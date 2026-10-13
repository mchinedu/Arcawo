# Arc-awo — Smart Contract Architecture & Design Decisions

> Decentralized thrift contribution (Akawo / Isusu / Ajo) on **Arc**, Circle's stablecoin-native L1,
> using **native USDC** as the settlement asset.

---

## 1. Arc network facts this design is built on

| Property | Value | Source |
|---|---|---|
| Mainnet chain ID | `5042` (`0x13b2`) | docs.arc.io, Circle |
| Testnet chain ID | `5042002` | docs.arc.io |
| Mainnet RPC | `https://rpc.mainnet.arc.io` | docs.arc.io |
| Testnet RPC | `https://rpc.testnet.arc.io` | docs.arc.io |
| Gas token | **USDC** (no separate ETH-like gas token) | docs.arc.io |
| Native USDC precision | **18 decimals** (gas, `msg.value`, `address.balance`) | docs.arc.io |
| USDC ERC-20 interface | `0x3600000000000000000000000000000000000000`, **6 decimals** | docs.arc.io / Circle |
| Finality | Deterministic, sub-second (Malachite BFT); 1 confirmation = final | docs.arc.io |
| Block time | ~0.5 s | observed |
| Testnet faucet | https://faucet.circle.com | docs.arc.io |
| Testnet explorer | https://testnet.arcscan.app | docs.arc.io |
| CCTP domain | 26 | Circle |

### 1.1 The Arc USDC model — one balance, two precisions

On Arc there is **no wrapped-native token** and **no separate "gas coin"**. USDC *is* the native
asset. It exposes itself two ways over the **same pooled balance**:

```
native view   :  msg.value / address(this).balance / gas      → 18 decimals (wei-equivalent)
ERC-20 view   :  IERC20(0x3600…0000).balanceOf/transfer/…     → 6 decimals
```

`1 USDC = 1e18 native units = 1e6 ERC-20 units`, i.e. a **1e12 scale factor between the two views
of the same money**. Sending native value to a contract and calling `USDC.transfer()` are two rails
into one wallet. There is no wrap/unwrap step.

The #1 integration risk on Arc is **mixing the two precisions** (Circle's docs warn about this
explicitly). Quoting `1 USDC` as `1e18` on the ERC-20 rail silently moves a trillion dollars.

### 1.2 Our decision: canonical accounting in **6-decimal app units**

Arc-awo tracks every balance (contributions, pots, fees, penalties) in **USDC 6-decimal units** —
the same precision wallets, CCTP, Circle APIs, Permit2, and indexers use for Arc USDC. Rationale:

1. **Human correctness.** `₦`-style thrift amounts are whole micro-dollars ("5 USDC weekly").
   6 decimals is USDC's meaningful precision; 18-decimal dust is invisible to users and to the
   ERC-20 face.
2. **Ecosystem correctness.** Every tool a Nigerian fintech user touches (wallet token list,
   Circle faucet, exchange withdrawals, The Graph) displays USDC at 6 decimals. Internal 18-decimal
   accounting would force `/ 1e12` conversions at every boundary and invite precision bugs.
3. **Exactness at the rails.** Scaling is lossless when enforced:
   `native → app` requires `msg.value % 1e12 == 0` (revert on sub-micro-dollar dust);
   `app → native` multiplies exactly. No rounding, no trapped dust.
4. **Dual-rail deposits, single-rail accounting.** Members may pay with either rail:
   - **Token rail (primary):** `usdc.transferFrom(payer, plan, amt6)` — standard ERC-20/Permit2 UX.
   - **Native rail (sugar):** `contribute{value: v}()` where `v` is `amt6 * 1e12` — plain wallet
     "send USDC to this address" flows that UX research shows non-crypto users prefer.
   Both credit the *same* app-unit ledger. On Arc both arrive in one pool, so payouts via the
   ERC-20 face always work regardless of which rail funded them.

This is implemented once in `libraries/ArcUsdcLib.sol` (`toApp`, `toNative`, `USDC` constant) —
no other contract does decimal math.

