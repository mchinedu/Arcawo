// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ArcawoPlan} from "./ArcawoPlan.sol";
import {IsusuGroup} from "./IsusuGroup.sol";
import {IArcawoFactory} from "./interfaces/IArcawoFactory.sol";
import {ICollectorReputation} from "./interfaces/ICollectorReputation.sol";

/// @title ArcawoFactory — deployment factory + registry for Arc-awo thrift instances
/// @notice Creates `ArcawoPlan` and `IsusuGroup` escrows via CREATE2 (deterministic addresses,
///         counterfactual-friendly), validates every user-supplied parameter against
///         protocol-wide caps, and stamps protocol-level fields (guardian, treasury, fee config,
///         reputation) that creators cannot influence. Emits fully-decoded creation events so
///         indexers can rebuild the entire product state from logs alone.
///
///         Roles (production wiring):
///         • owner   — timelock/multisig: fee config, treasury, reputation pointer.
///         • guardian — ops multisig: pause new creations (never user funds).
contract ArcawoFactory is Ownable2Step, Pausable, IArcawoFactory {
    // ---------------------------------------------------------------------
    // Constants (protocol-wide hard caps — cannot be exceeded by any config)
    // ---------------------------------------------------------------------

    uint16 public constant MAX_COLLECTOR_FEE_BPS = 100; // 1%
    uint16 public constant MAX_PENALTY_BPS = 500; // 5%
    uint16 public constant MAX_LATE_FEE_BPS = 500; // 5%
    uint16 public constant MAX_PROTOCOL_FEE_BPS = 100; // 1%
    uint16 public constant MAX_REFERRAL_SHARE_BPS = 10_000; // 100% of protocol fee
    uint64 public constant MAX_START_DELAY = 30 days;
    uint256 public constant MAX_METADATA_BYTES = 512;

    // ---------------------------------------------------------------------
    // Config
    // ---------------------------------------------------------------------

    address public guardian;
    address public treasury;
    ICollectorReputation public reputation;
    uint16 public protocolFeeBps; // 0 at launch (no surprise economics)
    uint16 public referralShareBps; // share of protocol fee to a member's referrer

    // ---------------------------------------------------------------------
    // Registry
    // ---------------------------------------------------------------------

    address[] public allPlans;
    address[] public allGroups;
    mapping(address => bool) private _isPlan;
    mapping(address => bool) private _isGroup;
    mapping(address => address[]) private _plansOf;
    mapping(address => address[]) private _groupsOf;

    // Referral stats (volume in app units, estimated at creation)
    mapping(address => uint256) public referralVolume;
    mapping(address => uint256) public referralCount;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event PlanCreated(
        address indexed plan,
        address indexed collector,
        address indexed referrer,
        uint256 contributionAmount,
        ArcawoPlan.Frequency frequency,
        uint64 startTime,
        uint16 durationPeriods,
        uint16 feeBps,
        uint16 earlyWithdrawPenaltyBps,
        string metadataURI
    );
    event GroupCreated(
        address indexed group,
        address indexed collector,
        address indexed referrer,
        uint256 contributionAmount,
        IsusuGroup.Frequency frequency,
        IsusuGroup.PayoutMode payoutMode,
        uint16 memberCount,
        uint16 feeBps,
        uint16 lateFeeBps,
        uint64 startDelay,
        string metadataURI
    );
    event ConfigUpdated(
        address guardian,
        address treasury,
        address reputation,
        uint16 protocolFeeBps,
        uint16 referralShareBps
    );

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error BadFee(string param);
    error BadConfig();
    error MetadataTooLong();
    error StartTooFar();

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    constructor(
        address owner_,
        address guardian_,
        address treasury_,
        address reputation_,
        uint16 protocolFeeBps_,
        uint16 referralShareBps_
    ) Ownable(owner_) {
        if (guardian_ == address(0) || treasury_ == address(0) || reputation_ == address(0)) {
            revert BadConfig();
        }
        if (protocolFeeBps_ > MAX_PROTOCOL_FEE_BPS || referralShareBps_ > MAX_REFERRAL_SHARE_BPS) {
            revert BadFee("fee");
        }
        guardian = guardian_;
        treasury = treasury_;
        reputation = ICollectorReputation(reputation_);
        protocolFeeBps = protocolFeeBps_;
        referralShareBps = referralShareBps_;
        emit ConfigUpdated(guardian_, treasury_, reputation_, protocolFeeBps_, referralShareBps_);
    }

    // ---------------------------------------------------------------------
    // Creation
    // ---------------------------------------------------------------------

    /// @notice Deploy a classic Akawo savings plan. `userSalt` makes the CREATE2 address a
    ///         function of (creator, salt) so addresses are predictable and front-running of
    ///         someone else's salt is impossible.
    /// @param params User-facing plan fields. Protocol fields (guardian, treasury, reputation,
    ///               protocol fee) are stamped by the factory and ignored in the input.
    /// @param referrer Optional referrer (address(0) = none); earns a share of protocol fees.
    function createPlan(ArcawoPlan.PlanParams calldata params, bytes32 userSalt, address referrer)
        external
        whenNotPaused
        returns (address plan)
    {
        if (bytes(params.metadataURI).length > MAX_METADATA_BYTES) revert MetadataTooLong();
        if (params.startTime > block.timestamp + MAX_START_DELAY) revert StartTooFar();
        if (params.feeBps > MAX_COLLECTOR_FEE_BPS) revert BadFee("feeBps");
        if (params.earlyWithdrawPenaltyBps > MAX_PENALTY_BPS) revert BadFee("earlyWithdrawPenaltyBps");

        ArcawoPlan.PlanParams memory stamped = params;
        stamped.guardian = guardian;
        stamped.treasury = treasury;
        stamped.reputation = address(reputation);
        stamped.protocolFeeBps = protocolFeeBps;
        stamped.referralShareBps = referralShareBps;

        bytes32 salt = keccak256(abi.encode(msg.sender, userSalt));
        plan = address(new ArcawoPlan{salt: salt}(stamped));

        _isPlan[plan] = true;
        allPlans.push(plan);
        _plansOf[params.collector].push(plan);

        if (referrer != address(0) && referrer != msg.sender) {
            referralCount[referrer] += 1;
            referralVolume[referrer] += stamped.contributionAmount * stamped.durationPeriods;
        }

        emit PlanCreated(
            plan,
            params.collector,
            referrer == msg.sender ? address(0) : referrer,
            params.contributionAmount,
            params.frequency,
            params.startTime,
            params.durationPeriods,
            params.feeBps,
            params.earlyWithdrawPenaltyBps,
            params.metadataURI
        );
    }

    /// @notice Deploy a rotating savings (Isusu) group.
    function createGroup(IsusuGroup.GroupParams calldata params, bytes32 userSalt, address referrer)
        external
        whenNotPaused
        returns (address group)
    {
        if (bytes(params.metadataURI).length > MAX_METADATA_BYTES) revert MetadataTooLong();
        if (params.feeBps > MAX_COLLECTOR_FEE_BPS) revert BadFee("feeBps");
        if (params.lateFeeBps > MAX_LATE_FEE_BPS) revert BadFee("lateFeeBps");
        if (params.startDelay > MAX_START_DELAY) revert StartTooFar();

        IsusuGroup.GroupParams memory stamped = params;
        stamped.guardian = guardian;
        stamped.treasury = treasury;
        stamped.reputation = address(reputation);
        stamped.protocolFeeBps = protocolFeeBps;

        bytes32 salt = keccak256(abi.encode(msg.sender, userSalt));
        group = address(new IsusuGroup{salt: salt}(stamped));

        _isGroup[group] = true;
        allGroups.push(group);
        _groupsOf[params.collector].push(group);

        if (referrer != address(0) && referrer != msg.sender) {
            referralCount[referrer] += 1;
            referralVolume[referrer] += params.contributionAmount * params.memberCount * params.memberCount;
        }

        emit GroupCreated(
            group,
            params.collector,
            referrer == msg.sender ? address(0) : referrer,
            params.contributionAmount,
            params.frequency,
            params.payoutMode,
            params.memberCount,
            params.feeBps,
            params.lateFeeBps,
            params.startDelay,
            params.metadataURI
        );
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @inheritdoc IArcawoFactory
    function isPlan(address instance) external view returns (bool) {
        return _isPlan[instance];
    }

    /// @inheritdoc IArcawoFactory
    function isGroup(address instance) external view returns (bool) {
        return _isGroup[instance];
    }

    function plansOf(address collector) external view returns (address[] memory) {
        return _plansOf[collector];
    }

    function groupsOf(address collector) external view returns (address[] memory) {
        return _groupsOf[collector];
    }

    function planCount() external view returns (uint256) {
        return allPlans.length;
    }

    function groupCount() external view returns (uint256) {
        return allGroups.length;
    }

    function plans(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        return _page(allPlans, offset, limit);
    }

    function groups(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        return _page(allGroups, offset, limit);
    }

    function _page(address[] storage list, uint256 offset, uint256 limit)
        internal
        view
        returns (address[] memory page)
    {
        uint256 total = list.length;
        if (offset >= total) return new address[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = list[i];
        }
    }

    // ---------------------------------------------------------------------
    // Admin (owner = timelock; guardian = ops multisig)
    // ---------------------------------------------------------------------

    /// @notice Update protocol configuration (fee caps enforced).
    function setConfig(
        address guardian_,
        address treasury_,
        address reputation_,
        uint16 protocolFeeBps_,
        uint16 referralShareBps_
    ) external onlyOwner {
        if (guardian_ == address(0) || treasury_ == address(0) || reputation_ == address(0)) {
            revert BadConfig();
        }
        if (protocolFeeBps_ > MAX_PROTOCOL_FEE_BPS || referralShareBps_ > MAX_REFERRAL_SHARE_BPS) {
            revert BadFee("fee");
        }
        guardian = guardian_;
        treasury = treasury_;
        reputation = ICollectorReputation(reputation_);
        protocolFeeBps = protocolFeeBps_;
        referralShareBps = referralShareBps_;
        emit ConfigUpdated(guardian_, treasury_, reputation_, protocolFeeBps_, referralShareBps_);
    }

    /// @notice Guardian pauses NEW plan/group creation (existing instances are unaffected;
    ///         their pause switches are per-instance and never block user exits).
    function pauseFactory() external {
        if (msg.sender != guardian) revert BadConfig();
        _pause();
    }

    function unpauseFactory() external onlyOwner {
        _unpause();
    }
}
