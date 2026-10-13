// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EscrowBase} from "./abstracts/EscrowBase.sol";
import {ICollectorReputation} from "./interfaces/ICollectorReputation.sol";
import {ArcUsdcLib} from "./libraries/ArcUsdcLib.sol";

/// @title IsusuGroup — Rotating Savings & Credit Association (Isusu / Ajo) on Arc USDC
/// @notice N members each contribute a fixed USDC stake every cycle; one member receives the
///         whole pot each round; after N rounds everyone has contributed N times and received
///         the pot once. Funds live in contract escrow — the coordinator ("collector") can never
///         touch member principal.
///
///         Payout order:
///         • FixedOrder — transparent join order (index i is paid in round i). Zero trust.
///         • Lottery    — commit-reveal selection per round (see `_pick`/`reveal`/`fallbackSelect`).
///
///         Default handling: a missed round is an arrears debt of `stake + lateFee`, payable any
///         time. Arrears payers compensate the round's winner directly once that pot is claimed
///         (a default can never dilute a pot already paid). A winner in arrears cannot claim their
///         own pot until cleared; an unclaimed pot can be redistributed pro-rata to that round's
///         payers after a timeout. Collector fees are capped and only ever taken from pots.
///
///         Accounting is in 6-decimal USDC app units (see `ArcUsdcLib`); deposits accept both
///         Arc rails (ERC-20 `transferFrom` and native `msg.value`).
contract IsusuGroup is EscrowBase {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum Frequency {
        Daily,
        Weekly,
        Monthly
    }

    enum PayoutMode {
        FixedOrder,
        Lottery
    }

    enum GroupState {
        Open, // filling up
        Active, // finalized: rounds in progress
        Completed // all rounds resolved (or cancelled while Open)
    }

    struct GroupParams {
        address collector;
        address guardian;
        uint256 contributionAmount; // app units (6-dec USDC) per member per round
        Frequency frequency;
        uint16 memberCount; // exact group size N (rounds = N), 2..100
        PayoutMode payoutMode;
        uint16 feeBps; // collector fee taken from each claimed pot
        uint16 lateFeeBps; // penalty on payments after the round window, added to that pot
        uint16 protocolFeeBps; // optional protocol fee taken from each claimed pot
        uint64 startDelay; // seconds between finalization and round 1
        address treasury;
        address reputation; // CollectorReputation, or address(0) to disable
        bool collectorPlays; // collector is auto-enrolled as member 0
        string metadataURI;
    }

    struct Member {
        uint32 index; // position in payout order (FixedOrder round index)
        bool joined;
        bool won; // pot received
        uint32 roundsPaid;
        uint256 paidBitmap; // bit r set => round r paid (supports 256 rounds; N <= 100)
        uint256 lateFeesPaid;
        address referrer;
    }

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    uint256 public constant MIN_MEMBERS = 2;
    uint256 public constant MAX_MEMBERS = 100;
    uint256 public constant MAX_CONTRIBUTION = 1_000_000e6; // $1M stake
    uint256 public constant REVEAL_TIMEOUT = 1 days;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    GroupParams private _params;
    GroupState public state;

    mapping(address => Member) private _members;
    address[] private _memberList; // join order == FixedOrder payout order

    uint64 public startTime; // set at finalize: now + startDelay
    uint256 public totalContributed; // gross across all rounds (app units)

    // Per-round state (N <= 100)
    mapping(uint256 => uint256) public collected; // round => stake sum
    mapping(uint256 => uint256) public lateFeesOf; // round => late fee sum (to pot)
    mapping(uint256 => bool) public potClaimed;
    mapping(uint256 => address) public winnerOf;
    mapping(uint256 => bool) public selectionRequested;
    mapping(uint256 => uint256) public selectionRequestBlock;
    mapping(uint256 => uint256) public revealDeadline;

    uint256 public resolvedRounds; // pots claimed or redistributed
    uint256 public lateEvents; // late/arrears payments observed (reputation input)

    // Lottery (commit-reveal)
    bytes32 public commitment; // keccak256(secret), optional but recommended
    bool public anySelectionRequested;

    uint256 public accruedCollectorFees;
    uint256 public accruedProtocolFees;
    bool public reported;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event MemberJoined(address indexed member, uint32 index, address indexed referrer);
    event GroupFinalized(uint64 startTime, uint256 memberCount);
    event Contributed(
        address indexed member,
        uint256 indexed round,
        uint256 amount,
        uint256 lateFee,
        bool nativeRail,
        bool arrearsSettlement
    );
    event PotClaimed(uint256 indexed round, address indexed winner, uint256 pot, uint256 collectorFee);
    event PotRedistributed(uint256 indexed round, uint256 pot, uint256 recipients);
    event SelectionRequested(uint256 indexed round, uint256 requestBlock);
    event WinnerRevealed(uint256 indexed round, address indexed winner, bytes32 entropy);
    event WinnerSelectedFallback(uint256 indexed round, address indexed winner, bytes32 entropy);
    event LotteryCommitted(bytes32 commitment);
    event CollectorFeesClaimed(address indexed collector, uint256 amount);
    event ProtocolFeesClaimed(address indexed treasury, uint256 amount);
    event GroupCompleted(uint256 totalContributed);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error BadParams();
    error GroupNotOpen();
    error GroupNotActive();
    error GroupNotCompleted();
    error AlreadyMember();
    error NotMember();
    error GroupFull();
    error BadRound(uint256 round);
    error FutureRound(uint256 round);
    error AlreadyPaid(uint256 round);
    error RoundVoided(uint256 round);
    error WrongNativeValue(uint256 expectedNative);
    error NotWinner();
    error InArrears(uint256 unpaidRounds);
    error PotNotClaimable();
    error PotAlreadyClaimed();
    error SelectionNotRequested();
    error SelectionAlreadyDone();
    error BadCommitment();
    error CommitmentAlreadySet();
    error RevealNotAllowed();
    error RevealTimeoutNotElapsed();
    error NothingToClaim();
    error BadState();

    // ---------------------------------------------------------------------
    // Construction (factory-only, via CREATE2)
    // ---------------------------------------------------------------------

    constructor(GroupParams memory params_) EscrowBase(params_.collector, params_.guardian) {
        _validate(params_);
        _params = params_;

        if (params_.collectorPlays) {
            // Collector is coordinator and member 0 (paid first in FixedOrder — traditional).
            _members[params_.collector] = Member({
                index: 0,
                joined: true,
                won: false,
                roundsPaid: 0,
                paidBitmap: 0,
                lateFeesPaid: 0,
                referrer: address(0)
            });
            _memberList.push(params_.collector);
            emit MemberJoined(params_.collector, 0, address(0));
        }
    }

    function _validate(GroupParams memory p) internal pure {
        if (p.collector == address(0) || p.guardian == address(0) || p.treasury == address(0)) {
            revert BadParams();
        }
        if (p.contributionAmount == 0 || p.contributionAmount > MAX_CONTRIBUTION) revert BadParams();
        if (p.memberCount < MIN_MEMBERS || p.memberCount > MAX_MEMBERS) revert BadParams();
    }

    // ---------------------------------------------------------------------
    // Membership & start
    // ---------------------------------------------------------------------

    /// @notice Join the group (first-come, first-served). The last join finalizes the group.
    function join(address referrer) external whenNotPaused {
        if (state != GroupState.Open) revert GroupNotOpen();
        if (_members[msg.sender].joined) revert AlreadyMember();
        if (_memberList.length >= _params.memberCount) revert GroupFull();

        uint32 index = uint32(_memberList.length);
        _members[msg.sender] = Member({
            index: index,
            joined: true,
            won: false,
            roundsPaid: 0,
            paidBitmap: 0,
            lateFeesPaid: 0,
            referrer: referrer == msg.sender ? address(0) : referrer
        });
        _memberList.push(msg.sender);
        emit MemberJoined(msg.sender, index, referrer);

        if (_memberList.length == _params.memberCount) {
            _finalize();
        }
    }

    function _finalize() internal {
        state = GroupState.Active;
        startTime = uint64(block.timestamp + _params.startDelay);
        emit GroupFinalized(startTime, _params.memberCount);
    }

    /// @notice Cancel an unfilled group (no funds can be held while Open — joins are free).
    function cancel() external onlyCollector {
        if (state != GroupState.Open) revert BadState();
        state = GroupState.Completed;
        reported = true; // nothing to report
    }

    // ---------------------------------------------------------------------
    // Contributions (dual-rail). Also settles arrears for past rounds.
    // ---------------------------------------------------------------------

    /// @notice Pay `round`'s stake on the ERC-20 rail. Late payments (after the round window)
    ///         include `lateFeeBps` on top. Payments for a claimed pot settle arrears directly
    ///         to that round's winner.
    function contribute(uint256 round) external nonReentrant whenNotPaused {
        (uint256 amount, uint256 lateFee) = _requirePayment(round);
        _pullToken(msg.sender, amount + lateFee);
        _recordPayment(round, amount, lateFee, false);
    }

    /// @notice Native-rail payment of `round`'s stake (plain wallet send semantics).
    function contributeNative(uint256 round) external payable nonReentrant whenNotPaused {
        (uint256 amount, uint256 lateFee) = _requirePayment(round);
        uint256 expectedNative = ArcUsdcLib.toNative(amount + lateFee);
        if (msg.value != expectedNative) revert WrongNativeValue(expectedNative);
        _pullNative(msg.value);
        _recordPayment(round, amount, lateFee, true);
    }

    function _requirePayment(uint256 round)
        internal
        view
        returns (uint256 amount, uint256 lateFee)
    {
        if (state != GroupState.Active && state != GroupState.Completed) revert GroupNotActive();
        if (round >= _params.memberCount) revert BadRound(round);
        // No pre-paying future rounds: defaults must stay visible.
        if (round > currentRound()) revert FutureRound(round);

        Member storage m = _members[msg.sender];
        if (!m.joined) revert NotMember();
        uint256 bit = 1 << round;
        if (m.paidBitmap & bit != 0) revert AlreadyPaid(round);
        // A redistributed round's slot was voided: there is no recipient left to settle.
        if (potClaimed[round] && winnerOf[round] == address(0)) revert RoundVoided(round);

        amount = _params.contributionAmount;
        if (block.timestamp > roundEnd(round)) {
            lateFee = (amount * _params.lateFeeBps) / 10_000;
        }
    }

    function _recordPayment(uint256 round, uint256 amount, uint256 lateFee, bool nativeRail) internal {
        Member storage m = _members[msg.sender];
        m.paidBitmap |= (1 << round);
        unchecked {
            m.roundsPaid += 1;
        }
        m.lateFeesPaid += lateFee;
        totalContributed += amount + lateFee;
        if (lateFee != 0) {
            unchecked {
                lateEvents += 1;
            }
        }

        if (!potClaimed[round]) {
            // Funds stay in escrow as part of this round's pot.
            collected[round] += amount;
            lateFeesOf[round] += lateFee;
            emit Contributed(msg.sender, round, amount, lateFee, nativeRail, false);
        } else {
            // Arrears settlement: compensate the winner whose pot was short this round.
            address winner = winnerOf[round];
            _push(winner, amount + lateFee);
            emit Contributed(msg.sender, round, amount, lateFee, nativeRail, true);
        }
    }

    // ---------------------------------------------------------------------
    // Winner selection
    // ---------------------------------------------------------------------

    /// @notice Commit the lottery secret. Allowed only before any selection is requested, so a
    ///         collector can never grind a secret against a known request. The secret is
    ///         subsequently revealed per round mixed with post-commit chain entropy.
    function commit(bytes32 commitmentHash) external onlyCollector {
        if (_params.payoutMode != PayoutMode.Lottery) revert BadState();
        if (commitment != 0) revert CommitmentAlreadySet();
        if (anySelectionRequested) revert SelectionAlreadyDone();
        if (commitmentHash == 0) revert BadCommitment();
        commitment = commitmentHash;
        emit LotteryCommitted(commitmentHash);
    }

    /// @notice Open selection for a closed round (Lottery mode). Permissionless.
    function requestSelection(uint256 round) external {
        if (state != GroupState.Active) revert GroupNotActive();
        if (_params.payoutMode != PayoutMode.Lottery) revert BadState();
        if (round >= _params.memberCount) revert BadRound(round);
        if (block.timestamp <= roundEnd(round)) revert PotNotClaimable();
        if (selectionRequested[round]) revert SelectionAlreadyDone();
        if (potClaimed[round]) revert PotAlreadyClaimed();

        selectionRequested[round] = true;
        selectionRequestBlock[round] = block.number;
        revealDeadline[round] = block.timestamp + REVEAL_TIMEOUT;
        anySelectionRequested = true;
        emit SelectionRequested(round, block.number);
    }

    /// @notice Collector reveals the secret to select the winner of `round`.
    function reveal(bytes32 secret, uint256 round) external {
        if (!selectionRequested[round]) revert SelectionNotRequested();
        if (winnerOf[round] != address(0)) revert SelectionAlreadyDone();
        if (commitment == 0 || keccak256(abi.encodePacked(secret)) != commitment) revert BadCommitment();

        bytes32 entropy = keccak256(
            abi.encodePacked(secret, round, block.prevrandao, blockhash(selectionRequestBlock[round]))
        );
        _selectWinner(round, entropy);
        emit WinnerRevealed(round, winnerOf[round], entropy);
    }

    /// @notice Liveness fallback: after the reveal timeout (or when no commitment exists) anyone
    ///         can select the winner from chain entropy alone. A collector can never freeze a
    ///         group by withholding the reveal.
    function fallbackSelect(uint256 round) external {
        if (!selectionRequested[round]) revert SelectionNotRequested();
        if (winnerOf[round] != address(0)) revert SelectionAlreadyDone();
        if (commitment != 0 && block.timestamp < revealDeadline[round]) revert RevealTimeoutNotElapsed();

        bytes32 entropy = keccak256(
            abi.encodePacked(bytes32(0), round, block.prevrandao, blockhash(selectionRequestBlock[round]))
        );
        _selectWinner(round, entropy);
        emit WinnerSelectedFallback(round, winnerOf[round], entropy);
    }

    /// @dev Pick the (entropy % remaining)-th member who has not won yet. O(N), N <= 100.
    function _selectWinner(uint256 round, bytes32 entropy) internal {
        uint256 remaining;
        uint256 total = _memberList.length;
        for (uint256 i = 0; i < total; ++i) {
            if (!_members[_memberList[i]].won) {
                unchecked {
                    remaining += 1;
                }
            }
        }
        if (remaining == 0) revert BadState();

        uint256 target = uint256(entropy) % remaining;
        for (uint256 i = 0; i < total; ++i) {
            address candidate = _memberList[i];
            if (!_members[candidate].won) {
                if (target == 0) {
                    winnerOf[round] = candidate;
                    return;
                }
                unchecked {
                    target -= 1;
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Pot claims & redistribution
    // ---------------------------------------------------------------------

    /// @notice Winner claims the pot of `round` (after the round window closes). Requires the
    ///         winner to have paid every round up to and including `round`.
    function claimPot(uint256 round) external nonReentrant returns (uint256 pot) {
        if (state != GroupState.Active && state != GroupState.Completed) revert BadState();
        if (round >= _params.memberCount) revert BadRound(round);
        if (potClaimed[round]) revert PotAlreadyClaimed();
        if (block.timestamp <= roundEnd(round)) revert PotNotClaimable();

        address winner = _resolveWinner(round);
        if (winner != msg.sender) revert NotWinner();

        uint256 unpaid = _unpaidCount(msg.sender, round);
        if (unpaid != 0) revert InArrears(unpaid);

        pot = _payPot(round, winner);
    }

    /// @dev FixedOrder winner is implicit; Lottery winner must be selected first.
    function _resolveWinner(uint256 round) internal view returns (address winner) {
        winner = winnerOf[round];
        if (winner != address(0)) return winner;
        if (_params.payoutMode == PayoutMode.FixedOrder) {
            return _memberList[round];
        }
        revert SelectionNotRequested();
    }

    function _payPot(uint256 round, address winner) internal returns (uint256 pot) {
        uint256 gross = collected[round] + lateFeesOf[round];
        uint256 collectorFee = (collected[round] * _params.feeBps) / 10_000;
        uint256 protocolFee = (collected[round] * _params.protocolFeeBps) / 10_000;
        pot = gross - collectorFee - protocolFee;

        potClaimed[round] = true;
        if (winnerOf[round] == address(0)) winnerOf[round] = winner;
        _members[winner].won = true;
        accruedCollectorFees += collectorFee;
        accruedProtocolFees += protocolFee;
        unchecked {
            resolvedRounds += 1;
        }

        _push(winner, pot);
        emit PotClaimed(round, winner, pot, collectorFee);
        _maybeComplete();
    }

    /// @notice Redistribute an unclaimed pot pro-rata to that round's payers after the timeout.
    ///         Permissionless liveness: a vanished winner cannot strand the round. The rotation
    ///         slot is voided (nobody is marked `won`); shares are weighted by each payer's
    ///         payment into the pot (equal stakes → equal shares; late-fee component splits
    ///         equally), with sub-micro-unit rounding dust credited to the collector fee pool.
    function redistribute(uint256 round) external nonReentrant returns (uint256 pot) {
        if (state != GroupState.Active && state != GroupState.Completed) revert BadState();
        if (round >= _params.memberCount) revert BadRound(round);
        if (potClaimed[round]) revert PotAlreadyClaimed();
        if (block.timestamp <= roundEnd(round) + redistributionTimeout()) revert PotNotClaimable();

        uint256 gross = collected[round] + lateFeesOf[round];
        uint256 collectorFee = (collected[round] * _params.feeBps) / 10_000;
        uint256 protocolFee = (collected[round] * _params.protocolFeeBps) / 10_000;
        pot = gross - collectorFee - protocolFee;

        potClaimed[round] = true;
        accruedCollectorFees += collectorFee;
        accruedProtocolFees += protocolFee;
        unchecked {
            resolvedRounds += 1;
        }
        // A redistributed round never marks anyone `won` (the rotation slot is voided).

        uint256 total = _memberList.length;
        uint256 payers;
        for (uint256 i = 0; i < total; ++i) {
            if (_members[_memberList[i]].paidBitmap & (1 << round) != 0) {
                unchecked {
                    payers += 1;
                }
            }
        }

        if (payers != 0 && pot != 0) {
            uint256 share = pot / payers;
            uint256 distributed;
            for (uint256 i = 0; i < total; ++i) {
                address member = _memberList[i];
                if (_members[member].paidBitmap & (1 << round) != 0) {
                    distributed += share;
                    _push(member, share);
                }
            }
            // Rounding dust (< 1 micro-USDC per payer) goes to the collector fee pool.
            uint256 dust = pot - distributed;
            if (dust != 0) {
                accruedCollectorFees += dust;
            }
        }

        emit PotRedistributed(round, pot, payers);
        _maybeComplete();
    }

    function _maybeComplete() internal {
        if (resolvedRounds < _params.memberCount) return;
        state = GroupState.Completed;
        emit GroupCompleted(totalContributed);
        _report();
    }

    // ---------------------------------------------------------------------
    // Fees
    // ---------------------------------------------------------------------

    function claimFees() external nonReentrant onlyCollector returns (uint256 amount) {
        amount = accruedCollectorFees;
        if (amount == 0) revert NothingToClaim();
        accruedCollectorFees = 0;
        _push(collector, amount);
        emit CollectorFeesClaimed(collector, amount);
    }

    function claimProtocolFees() external nonReentrant returns (uint256 amount) {
        if (msg.sender != _params.treasury) revert NotAuthorized();
        amount = accruedProtocolFees;
        if (amount == 0) revert NothingToClaim();
        accruedProtocolFees = 0;
        _push(_params.treasury, amount);
        emit ProtocolFeesClaimed(_params.treasury, amount);
    }

    // ---------------------------------------------------------------------
    // Lifecycle / reputation
    // ---------------------------------------------------------------------

    function _report() internal {
        if (reported || _params.reputation == address(0)) return;
        reported = true;
        try ICollectorReputation(_params.reputation).reportGroupOutcome(
            collector, totalContributed, true, lateEvents
        ) {} catch {
            // Best-effort: never block funds.
        }
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Full immutable group parameters (explicit getter: includes metadataURI).
    function params() external view returns (GroupParams memory) {
        return _params;
    }

    function periodLength() public view returns (uint256) {
        Frequency f = _params.frequency;
        if (f == Frequency.Daily) return 1 days;
        if (f == Frequency.Weekly) return 7 days;
        return 30 days;
    }

    /// @notice Seconds after a round window before its unclaimed pot may be redistributed.
    function redistributionTimeout() public view returns (uint256) {
        uint256 p = periodLength();
        uint256 t = 2 * p;
        return t > 7 days ? 7 days : t;
    }

    function roundEnd(uint256 round) public view returns (uint256) {
        return uint256(startTime) + (round + 1) * periodLength();
    }

    /// @notice Current round index while Active/Completed (clamped to N-1 after the last window).
    function currentRound() public view returns (uint256) {
        if (state == GroupState.Open || block.timestamp < startTime) return 0;
        uint256 elapsed = block.timestamp - startTime;
        uint256 round = elapsed / periodLength();
        uint256 last = _params.memberCount - 1;
        return round > last ? last : round;
    }

    /// @notice Number of rounds `member` has not paid among rounds [0, through].
    function _unpaidCount(address member, uint256 through) internal view returns (uint256 count) {
        uint256 bitmap = _members[member].paidBitmap;
        for (uint256 r = 0; r <= through; ++r) {
            if (bitmap & (1 << r) == 0) {
                unchecked {
                    count += 1;
                }
            }
        }
    }

    /// @notice Rounds `member` has not paid among rounds [0, `through`].
    function unpaidRounds(address member, uint256 through) external view returns (uint256 count) {
        return _unpaidCount(member, through);
    }

    function memberOf(address member) external view returns (Member memory) {
        return _members[member];
    }

    function memberAt(uint256 index) external view returns (address) {
        return _memberList[index];
    }

    function memberCount() external view returns (uint256) {
        return _memberList.length;
    }

    /// @notice Pot size of `round` if claimed now (before fees are deducted from collected).
    function potOf(uint256 round) external view returns (uint256) {
        uint256 gross = collected[round] + lateFeesOf[round];
        return gross - (collected[round] * _params.feeBps) / 10_000 - (collected[round] * _params.protocolFeeBps) / 10_000;
    }
}
