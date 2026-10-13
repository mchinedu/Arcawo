// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

/// @title MockArcUsdc — test double that reproduces Arc's REAL USDC semantics
/// @notice On Arc, USDC is the native gas asset with **one balance exposed at two precisions**:
///         `address.balance` (18-dec) and the ERC-20 face at `0x3600…0000` (6-dec), related by
///         `balanceOf(a) == a.balance / 1e12`. A standard ERC-20 mock cannot test that.
///
///         This mock implements the ERC-20 face *as a view of the test chain's native balance*:
///         • `balanceOf(a)`      → `a.balance / 1e12`
///         • `transfer`          → moves native balance (via `vm.deal`), scaled ×1e12
///         • `transferFrom`      → same, through a standard allowance
///
///         Tests etch this contract AT the canonical Arc USDC address with `vm.etch`, so protocol
///         code runs against production addresses and production invariants (native-rail deposits
///         and ERC-20 payouts draw from the same pool).
contract MockArcUsdc {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant NATIVE_PER_APP = 1e12;

    mapping(address => mapping(address => uint256)) public allowance;

    error InsufficientBalance();
    error InsufficientAllowance();

    // --- ERC-20 metadata (Arc USDC values) ---

    function name() external pure returns (string memory) {
        return "USDC";
    }

    function symbol() external pure returns (string memory) {
        return "USDC";
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }

    /// @dev On Arc the "total supply" is the whole native balance of the chain; tests never
    ///      need it. Returns a large constant for interface completeness.
    function totalSupply() external pure returns (uint256) {
        return type(uint256).max / 2;
    }

    // --- ERC-20 face over native balance ---

    function balanceOf(address account) public view returns (uint256) {
        return account.balance / NATIVE_PER_APP;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - amount;
        }
        _move(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @dev Moves native balance at 1e12 scale — the Arc "two views, one pool" invariant.
    function _move(address from, address to, uint256 amount) internal {
        uint256 nativeAmount = amount * NATIVE_PER_APP;
        if (from.balance < nativeAmount) revert InsufficientBalance();
        VM.deal(from, from.balance - nativeAmount);
        VM.deal(to, to.balance + nativeAmount);
    }
}
