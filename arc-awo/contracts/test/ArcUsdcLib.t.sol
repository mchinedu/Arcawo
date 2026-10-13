// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArcUsdcLib} from "../src/libraries/ArcUsdcLib.sol";

contract ArcUsdcLibTest is Test {
    function test_constants() public pure {
        assertEq(ArcUsdcLib.USDC, 0x3600000000000000000000000000000000000000);
        assertEq(ArcUsdcLib.APP_DECIMALS, 6);
        assertEq(ArcUsdcLib.NATIVE_PER_APP, 1e12);
    }

    function test_toApp_exactScaling() public pure {
        assertEq(ArcUsdcLib.toApp(1e18), 1e6); // 1 native USDC = 1 app USDC
        assertEq(ArcUsdcLib.toApp(5e18), 5e6);
        assertEq(ArcUsdcLib.toApp(0), 0);
        assertEq(ArcUsdcLib.toApp(1e12), 1); // 1 micro-USDC
    }

    function test_toNative_exactScaling() public pure {
        assertEq(ArcUsdcLib.toNative(1e6), 1e18);
        assertEq(ArcUsdcLib.toNative(1), 1e12);
        assertEq(ArcUsdcLib.toNative(0), 0);
    }

    function test_roundTrip() public pure {
        for (uint256 i = 0; i < 7; ++i) {
            uint256 app = 12345 * 10 ** i;
            assertEq(ArcUsdcLib.toApp(ArcUsdcLib.toNative(app)), app);
        }
    }

    function test_toApp_revertsOnDust() public {
        vm.expectRevert(abi.encodeWithSelector(ArcUsdcLib.NativePrecisionLoss.selector, 1e12 - 1));
        this.externalToApp(1e12 - 1);

        vm.expectRevert(abi.encodeWithSelector(ArcUsdcLib.NativePrecisionLoss.selector, 1));
        this.externalToApp(1);
    }

    function test_toNative_revertsOnOverflow() public {
        vm.expectRevert(abi.encodeWithSelector(ArcUsdcLib.AmountOverflow.selector, type(uint256).max));
        this.externalToNative(type(uint256).max);
    }

    function testFuzz_toAppNeverLossy(uint256 app) public pure {
        vm.assume(app <= type(uint256).max / 1e12);
        assertEq(ArcUsdcLib.toApp(ArcUsdcLib.toNative(app)), app);
    }

    function testFuzz_dustAlwaysReverts(uint256 nativeAmount) public {
        vm.assume(nativeAmount % 1e12 != 0);
        vm.expectRevert(abi.encodeWithSelector(ArcUsdcLib.NativePrecisionLoss.selector, nativeAmount));
        this.externalToApp(nativeAmount);
    }

    // --- external wrappers for expectRevert on library internals ---

    function externalToApp(uint256 nativeAmount) external pure returns (uint256) {
        return ArcUsdcLib.toApp(nativeAmount);
    }

    function externalToNative(uint256 app) external pure returns (uint256) {
        return ArcUsdcLib.toNative(app);
    }
}
