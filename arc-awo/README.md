# Arc-awo — Decentralized Thrift & Rotating Savings on Arc

> **Akawo / Isusu / Ajo**, on-chain. Save daily, weekly or monthly in **native USDC** with full
> transparency, contract-enforced escrow, and automatic payouts — so no collector can ever run
> away with the money.

Built on **Arc** (Circle's stablecoin-native L1, chain ID 5042 / testnet 5042002) where USDC *is*
the gas token and settlement asset.

| | |
|---|---|
| **Classic Akawo** | A trusted collector hosts a savings plan; members contribute per period; withdraw full savings at cycle end minus a capped collector fee (≤ 1%). |
| **Isusu / Ajo (ROSCA)** | N members contribute every cycle; one member receives the whole pot each round — fixed transparent order or on-chain lottery (commit-reveal). |

- **Contracts**: Solidity 0.8.28 · Foundry · OpenZeppelin v5 · non-upgradeable escrows
- **Frontend**: Next.js 15 · TypeScript · Tailwind · shadcn/ui · wagmi/viem · RainbowKit
- **Tests**: 78 passing — unit, fuzz, integration, and a Foundry invariant suite proving
  `usdcBalance ≥ trackedLiabilities` under random action interleavings.

```
arc-awo/
├── ARCHITECTURE.md        ← design decisions, especially Arc USDC handling (READ THIS)
├── contracts/             ← Foundry project
│   ├── src/
│   │   ├── ArcawoFactory.sol        CREATE2 factory + registry + fee caps + referrals
│   │   ├── ArcawoPlan.sol           Classic Akawo collector thrift
│   │   ├── IsusuGroup.sol           ROSCA with arrears/redistribution rules
│   │   ├── CollectorReputation.sol  on-chain collector scores
│   │   ├── abstracts/EscrowBase.sol dual-rail USDC custody + solvency ledger
│   │   └── libraries/ArcUsdcLib.sol the single 18↔6 decimal boundary
│   ├── test/                unit + fuzz + invariant tests + Arc-semantics USDC mock
│   └── script/Deploy.s.sol
└── frontend/              ← Next.js app (mobile-first)
    └── src/app/  dashboard · create · browse · history · admin · plan/[addr] · group/[addr]
```

---

## Arc network configuration

| Parameter | Testnet | Mainnet |
|---|---|---|
| Network name | Arc Testnet | Arc |
| Chain ID | `5042002` | `5042` (`0x13b2`) |
| RPC URL | `https://rpc.testnet.arc.io` | `https://rpc.mainnet.arc.io` |
| Currency | USDC (native gas) | USDC (native gas) |
| Explorer | https://testnet.arcscan.app | https://explorer.arc.io |
| USDC (ERC-20 face) | `0x3600000000000000000000000000000000000000` | same address |
| Faucet | https://faucet.circle.com | — (bridge/withdraw from an exchange) |

### How Arc's native USDC model is handled (the one hard part)

On Arc there is **no ETH and no wrapped-native token**. USDC is the native asset and exposes
**one balance at two precisions**:

```
native view : msg.value / address.balance / gas   → 18 decimals
ERC-20 face : 0x3600…0000 transfer()/balanceOf()  → 6 decimals
              ↑ same money, 1e12 scale factor between the two views
```

Arc-awo's rule: **all accounting in 6-decimal USDC app units** (wallet/CCTP/exchange/indexer
parity), with the 18-decimal native rail scaled exactly once at `ArcUsdcLib`:

- `contributeNative{value: v}()` requires `v % 1e12 == 0` (whole micro-USDC) and credits `v / 1e12`
- `contribute()` uses the ERC-20 rail (`transferFrom`, Permit2-ready)
- both credit the same ledger; payouts always use the ERC-20 face (same pool on Arc)
- tests run under the same invariant via `MockArcUsdc`, which implements `balanceOf(a) = a.balance / 1e12`

Full rationale and diagrams: [`ARCHITECTURE.md`](./ARCHITECTURE.md).

---

## Getting started

### 0. Prerequisites

