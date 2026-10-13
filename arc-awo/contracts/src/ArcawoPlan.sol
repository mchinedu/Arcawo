// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EscrowBase} from "./abstracts/EscrowBase.sol";
import {ICollectorReputation} from "./interfaces/ICollectorReputation.sol";
import {ArcUsdcLib} from "./libraries/ArcUsdcLib.sol";

/// @title ArcawoPlan — Classic Akawo (collector-hosted thrift savings) on Arc USDC
/// @notice A trusted collector hosts a savings plan. Members contribute a fixed USDC amount
///         every period (daily / weekly / monthly). Funds are held in contract escrow — the
///         collector can never touch member principal. At the end of the cycle (or when the
///         collector ends the plan) members withdraw their full savings minus a small optional
///         collector fee. Early exit is allowed with a capped penalty credited to the collector.
///
///         Accounting is in 6-decimal USDC app units (see `ArcUsdcLib`). Deposits accept both
///         Arc rails: ERC-20 `transferFrom` and plain native `msg.value`.
///
///         Period `i` covers `[startTime + i·P, startTime + (i+1)·P)` with
///         `P ∈ {1 days, 7 days, 30 days}`. "Monthly" is a deterministic 30 days. Cycle
///         progression is pure timestamp math — no keepers.
contract ArcawoPlan is EscrowBase {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum Frequency {
        Daily,
        Weekly,
        Monthly
    }

    /// @notice Immutable plan parameters. Validated by the factory at creation.
    struct PlanParams {
        address collector;
        address guardian;
        uint256 contributionAmount; // app units (6-dec USDC) per member per period
        Frequency frequency;
        uint64 startTime; // first period start (unix seconds)
        uint16 durationPeriods; // number of periods in the cycle (1..256)
        uint16 feeBps; // collector fee on each withdrawal (<= factory cap)
        uint16 earlyWithdrawPenaltyBps; // penalty on early exit, to collector fee pool
        uint16 protocolFeeBps; // optional protocol fee on each withdrawal
        uint16 referralShareBps; // share of protocol fee paid to the member's referrer
        address treasury; // protocol fee destination (non-referrer share)
        address reputation; // CollectorReputation, or address(0) to disable
        bool approvalRequired; // collector must approve each joiner
        uint16 maxMembers; // 0 = unlimited
        string metadataURI; // off-chain description (group name, rules, chat link…)
    }

    struct Member {
        uint64 joinedAt;
        uint64 exitedAt; // 0 until the member withdraws
        uint32 contributedPeriods; // number of periods paid
        bool approved; // always true unless approvalRequired
        bool withdrawn;
        uint256 totalContributed; // gross contributions (app units)
        uint256 contributionBitmap; // bit i set => period i paid (supports 256 periods)
        address referrer;
    }

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    uint256 public constant MAX_PERIODS = 256;
    uint256 public constant MAX_CONTRIBUTION = 1_000_000e6; // $1M per period per member
    uint256 public constant MAX_MEMBERS = 5_000;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    PlanParams private _params;

    mapping(address => Member) private _members;
    address[] private _memberList;

    uint256 public totalContributed; // gross plan-wide contributions
    uint256 public accruedCollectorFees; // unclaimed collector fees + penalties
    uint256 public accruedProtocolFees; // unclaimed protocol fees
    mapping(address => uint256) public accruedReferralFees; // unclaimed referrer shares
    mapping(address => uint256) public claimed; // net amounts withdrawn per member

    bool public ended; // collector ended the plan early, or cycle finished
    bool public reported; // outcome reported to reputation

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event MemberJoined(address indexed member, address indexed referrer);
    event MemberApproved(address indexed member);
    event Contributed(
        address indexed member,
        uint256 indexed period,
        uint256 amount,
        bool nativeRail
    );
    event Withdrawn(
        address indexed member,
        uint256 gross,
        uint256 payout,
        uint256 collectorFee,
        uint256 protocolFee,
        uint256 penalty,
        bool early
    );
    event CollectorFeesClaimed(address indexed collector, uint256 amount);
    event ProtocolFeesClaimed(address indexed treasury, uint256 amount);
    event ReferralFeeClaimed(address indexed referrer, uint256 amount);
    event PlanEnded(uint256 totalContributed, bool fullCycle);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error AlreadyMember();
    error AlreadyApproved();
    error NotMember();
    error NotApproved();
    error JoinClosed();
    error ApprovalNotRequired();
    error MemberLimitReached();
    error PlanInactive();
    error PlanNotFinished();
    error AlreadyContributed(uint256 period);
    error BadPeriodsLength();
    error BadPeriod(uint256 period);
    error WrongNativeValue(uint256 expectedNative);
    error NothingToWithdraw();
    error NothingToClaim();
    error BadParams();

    // ---------------------------------------------------------------------
    // Construction (factory-only, via CREATE2)
    // ---------------------------------------------------------------------

    constructor(PlanParams memory params_) EscrowBase(params_.collector, params_.guardian) {
        _validate(params_);
        _params = params_;
        emit PlanCreated(
            params_.collector,
            params_.contributionAmount,
            params_.frequency,
            params_.startTime,
            params_.durationPeriods,
            params_.feeBps,
            params_.earlyWithdrawPenaltyBps
        );
    }

    /// @notice Emitted once per instance; the factory's richer `PlanCreated` is the indexer entry.
    event PlanCreated(
        address indexed collector,
        uint256 contributionAmount,
        Frequency frequency,
        uint64 startTime,
        uint16 durationPeriods,
        uint16 feeBps,
        uint16 earlyWithdrawPenaltyBps
    );

    function _validate(PlanParams memory p) internal pure {
        if (p.collector == address(0) || p.guardian == address(0)) revert BadParams();
        if (p.contributionAmount == 0 || p.contributionAmount > MAX_CONTRIBUTION) revert BadParams();
        if (p.durationPeriods == 0 || p.durationPeriods > MAX_PERIODS) revert BadParams();
        if (p.startTime == 0) revert BadParams();
        if (p.treasury == address(0)) revert BadParams();
    }

    // ---------------------------------------------------------------------
    // Membership
    // ---------------------------------------------------------------------

    /// @notice Join the plan. Free-form `referrer` (address(0) = none). When
    ///         `approvalRequired` is set, the collector must approve before contributing.
    function join(address referrer) external whenNotPaused {
        if (_members[msg.sender].joinedAt != 0) revert AlreadyMember();
        if (isComplete() || ended) revert JoinClosed();

        uint256 limit = _params.maxMembers;
        if (limit != 0 && _memberList.length >= limit) revert MemberLimitReached();

        bool approved = !_params.approvalRequired;
        _members[msg.sender] = Member({
            joinedAt: uint64(block.timestamp),
            exitedAt: 0,
            contributedPeriods: 0,
            approved: approved,
            withdrawn: false,
            totalContributed: 0,
            contributionBitmap: 0,
            referrer: referrer == msg.sender ? address(0) : referrer
        });
        _memberList.push(msg.sender);

        emit MemberJoined(msg.sender, referrer);
        if (approved) emit MemberApproved(msg.sender);
    }

    /// @notice Approve a pending joiner (only when `approvalRequired`).
    function approveMember(address member) external onlyCollector {
        if (!_params.approvalRequired) revert ApprovalNotRequired();
        Member storage m = _members[member];
        if (m.joinedAt == 0) revert NotMember();
        if (m.approved) revert AlreadyApproved();
        m.approved = true;
        emit MemberApproved(member);
    }

    /// @notice Batch approval convenience for collectors onboarding a WhatsApp group.
    function approveMembers(address[] calldata toApprove) external onlyCollector {
        if (!_params.approvalRequired) revert ApprovalNotRequired();
        uint256 len = toApprove.length;
        for (uint256 i = 0; i < len; ++i) {
            Member storage m = _members[toApprove[i]];
            if (m.joinedAt == 0) revert NotMember();
            if (!m.approved) {
                m.approved = true;
                emit MemberApproved(toApprove[i]);
            }
        }
    }

    // ---------------------------------------------------------------------
    // Contributions (dual-rail)
    // ---------------------------------------------------------------------

    /// @notice Contribute one or more periods on the ERC-20 rail (approve first, or use Permit2).
    /// @param periods Period indices to pay (catch-up allowed; pre-payment of any period allowed).
    function contribute(uint256[] calldata periods) external nonReentrant whenNotPaused {
        uint256 amount = _requireDeposit(periods);
        _pullToken(msg.sender, amount);
        _recordContribution(msg.sender, periods, false);
    }

    /// @notice Contribute one or more periods on the native rail (plain wallet send).
    /// @dev `msg.value` must equal `periods.length * contributionAmount * 1e12` exactly
    ///      (whole micro-USDC; sub-micro-dollar dust reverts with `NativePrecisionLoss`).
    function contributeNative(uint256[] calldata periods) external payable nonReentrant whenNotPaused {
        uint256 expected = _requireDeposit(periods);
        uint256 appAmount = ArcUsdcLib.toApp(msg.value); // reverts on sub-micro-dollar dust first
        if (appAmount != expected) revert WrongNativeValue(ArcUsdcLib.toNative(expected));
        _pullNative(msg.value);
        _recordContribution(msg.sender, periods, true);
    }

    function _requireDeposit(uint256[] calldata periods) internal view returns (uint256 amount) {
        uint256 len = periods.length;
        if (len == 0 || len > MAX_PERIODS) revert BadPeriodsLength();
        if (ended || isComplete()) revert PlanInactive();

        Member storage m = _members[msg.sender];
        if (m.joinedAt == 0) revert NotMember();
        if (!m.approved) revert NotApproved();
        if (m.withdrawn) revert PlanInactive();

        amount = _params.contributionAmount * len;
    }

    function _recordContribution(address member, uint256[] calldata periods, bool nativeRail) internal {
        Member storage m = _members[member];
        uint256 len = periods.length;

        for (uint256 i = 0; i < len; ++i) {
            uint256 period = periods[i];
            if (period >= _params.durationPeriods) revert BadPeriod(period);
            uint256 bit = 1 << period;
            if (m.contributionBitmap & bit != 0) revert AlreadyContributed(period);
            m.contributionBitmap |= bit;
            unchecked {
                m.contributedPeriods += 1;
            }
            emit Contributed(member, period, _params.contributionAmount, nativeRail);
        }

        uint256 amount = _params.contributionAmount * len;
        m.totalContributed += amount;
        totalContributed += amount;
    }

    // ---------------------------------------------------------------------
    // Withdrawals
    // ---------------------------------------------------------------------

    /// @notice Withdraw full savings at the end of the cycle (or after the collector ends the
    ///         plan). Pays `contributed × (1 − feeBps − protocolFeeBps)`.
    function withdraw() external nonReentrant returns (uint256 payout) {
        if (!isComplete()) revert PlanNotFinished();
        (payout, ) = _withdraw(false);
    }

    /// @notice Exit before the cycle ends. Pays `contributed × (1 − feeBps − protocolFeeBps)
    ///         × (1 − earlyWithdrawPenaltyBps)`. The penalty is credited to the collector fee
    ///         pool (curation compensation; capped at 5% by the factory).
    function withdrawEarly() external nonReentrant returns (uint256 payout) {
        if (isComplete()) revert PlanInactive(); // use withdraw() instead
        (payout, ) = _withdraw(true);
    }

    function _withdraw(bool early) internal returns (uint256 payout, Member memory m) {
        Member storage s = _members[msg.sender];
        if (s.joinedAt == 0) revert NotMember();
        if (s.withdrawn) revert NothingToWithdraw();
        uint256 gross = s.totalContributed;
        if (gross == 0) revert NothingToWithdraw();

        uint256 collectorFee = (gross * _params.feeBps) / 10_000;
        uint256 protocolFee = (gross * _params.protocolFeeBps) / 10_000;
        uint256 afterFees = gross - collectorFee - protocolFee;
        uint256 penalty = early ? (afterFees * _params.earlyWithdrawPenaltyBps) / 10_000 : 0;
        payout = afterFees - penalty;

        s.withdrawn = true;
        s.exitedAt = uint64(block.timestamp);
        claimed[msg.sender] = payout;

        // Natural full-cycle completion gets reported on first exit (once).
        if (!ended) _report(true);

        accruedCollectorFees += collectorFee + penalty;
        accruedProtocolFees += protocolFee;
        if (_params.referralShareBps != 0 && protocolFee != 0 && s.referrer != address(0)) {
            uint256 share = (protocolFee * _params.referralShareBps) / 10_000;
            accruedProtocolFees -= share;
            accruedReferralFees[s.referrer] += share;
        }

        _push(msg.sender, payout);
        emit Withdrawn(msg.sender, gross, payout, collectorFee, protocolFee, penalty, early);
    }

    // ---------------------------------------------------------------------
    // Fee claims
    // ---------------------------------------------------------------------

    /// @notice Collector claims accumulated fees + early-exit penalties.
    function claimFees() external nonReentrant onlyCollector returns (uint256 amount) {
        amount = accruedCollectorFees;
        if (amount == 0) revert NothingToClaim();
        accruedCollectorFees = 0;
        _push(collector, amount);
        emit CollectorFeesClaimed(collector, amount);
    }

    /// @notice Treasury claims accumulated protocol fees.
    function claimProtocolFees() external nonReentrant returns (uint256 amount) {
        if (msg.sender != _params.treasury) revert NotAuthorized();
        amount = accruedProtocolFees;
        if (amount == 0) revert NothingToClaim();
        accruedProtocolFees = 0;
        _push(_params.treasury, amount);
        emit ProtocolFeesClaimed(_params.treasury, amount);
    }

    /// @notice A referrer claims their accumulated share of protocol fees.
    function claimReferralFees() external nonReentrant returns (uint256 amount) {
        amount = accruedReferralFees[msg.sender];
        if (amount == 0) revert NothingToClaim();
        accruedReferralFees[msg.sender] = 0;
        _push(msg.sender, amount);
        emit ReferralFeeClaimed(msg.sender, amount);
    }

    // ---------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------

    /// @notice Collector ends the plan early. Members keep full withdrawal rights; the only
    ///         effect is that contributions stop and withdrawals open immediately.
    function endPlan() external onlyCollector {
        if (ended) revert PlanInactive();
        ended = true;
        emit PlanEnded(totalContributed, false);
        _report(false);
    }

    function _report(bool completed) internal {
        if (reported || _params.reputation == address(0)) return;
        reported = true;
        try ICollectorReputation(_params.reputation).reportPlanOutcome(collector, totalContributed, completed)
        {} catch {
            // Reputation is best-effort: never block funds.
        }
    }

    /// @notice Permissionless poke to report a naturally-completed cycle (if nobody withdrew).
    function pokeOutcome() external {
        if (!isComplete() || reported) revert PlanInactive();
        _report(!ended);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Full immutable plan parameters (explicit getter: includes metadataURI).
    function params() external view returns (PlanParams memory) {
        return _params;
    }

    /// @notice Seconds per contribution period.
    function periodLength() public view returns (uint256) {
        Frequency f = _params.frequency;
        if (f == Frequency.Daily) return 1 days;
        if (f == Frequency.Weekly) return 7 days;
        return 30 days;
    }

    /// @notice Unix time at which the full cycle completes.
    function cycleEnd() public view returns (uint256) {
        return uint256(_params.startTime) + uint256(_params.durationPeriods) * periodLength();
    }

    /// @notice True once the full cycle elapsed or the collector ended the plan.
    function isComplete() public view returns (bool) {
        return ended || block.timestamp >= cycleEnd();
    }

    /// @notice Current period index, clamped to `[0, durationPeriods]` (durationPeriods = done).
    function currentPeriod() public view returns (uint256) {
        if (block.timestamp < _params.startTime) return 0;
        uint256 elapsed = block.timestamp - _params.startTime;
        uint256 period = elapsed / periodLength();
        return period > _params.durationPeriods ? _params.durationPeriods : period;
    }

    /// @notice True if `member` paid `period`.
    function hasContributed(address member, uint256 period) public view returns (bool) {
        return _members[member].contributionBitmap & (1 << period) != 0;
    }

    /// @notice Full member record.
    function memberOf(address member) external view returns (Member memory) {
        return _members[member];
    }

    /// @notice All members (bounded reads off-chain / for the frontend multicall).
    function members(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        uint256 total = _memberList.length;
        if (offset >= total) return new address[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = _memberList[i];
        }
    }

    function memberCount() external view returns (uint256) {
        return _memberList.length;
    }

    /// @notice Payout `member` would receive from `withdraw()` / `withdrawEarly()` right now.
    function claimableOf(address member) external view returns (uint256) {
        Member storage m = _members[member];
        if (m.withdrawn || m.totalContributed == 0) return 0;
        uint256 collectorFee = (m.totalContributed * _params.feeBps) / 10_000;
        uint256 protocolFee = (m.totalContributed * _params.protocolFeeBps) / 10_000;
        uint256 afterFees = m.totalContributed - collectorFee - protocolFee;
        if (!isComplete()) {
            return afterFees - (afterFees * _params.earlyWithdrawPenaltyBps) / 10_000;
        }
        return afterFees;
    }
}
