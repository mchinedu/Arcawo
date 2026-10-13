// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ICollectorReputation
/// @notice Outcome-reporting surface used by Arc-awo escrow instances to build an on-chain
///         reputation record for collectors. All reports are best-effort: escrows call these
///         inside try/catch so a failing reputation contract can never block user funds.
interface ICollectorReputation {
    /// @notice A collector-hosted savings plan reached its terminal state.
    /// @param collector The plan's collector.
    /// @param volume    Total USDC (6-dec) contributed to the plan.
    /// @param completed True if the plan ran its full cycle, false if ended early.
    function reportPlanOutcome(address collector, uint256 volume, bool completed) external;

    /// @notice A ROSCA group resolved all rounds.
    /// @param collector     The group's coordinator.
    /// @param volume        Total USDC (6-dec) contributed across all rounds.
    /// @param completed     True if every round's pot was claimed or redistributed.
    /// @param defaultEvents Number of member-round defaults observed (late/missing payments).
    function reportGroupOutcome(address collector, uint256 volume, bool completed, uint256 defaultEvents)
        external;
}
