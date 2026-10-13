// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IArcawoFactory
/// @notice Registry surface of the Arc-awo factory, used by the reputation contract to verify
///         that outcome reports come from genuine factory-deployed instances.
interface IArcawoFactory {
    function isPlan(address instance) external view returns (bool);
    function isGroup(address instance) external view returns (bool);
    function guardian() external view returns (address);
}
