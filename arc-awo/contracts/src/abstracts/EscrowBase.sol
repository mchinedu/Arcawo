// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ArcUsdcLib} from "../libraries/ArcUsdcLib.sol";

/// @title EscrowBase
/// @notice Shared custody primitives for every Arc-awo escrow instance (ArcawoPlan / IsusuGroup):
///         dual-rail USDC deposits (ERC-20 + native), solvency tracking, guardian pause, and a
///         strictly-bounded `rescueExcess`.
///
///         Safety invariants enforced here:
///         1. `trackedLiabilities` is increased on every inbound credit and decreased on every
///            outbound payment. It equals the sum of all user claims + accrued fees at all times.
///         2. `rescueExcess` can move at most `balance − trackedLiabilities` — unsolicited
///            donations only. No admin path can ever move tracked user principal.
///         3. Pause blocks deposits (joins/contributions) but NEVER exits. Members can always
///            withdraw/claim even while paused.
abstract contract EscrowBase is ReentrancyGuard, Pausable {
    /// @notice The collector/coordinator of this instance.
    address public immutable collector;

    /// @notice Ops guardian (multisig) able to pause deposits and rescue untracked excess.
    address public immutable guardian;

    /// @notice Sum of all tracked claims (user principal claims + accrued fees), in app units.
    uint256 public trackedLiabilities;

    /// @notice Untracked funds (e.g. direct USDC transfers that never called `contribute`).
    event ExcessRescued(address indexed to, uint256 amount);

    error OnlyCollector();
    error OnlyGuardian();
    error NotAuthorized();
    error ZeroAmount();
    error ZeroAddress();

    modifier onlyCollector() {
        if (msg.sender != collector) revert OnlyCollector();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian();
        _;
    }

    constructor(address collector_, address guardian_) {
        if (collector_ == address(0) || guardian_ == address(0)) revert ZeroAddress();
        collector = collector_;
        guardian = guardian_;
    }

    // ---------------------------------------------------------------------
    // Pause — deposits only. Exits are deliberately never gated.
    // ---------------------------------------------------------------------

    /// @notice Pause joins/contributions (guardian). Withdrawals remain available.
    function pause() external onlyGuardian {
        _pause();
    }

    /// @notice Resume joins/contributions.
    function unpause() external onlyGuardian {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Dual-rail USDC custody (app units; see ArcUsdcLib for precision rules)
    // ---------------------------------------------------------------------

    /// @dev Pull `appAmount` from `from` on the ERC-20 rail and credit the ledger.
    function _pullToken(address from, uint256 appAmount) internal {
        trackedLiabilities += appAmount;
        ArcUsdcLib.safeTransferFrom(from, address(this), appAmount);
    }

    /// @dev Credit the ledger for native value already received via `msg.value` (native rail).
    ///      Reverts on sub-micro-dollar dust so the 6-dec ledger stays exact. On Arc the native
    ///      value and the ERC-20 balance are one pool, so `_push` works regardless of rail.
    function _pullNative(uint256 nativeAmount) internal returns (uint256 appAmount) {
        appAmount = ArcUsdcLib.toApp(nativeAmount);
        trackedLiabilities += appAmount;
    }

    /// @dev Pay `appAmount` to `to` on the ERC-20 rail and debit the ledger.
    function _push(address to, uint256 appAmount) internal {
        trackedLiabilities -= appAmount;
        ArcUsdcLib.safeTransfer(to, appAmount);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice USDC held by this escrow in app units (6 decimals).
    function usdcBalance() public view returns (uint256) {
        return ArcUsdcLib.balanceOf(address(this));
    }

    /// @notice Funds above tracked liabilities (unsolicited transfers). Always sweepable.
    function excess() public view returns (uint256) {
        uint256 balance = ArcUsdcLib.balanceOf(address(this));
        return balance > trackedLiabilities ? balance - trackedLiabilities : 0;
    }

    // ---------------------------------------------------------------------
    // Emergency
    // ---------------------------------------------------------------------

    /// @notice Sweep only untracked excess (never user principal) to `to`.
    ///         Callable by the collector or the guardian (multisig/timelock in production).
    function rescueExcess(address to) external nonReentrant returns (uint256 amount) {
        if (msg.sender != collector && msg.sender != guardian) revert NotAuthorized();
        if (to == address(0)) revert ZeroAddress();
        amount = excess();
        if (amount == 0) revert ZeroAmount();
        // Deliberately no change to trackedLiabilities: only untracked value moves.
        ArcUsdcLib.safeTransfer(to, amount);
        emit ExcessRescued(to, amount);
    }
}
