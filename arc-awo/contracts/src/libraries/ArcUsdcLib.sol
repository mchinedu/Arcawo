// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ArcUsdcLib — the single decimal boundary for Arc native USDC
/// @notice On Arc (Circle's stablecoin L1) USDC is the native gas asset and exposes **one
///         balance through two precisions**:
///
///         • native view   — `msg.value` / `address.balance` / gas   → 18 decimals
///         • ERC-20 view   — `0x3600…0000` transfer/balanceOf/…      → 6 decimals
///
///         `1 USDC = 1e18 native units = 1e6 ERC-20 units`, a 1e12 scale factor over the same
///         money. There is no wrapped-USDC contract on Arc and no conversion step.
///
///         Arc-awo's canonical accounting unit is the **6-decimal app unit** (USDC's
///         wallet/CCTP/indexer precision). All protocol accounting — contributions, pots,
///         fees, penalties — happens in app units. The 18-decimal native rail is scaled
///         exactly at this boundary and nowhere else:
///
///         • native → app  : `toApp` requires `native % 1e12 == 0` (sub-micro-dollar dust reverts)
///         • app → native  : `toNative` multiplies (exact)
///
///         See ARCHITECTURE.md §1 for the full rationale.
library ArcUsdcLib {
    using SafeERC20 for IERC20;

    /// @notice Canonical Arc USDC ERC-20 face (6 decimals). Same address on mainnet and testnet.
    ///         It is a system predeploy — the ERC-20 view of the native asset itself.
    address internal constant USDC = 0x3600000000000000000000000000000000000000;

    /// @notice Canonical accounting precision used across Arc-awo.
    uint8 internal constant APP_DECIMALS = 6;

    /// @notice Native units (18-dec) per app unit (6-dec). 1 USDC = 1e12 native-per-app.
    uint256 internal constant NATIVE_PER_APP = 1e12;

    /// @notice A native amount is not representable in 6-dec app units (dust < 1e-6 USDC).
    error NativePrecisionLoss(uint256 nativeAmount);

    /// @notice Scaling app → native would overflow.
    error AmountOverflow(uint256 appAmount);

    /// @notice Convert a native (18-dec) amount to canonical app (6-dec) units, exactly.
    /// @dev    Reverts on any amount that is not a whole number of micro-USDC. Callers that
    ///         accept `msg.value` on the native rail MUST route it through this function so
    ///         dust can never enter the accounting ledger.
    function toApp(uint256 nativeAmount) internal pure returns (uint256 appAmount) {
        if (nativeAmount % NATIVE_PER_APP != 0) revert NativePrecisionLoss(nativeAmount);
        return nativeAmount / NATIVE_PER_APP;
    }

    /// @notice Convert canonical app (6-dec) units to native (18-dec) units, exactly.
    function toNative(uint256 appAmount) internal pure returns (uint256 nativeAmount) {
        if (appAmount > type(uint256).max / NATIVE_PER_APP) revert AmountOverflow(appAmount);
        return appAmount * NATIVE_PER_APP;
    }

    /// @notice Safe USDC transfer in app units (ERC-20 face).
    function safeTransfer(address to, uint256 appAmount) internal {
        SafeERC20.safeTransfer(IERC20(USDC), to, appAmount);
    }

    /// @notice Safe USDC transferFrom in app units (ERC-20 face).
    function safeTransferFrom(address from, address to, uint256 appAmount) internal {
        SafeERC20.safeTransferFrom(IERC20(USDC), from, to, appAmount);
    }

    /// @notice USDC balance of `account` in app units (ERC-20 face, 6 decimals).
    function balanceOf(address account) internal view returns (uint256) {
        return IERC20(USDC).balanceOf(account);
    }
}