**Testing implication:** on a local anvil chain, native balance and an ERC-20 token are *different*
pools, unlike Arc. The test mock `MockArcUsdc` reproduces Arc's true semantics: `balanceOf(a) ==
a.balance / 1e12` and `transfer` moves native balance via `vm.deal`. Every test therefore runs
against the real "one balance, two views" invariant.

---

## 2. System overview

```
                        ┌────────────────────────┐
                        │     ArcawoFactory      │  CREATE2 deploy + registry
                        │  owner (timelock)      │  config: fee caps, treasury
                        │  guardian (multisig)   │  pause (new activity only)
                        │  ReferralTracker       │  reputation wiring
                        └───────────┬────────────┘
              CREATE2               │               CREATE2
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌───────────────┐          ┌───────────────┐          ┌────────────────────┐
│ ArcawoPlan    │          │ IsusuGroup    │          │  (many instances)  │
│ Classic Akawo │          │ ROSCA/Isusu   │          │                    │
│ collector     │          │ rotating pot  │          │  CollectorRep.     │
│ escrow        │          │ (fixed/lottery)│         │  (shared, on-chain │
└───────┬───────┘          └───────┬───────┘          │   collector score) │
        │   report outcomes        │                  └────────────────────┘
        └──────────────┬───────────┘
                       ▼
             CollectorReputation
```

- **ArcawoFactory** — deploys `ArcawoPlan` and `IsusuGroup` clones via **CREATE2** (deterministic
  addresses, counterfactual deployment, cheap bulk creation), validates parameters against
  protocol-wide caps, keeps an on-chain registry (`plansOf`, `groupsOf`) and emits fully-decoded
  `PlanCreated` / `GroupCreated` events so indexers (The Graph or a custom poller) can rebuild all
  state from logs alone.
- **ArcawoPlan** — *Classic Akawo*: a collector hosts a savings plan; members contribute a fixed
  amount per period (daily / weekly / monthly); funds sit in contract escrow; members withdraw
  principal minus a small optional collector fee at the end of the cycle (or early, with penalty).
- **IsusuGroup** — *Isusu / Ajo ROSCA*: N members contribute a fixed amount every cycle; one member
  receives the whole pot each round; payout order is fixed (join order) or lottery (commit-reveal);
  the rotation completes after N rounds.
- **CollectorReputation** — outcome-based on-chain reputation for collectors (completed rounds,
  defaults, volume, on-time rate → 0–1000 score). Plans/groups report outcomes via `try/catch` so
  reputation failures can never block funds.

All contracts speak one asset: **Arc USDC** at `0x3600…0000` (6-dec app units internally).

---

## 3. ArcawoPlan (Classic Akawo) — state machine

### Parameters (immutable after creation)

| Param | Meaning | Bounds |
|---|---|---|
| `collector` | plan admin | set at create |
| `contributionAmount` | USDC per member per period (6-dec) | > 0 |
| `frequency` | 0 = Daily, 1 = Weekly, 2 = Monthly | enum |
| `startTime` | first period start | ≥ now |
| `durationPeriods` | number of periods in the cycle | 1 … 256 |
| `feeBps` | collector fee on each withdrawal | ≤ factory cap (100 = 1%) |
| `earlyWithdrawPenaltyBps` | penalty on early exit, credited to collector fee pool | ≤ factory cap (500 = 5%) |
| `approvalRequired` | collector must approve joiners | bool |
| `maxMembers` | 0 = unlimited | ≤ 5 000 |
| `metadataURI` | off-chain description (group name, rules, WhatsApp link…) | string |

Period `i` covers `[startTime + i·P, startTime + (i+1)·P)` where
`P ∈ {1 days, 7 days, 30 days}` ("monthly" = 30 days for determinism — documented).

### Lifecycle

```
create ──▶ join/approve ──▶ contribute(period i) ──…──▶ period elapsed
                                                     │
                          collector endPlan() ───────┤ (optional early end)
                                                     ▼
                                    withdraw()  [fee taken]
                                    withdrawEarly() [fee + penalty]
                                                     ▼
                                    collector claimFee() ──▶ close (reputation report)