- [Foundry](https://getfoundry.sh) (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- Node.js 20+
- A wallet (MetaMask, Rabby, Rainbow…) — note: wallets without custom-gas-token support may
  label your USDC balance "ETH"; it is USDC.

### 1. Get testnet USDC

1. Open **https://faucet.circle.com** and select **Arc Testnet**.
2. Request USDC for your deployer/user wallet. (USDC is both your balance and your gas — one
   funding step covers everything.)
3. Add the network to your wallet with the table above if it isn't listed.

### 2. Build & test the contracts

```bash
cd contracts
forge build
forge test -vv          # 78 tests incl. fuzz + invariant suites
```

### 3. Deploy

```bash
cd contracts
cp .env.example .env    # fill PRIVATE_KEY, GUARDIAN_ADDRESS, TREASURY_ADDRESS
forge script script/Deploy.s.sol \
  --rpc-url arc_testnet \
  --broadcast \
  --verify --etherscan-api-key $BLOCK_EXPLORER_API_KEY
```

This deploys **`CollectorReputation`** then **`ArcawoFactory`** (plan/group instances are created
by users through the factory). The script logs both addresses.

### 4. Run the frontend

```bash
cd frontend
npm install
cp .env.example .env.local
# set NEXT_PUBLIC_FACTORY_ADDRESS and NEXT_PUBLIC_REPUTATION_ADDRESS from step 3
# optional: NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID (cloud.walletconnect.com)
npm run dev             # http://localhost:3000
```

To point at mainnet: `NEXT_PUBLIC_DEFAULT_CHAIN=mainnet` and use the mainnet addresses.

### 5. Local development (optional)

```bash
anvil                    # in one terminal (plain anvil; contracts don't depend on Arc opcodes)
cd contracts
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

The `MockArcUsdc` etched in tests reproduces Arc's dual-view USDC; on plain anvil the deployed
contracts use whatever code sits at `0x3600…0000` (deploy `MockArcUsdc` there with `vm.etch` or a
small setup script for full local parity).

---

## Deployment addresses

Populate after deploying (keep this table in your ops notes):

| Network | Contract | Address |
|---|---|---|
| Arc Testnet (5042002) | `CollectorReputation` | _pending — fill after `forge script`_ |
| Arc Testnet (5042002) | `ArcawoFactory` | _pending — fill after `forge script`_ |
| Arc Mainnet (5042) | `CollectorReputation` | _not yet deployed_ |
| Arc Mainnet (5042) | `ArcawoFactory` | _not yet deployed_ |

> This repository is delivered with everything **except** live deployment — deployment requires
> your own funded key (never paste one into a repo). One `forge script` run produces the two
> addresses above; the frontend picks them up via env vars.

---

## Protocol rules (quick reference)

**Akawo plan** — join (open or approval-gated) → contribute `amount` per period (daily/weekly/
monthly, catch-up allowed) → at cycle end `withdraw()` pays `contributed × (1 − feeBps − protocolFeeBps)`.
Early exit adds `earlyWithdrawPenaltyBps` (≤ 5%, to the collector fee pool). Fees accrue to the
collector **only when a member exits**. Pause blocks deposits, never exits. `rescueExcess` can
move only untracked donations — no admin path touches principal.

**Isusu group** — N members join (auto-finalize) → each round everyone pays `stake` (late = +
`lateFeeBps` into the pot) → winner claims `pot = collected + lateFees − fees` → N rounds → done.
Fixed order = join order; Lottery = commit-reveal with a liveness fallback. Defaulters owe
`stake + lateFee` payable any time (settled to the round's winner after the pot is claimed);
a winner in arrears cannot claim until cleared; an unclaimed pot can be redistributed pro-rata
to that round's payers after a timeout.

**Fee caps (factory-enforced):** collector ≤ 1% · early penalty ≤ 5% · late fee ≤ 5% · protocol
fee ≤ 1% (0 at launch).

**Reputation:** instances report outcomes to `CollectorReputation` (score 0–1000 from completions,
volume and defaults). Reports are `try/catch` — reputation can never block funds.

---

## Security model

- Non-upgradeable escrows; immutable per-instance parameters; factory-stamped protocol fields
- ReentrancyGuard + checks-effects-interactions + OpenZeppelin SafeERC20
- Solvency ledger: every instance tracks `trackedLiabilities`; invariant-tested
- Guardian pause (deposits only) + bounded `rescueExcess`; production wiring: owner → timelock,
  guardian → ops multisig
- Decimal safety enforced at one boundary (`ArcUsdcLib.toApp` reverts on sub-micro-dollar dust)
- Commit-reveal lottery cannot be frozen by a withholding collector (fallback selection)
- See `ARCHITECTURE.md` §7 for the full checklist

## Testing

```bash
cd contracts
forge test                       # everything
forge test --match-contract ArcawoPlan -vv
forge test --match-test testFuzz_ -vv
forge test --match-contract SolvencyInvariant  # invariant: 256 runs × random interleavings
```

The test suite etches `MockArcUsdc` at the canonical USDC address so every test executes under
Arc's real "one balance, two precisions" semantics — including mixed-rail deposits and native
value flows.

## Export & receipts

The History page scans on-chain events for the connected wallet (no database) and exports
**CSV** and **PDF-style receipts** via the browser print dialog. Plans expose per-period payment
bitmaps suitable for a custom indexer or The Graph (all state transitions emit events).

## Roadmap

Permit2 gasless approvals (predeploy exists on Arc) · yield on idle escrow · mobile-money
on-ramp via Circle CPN · official subgraph package · ERC-4337 gas sponsorship.

## License

MIT
