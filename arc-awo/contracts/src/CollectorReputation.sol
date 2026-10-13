// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IArcawoFactory} from "./interfaces/IArcawoFactory.sol";
import {ICollectorReputation} from "./interfaces/ICollectorReputation.sol";

/// @title CollectorReputation — on-chain reputation for thrift collectors
/// @notice Aggregates outcome reports from genuine Arc-awo instances (verified against the
///         factory registry) into a transparent, portable collector score. Members can judge a
///         collector before entrusting them with a plan or joining their group.
///
///         Score (0..1000, clamped) — see `score()`:
///           500 base
///           + up to +400  (completion record & on-chain volume)
///           − defaults    (member defaults under their watch, early terminations)
///
///         Reports are pushed by escrow instances via try/catch; this contract can never block
///         funds. Only the factory owner can move the factory pointer (migration path).
contract CollectorReputation is ICollectorReputation {
    struct Stats {
        uint64 plansCompleted;
        uint64 plansEndedEarly;
        uint64 groupsCompleted;
        uint64 defaultEvents; // member-round defaults observed in their groups
        uint64 lastReportAt;
        uint128 totalVolumeUSDC6; // cumulative contributions (app units)
    }

    address public factory;
    address public owner;

    mapping(address => Stats) private _stats;

    event OutcomeReported(address indexed collector, bool completed, uint256 volume, uint256 defaultEvents);
    event FactoryUpdated(address indexed factory);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OnlyFactoryInstance();
    error OnlyOwner();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address factory_, address owner_) {
        if (factory_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        factory = factory_;
        owner = owner_;
        emit FactoryUpdated(factory_);
        emit OwnershipTransferred(address(0), owner_);
    }

    // ---------------------------------------------------------------------
    // Reporting (escrow instances only)
    // ---------------------------------------------------------------------

    /// @inheritdoc ICollectorReputation
    function reportPlanOutcome(address collector, uint256 volume, bool completed) external {
        if (!_isInstance(msg.sender)) revert OnlyFactoryInstance();
        Stats storage s = _stats[collector];
        if (completed) {
            unchecked {
                s.plansCompleted += 1;
            }
        } else {
            unchecked {
                s.plansEndedEarly += 1;
            }
        }
        _applyVolume(s, volume);
        emit OutcomeReported(collector, completed, volume, 0);
    }

    /// @inheritdoc ICollectorReputation
    function reportGroupOutcome(address collector, uint256 volume, bool completed, uint256 defaultEvents)
        external
    {
        if (!_isInstance(msg.sender)) revert OnlyFactoryInstance();
        Stats storage s = _stats[collector];
        if (completed) {
            unchecked {
                s.groupsCompleted += 1;
            }
        }
        uint64 capped = defaultEvents > type(uint64).max ? type(uint64).max : uint64(defaultEvents);
        s.defaultEvents += capped;
        _applyVolume(s, volume);
        emit OutcomeReported(collector, completed, volume, defaultEvents);
    }

    function _applyVolume(Stats storage s, uint256 volume) internal {
        uint256 total = uint256(s.totalVolumeUSDC6) + volume;
        s.totalVolumeUSDC6 = total > type(uint128).max ? type(uint128).max : uint128(total);
        s.lastReportAt = uint64(block.timestamp);
    }

    function _isInstance(address instance) internal view returns (bool) {
        IArcawoFactory f = IArcawoFactory(factory);
        return f.isPlan(instance) || f.isGroup(instance);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function statsOf(address collector) external view returns (Stats memory) {
        return _stats[collector];
    }

    /// @notice Composite collector score in [0, 1000].
    ///         500 base; +20 per completed plan/group (capped +400 via volume & completions);
    ///         + up to 200 for volume (1 pt per 250 USDC, capped); − 25 per default event;
    ///         − 15 per early plan termination. New collectors start at 500 ("neutral").
    function score(address collector) public view returns (uint256) {
        Stats memory s = _stats[collector];

        uint256 completions = uint256(s.plansCompleted) + uint256(s.groupsCompleted);
        uint256 points = 500;

        // Completion track record: +20 each, capped at +200.
        uint256 completionPts = completions * 20;
        if (completionPts > 200) completionPts = 200;
        points += completionPts;

        // Volume: +1 per 250 USDC (6-dec: 250e6), capped at +200 (=> 50,000 USDC).
        uint256 volumePts = uint256(s.totalVolumeUSDC6) / 250e6;
        if (volumePts > 200) volumePts = 200;
        points += volumePts;

        // Penalties.
        uint256 penalties = uint256(s.defaultEvents) * 25 + uint256(s.plansEndedEarly) * 15;
        if (penalties >= points) return 0;
        points -= penalties;

        return points > 1000 ? 1000 : points;
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setFactory(address factory_) external onlyOwner {
        if (factory_ == address(0)) revert ZeroAddress();
        factory = factory_;
        emit FactoryUpdated(factory_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