```

1. **Join** — open or approval-gated. Members are recorded with a per-member **contribution
   bitmap** (`uint256`, one bit per period — supports up to 256 periods in one storage slot).
   Catch-up: members may pay missed periods any time before the plan ends.
2. **Contribute** — `contribute(periods[])` or `contributeNative{value:}`; each period's payment is
   exactly `contributionAmount`; double-payment of a period reverts (`AlreadyContributed`).
3. **Auto-advancement** — `currentPeriod` is pure timestamp math: no keepers, no cron. On Arc's
   0.5 s blocks the UI updates every block for free.
4. **Withdraw** — after cycle end (or after `endPlan`):
   `payout = contributed × (10 000 − feeBps) / 10 000`. Early exit additionally pays
   `payout × earlyPenaltyBps / 10 000` to the collector fee pool (compensates the collector's
   curation and discourages churn that breaks group savings habits).
5. **Fees** — accrue to the collector *only when a member exits*; if a member never withdraws, the
   collector never earns a fee on that balance. Collector claims with `claimFee()`.

### Deliberate safety decisions

- **Pause never traps funds.** Guardian pause blocks *new* joins/contributions only; `withdraw` /
  `withdrawEarly` / `claimFee` stay live while paused. A rug-pull via pause is impossible.
- **No admin sweep of user principal.** `rescueExcess` can move only
  `usdc.balanceOf(this) − trackedLiabilities` — i.e. unsolicited donations. Emergency withdraw by
  multisig/timelock exists (the nice-to-have) but mathematically cannot touch tracked funds.
- **Fee & penalty caps enforced at the factory**, not just at creation params: even a malicious
  factory upgrade path cannot raise them retroactively (per-instance immutables).
- **ReentrancyGuard + checks-effects-interactions** on every state+transfer function; USDC moved
  with OpenZeppelin `SafeERC20`.

---

## 4. IsusuGroup (ROSCA) — state machine

### Parameters

| Param | Meaning | Bounds |
|---|---|---|
| `collector` | coordinator (auto-enrolled as member 0 if `collectorPlays`) | |
| `contributionAmount` | fixed stake per member per round (6-dec) | > 0 |
| `frequency` | Daily / Weekly / Monthly | enum |
| `memberCount` | exact group size N (rounds = N) | 2 … 100 |
| `payoutMode` | `0` FixedOrder (join order) · `1` Lottery (commit-reveal) | enum |
| `feeBps` | collector fee taken from each claimed pot | ≤ 1% |
| `lateFeeBps` | penalty on late round payment, added to that round's pot | ≤ 5% |
| `startDelay` | seconds between group finalization and round 1 | e.g. 1 days |
| `metadataURI` | off-chain description | string |

### Lifecycle

```
create ─▶ join (until N) ─▶ finalize (+ commit in lottery mode)
   ─▶ round r: contribute(r) ─▶ [grace] ─▶ select winner ─▶ claimPot(r)
   … N rounds … ─▶ close (reputation report)
```

1. **Join** — first N joiners lock the roster; `finalize()` fires automatically when full
   (FixedOrder payout order = join order, fully transparent and unbiased; no hidden shuffle).
2. **Contribute(r)** — window `[start + r·P, start + (r+1)·P)`, plus a **grace period**
   (`GRACE = min(P, 1 days)`) during which late payers must also pay `lateFeeBps` into the pot.
   Pre-paying future rounds is intentionally disallowed (keeps defaults visible).
3. **Pot accounting** — `pot(r) = collected(r) + lateFees(r) − collectorFee(collected)`. The pot
   is *what the group actually paid in that round* — a defaulter cannot dilute a past winner.
4. **Winner selection**
   - *FixedOrder*: `winner(r) = order[r]` — auditable, zero trust.
   - *Lottery*: collector **commits** `keccak256(secret)` at finalize; after round r's window,
     anyone calls `requestSelection(r)`; collector **reveals** `secret`; winner =
     `keccak256(secret, r, block.prevrandao, requestBlockHash) % remainingEligible`. The secret is
     ground-resistant because `prevrandao`/blockhash enter at *reveal* time. If the collector
     withholds the reveal past `REVEAL_TIMEOUT`, a fallback selector uses the request-block hash
     + prevrandao alone (documented: adequate for thrift stakes; not for casinos) — the collector
     can never freeze the group.
5. **Defaults & arrears** — a member with unpaid past rounds has `arrears = owed + late fees`.
   They may `clearArrears()` at any time. A member **cannot claim their own pot while in arrears**;
   if their pot goes unclaimed for `ARREARS_TIMEOUT` after their scheduled round, anyone may
   `redistribute(round)` to that round's on-time contributors pro-rata. Nobody's money is ever
   confiscated to the collector.
6. **Close** — after all rounds are resolved, collector claims accrued fees, outcome is reported to
   the reputation contract.

### Why commit-reveal instead of Chainlink VRF?

Arc is new; VRF availability/latency on a 0.5 s-finality chain is not something a thrift product
should bet on at launch. Commit-reveal needs no external oracle, is fully on-chain, and the
withholding fallback keeps liveness. The randomness interface is isolated in
`_selectWinner()` so a VRF adapter can replace it later without touching accounting.

---

## 5. Cross-cutting design decisions

| Decision | Choice | Why |
|---|---|---|
| Accounting unit | 6-dec USDC app units | §1.2 — wallet/CCTP/indexer parity, exact scaling |
| Deposits | dual-rail (`transferFrom` + payable native) | matches Arc's dual-view UX; plain-send friendly |
| Withdrawals | ERC-20 face only | standard wallet receipt UX; pool is shared on Arc |
| Instance deployment | CREATE2 via factory | deterministic addresses, cheap, indexable |
| Access control | Ownable2Step factory; per-instance `collector` + `guardian` | ops multisig + timelock ready |
| Upgradeability | **None** (non-proxy) | thrift escrow must be immutable; migrations = new plans |
| Emergency | pause + `rescueExcess` (untracked only) | no admin path to user principal |
| Reentrancy | OZ `ReentrancyGuard` + CEI + `SafeERC20` | standard defense |
| Events | full state transitions, indexed addresses/ids | The Graph / custom indexers |
| Time | `block.timestamp` periods (30-day month) | deterministic; Arc ~0.5 s blocks, no keeper needed |
| Gas | bitmaps for period tracking, packed structs, immutable asset | Arc fees are sub-cent USDC but mobile users still care |
| Decimal bug class | eliminated at `ArcUsdcLib` boundary | the one Arc-specific hazard, handled once |
| Referral | recorded at create/join, optional share of protocol fee | protocol fee defaults to 0 → no surprise economics |
| Reputation | outcome callbacks with `try/catch` | cannot block funds; score = f(completed, defaults, volume) |

## 6. Fee model (all bps, all on 6-dec USDC)

```
member withdraw (Plan):   payout = contributed × (10000 − feeBps) / 10000
                          early: payout −= payout × earlyPenaltyBps / 10000   (to collector)
protocol fee (optional):  taken from the fee slice, split treasury / referrer
                          default protocolFeeBps = 0 (disabled at launch)
group pot claim:          collector fee = collected(r) × feeBps / 10000
                          winner gets collected + lateFees − collectorFee
```

Caps enforced by factory: `collectorFeeBps ≤ 100` (1%), `penaltyBps ≤ 500` (5%),
`lateFeeBps ≤ 500` (5%), `protocolFeeBps ≤ 100` (1%).

## 7. Security checklist

- [x] Reentrancy guards on all value-moving entry points
- [x] Checks-effects-interactions everywhere
- [x] `SafeERC20` for USDC movement
- [x] Input validation + bound checks at factory (single choke point) and at instances
- [x] Precision safety (`msg.value % 1e12 == 0`, no 18/6 mixing outside `ArcUsdcLib`)
- [x] Pause cannot block user exits
- [x] `rescueExcess` cannot touch tracked liabilities (invariant-tested)
- [x] Fee/penalty caps immutable per instance
- [x] Commit-reveal with liveness fallback (no permanent lock by a malicious collector)
- [x] Solvency invariant in tests: `usdc.balanceOf(instance) ≥ trackedLiabilities`
- [x] Fuzz tests on fee math, scaling, pot math
- [x] No delegatecall, no selfdestruct, no tx.origin, no unbounded loops over members in
      write paths (N ≤ 100 bounded for ROSCA; plan member ops are O(1))

## 8. Out of scope for v1 (roadmap)

- Yield on idle escrow (Aave-style) — legal + risk surface, listed as nice-to-have
- Mobile money on/off-ramp (Circle CPN / local PSP integration)
- Permit2 gasless approvals (address is a canonical Arc predeploy — wired next)
- The Graph subgraph package (events designed for it; custom event poller ships in the frontend)
