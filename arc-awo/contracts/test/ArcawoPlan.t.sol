// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ThriftTestBase, IERC20Like} from "./helpers/ThriftTestBase.sol";
import {ArcawoPlan} from "../src/ArcawoPlan.sol";
import {ArcawoFactory} from "../src/ArcawoFactory.sol";
import {CollectorReputation} from "../src/CollectorReputation.sol";
import {EscrowBase} from "../src/abstracts/EscrowBase.sol";
import {ArcUsdcLib} from "../src/libraries/ArcUsdcLib.sol";

contract ArcawoPlanTest is ThriftTestBase {
    ArcawoPlan internal plan;

    function setUp() public override {
        super.setUp();
        plan = createDefaultPlan();
    }

    // ---------------------------------------------------------------------
    // Membership
    // ---------------------------------------------------------------------

    function test_join_open() public {
        vm.prank(alice);
        plan.join(address(0));
        assertTrue(plan.memberOf(alice).joinedAt != 0);
        assertTrue(plan.memberOf(alice).approved);
        assertEq(plan.memberCount(), 1);
    }

    function test_join_approvalRequired() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        p.approvalRequired = true;
        vm.prank(collector);
        ArcawoPlan gated = ArcawoPlan(factory.createPlan(p, bytes32("gated"), address(0)));

        vm.prank(alice);
        gated.join(address(0));
        assertFalse(gated.memberOf(alice).approved);

        // Cannot contribute before approval.
        vm.startPrank(alice);
        usdc.approve(address(gated), 100e6);
        vm.expectRevert(ArcawoPlan.NotApproved.selector);
        gated.contribute(single(0));
        vm.stopPrank();

        vm.prank(collector);
        gated.approveMember(alice);
        assertTrue(gated.memberOf(alice).approved);

        vm.prank(alice);
        gated.contribute(single(0));
        assertTrue(gated.hasContributed(alice, 0));
    }

    function test_join_twiceReverts() public {
        vm.prank(alice);
        plan.join(address(0));
        vm.prank(alice);
        vm.expectRevert(ArcawoPlan.AlreadyMember.selector);
        plan.join(address(0));
    }

    function test_join_afterCycleReverts() public {
        vm.warp(plan.cycleEnd());
        vm.prank(alice);
        vm.expectRevert(ArcawoPlan.JoinClosed.selector);
        plan.join(address(0));
    }

    // ---------------------------------------------------------------------
    // Contributions — token rail
    // ---------------------------------------------------------------------

    function test_contribute_tokenRail() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, two(0, 1));

        assertEq(plan.memberOf(alice).totalContributed, 200e6);
        assertEq(plan.memberOf(alice).contributedPeriods, 2);
        assertTrue(plan.hasContributed(alice, 0));
        assertTrue(plan.hasContributed(alice, 1));
        assertEq(plan.totalContributed(), 200e6);
        assertEq(plan.trackedLiabilities(), 200e6);
        assertEq(plan.usdcBalance(), 200e6);
    }

    function test_contribute_doublePeriodReverts() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));
        vm.startPrank(alice);
        usdc.approve(address(plan), 100e6);
        vm.expectRevert(abi.encodeWithSelector(ArcawoPlan.AlreadyContributed.selector, 0));
        plan.contribute(single(0));
        vm.stopPrank();
    }

    function test_contribute_withoutJoinReverts() public {
        vm.startPrank(alice);
        usdc.approve(address(plan), 100e6);
        vm.expectRevert(ArcawoPlan.NotMember.selector);
        plan.contribute(single(0));
        vm.stopPrank();
    }

    function test_contribute_badPeriodReverts() public {
        vm.prank(alice);
        plan.join(address(0));
        vm.startPrank(alice);
        usdc.approve(address(plan), 100e6);
        vm.expectRevert(abi.encodeWithSelector(ArcawoPlan.BadPeriod.selector, 12));
        plan.contribute(single(12));
        vm.stopPrank();
    }

    function test_contribute_catchUpLaterPeriods() public {
        vm.prank(alice);
        plan.join(address(0));
        vm.warp(block.timestamp + 5 * 7 days); // period 5
        assertEq(plan.currentPeriod(), 5);

        contributeToken(plan, alice, two(0, 5));
        assertTrue(plan.hasContributed(alice, 0));
        assertTrue(plan.hasContributed(alice, 5));
    }

    // ---------------------------------------------------------------------
    // Contributions — native rail (Arc dual-view semantics)
    // ---------------------------------------------------------------------

    function test_contribute_nativeRail() public {
        vm.prank(alice);
        plan.join(address(0));

        uint256 expectedNative = ArcUsdcLib.toNative(100e6);
        uint256 balBefore = plan.usdcBalance();

        vm.prank(alice);
        plan.contributeNative{value: expectedNative}(single(0));

        assertTrue(plan.hasContributed(alice, 0));
        assertEq(plan.usdcBalance(), balBefore + 100e6);
        assertEq(plan.trackedLiabilities(), 100e6);
    }

    function test_contribute_nativeRail_dustReverts() public {
        vm.prank(alice);
        plan.join(address(0));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArcUsdcLib.NativePrecisionLoss.selector, 1e12 - 1));
        plan.contributeNative{value: 1e12 - 1}(single(0));
    }

    function test_contribute_nativeRail_wrongValueReverts() public {
        vm.prank(alice);
        plan.join(address(0));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ArcawoPlan.WrongNativeValue.selector, ArcUsdcLib.toNative(100e6))
        );
        plan.contributeNative{value: ArcUsdcLib.toNative(200e6)}(single(0));
    }

    function test_mixedRails_sameLedger() public {
        vm.prank(alice);
        plan.join(address(0));
        vm.prank(bob);
        plan.join(address(0));

        // Alice pays period 0 on token rail, Bob on native rail.
        contributeToken(plan, alice, single(0));
        vm.prank(bob);
        plan.contributeNative{value: ArcUsdcLib.toNative(100e6)}(single(0));

        assertEq(plan.totalContributed(), 200e6);
        assertEq(plan.usdcBalance(), 200e6); // one pool, two rails
    }

    // ---------------------------------------------------------------------
    // Withdrawals & fees
    // ---------------------------------------------------------------------

    function test_withdraw_afterFullCycle() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, two(0, 1)); // 200 USDC

        vm.warp(plan.cycleEnd());
        assertTrue(plan.isComplete());

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = plan.withdraw();

        // 200 × (1 − 0.01) = 198
        assertEq(payout, 198e6);
        assertEq(usdc.balanceOf(alice), balBefore + 198e6);
        assertEq(plan.claimed(alice), 198e6);

        // Collector fee pool: 2 USDC
        assertEq(plan.accruedCollectorFees(), 2e6);
        vm.prank(collector);
        uint256 fees = plan.claimFees();
        assertEq(fees, 2e6);
        assertEq(plan.trackedLiabilities(), 0);
    }

    function test_withdrawEarly_penalty() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0)); // 100 USDC

        vm.prank(alice);
        uint256 payout = plan.withdrawEarly();

        // gross 100; fee 1%; afterFees 99; penalty 2% of 99 = 1.98; payout 97.02
        assertEq(payout, 97.02e6);
        assertEq(plan.accruedCollectorFees(), 1e6 + 1.98e6);
    }

    function test_withdraw_beforeEnd_reverts() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));
        vm.prank(alice);
        vm.expectRevert(ArcawoPlan.PlanNotFinished.selector);
        plan.withdraw();
    }

    function test_withdrawEarly_afterEnd_reverts() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));
        vm.warp(plan.cycleEnd());
        vm.prank(alice);
        vm.expectRevert(ArcawoPlan.PlanInactive.selector);
        plan.withdrawEarly();
    }

    function test_withdraw_twiceReverts() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));
        vm.warp(plan.cycleEnd());
        vm.prank(alice);
        plan.withdraw();
        vm.prank(alice);
        vm.expectRevert(ArcawoPlan.NothingToWithdraw.selector);
        plan.withdraw();
    }

    function test_endPlan_opensWithdrawalsEarly() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));

        vm.prank(collector);
        plan.endPlan();
        assertTrue(plan.isComplete());

        // Full withdrawal without early-exit penalty (collector ended it).
        vm.prank(alice);
        uint256 payout = plan.withdraw();
        assertEq(payout, 99e6);
    }

    function test_feesAccrueOnlyOnWithdrawal() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));
        vm.warp(plan.cycleEnd());

        // Member never withdraws → collector earns nothing on that balance.
        vm.prank(collector);
        vm.expectRevert(ArcawoPlan.NothingToClaim.selector);
        plan.claimFees();

        vm.prank(alice);
        plan.withdraw();
        vm.prank(collector);
        assertEq(plan.claimFees(), 1e6);
    }

    // ---------------------------------------------------------------------
    // Pause / emergency
    // ---------------------------------------------------------------------

    function test_pause_blocksDeposits_notExits() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));

        vm.prank(guardian);
        plan.pause();

        // New joins/deposits blocked while paused (plan still active).
        vm.prank(bob);
        vm.expectRevert();
        plan.join(address(0));

        vm.warp(plan.cycleEnd());

        // Withdrawal still available while paused.
        vm.prank(alice);
        assertEq(plan.withdraw(), 99e6);

        vm.prank(guardian);
        plan.unpause();
    }

    function test_pause_onlyGuardian() public {
        vm.prank(alice);
        vm.expectRevert(EscrowBase.OnlyGuardian.selector);
        plan.pause();
    }

    function test_rescueExcess_cannotTouchPrincipal() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0)); // 100 USDC tracked

        // Unsolicited donation via direct token transfer.
        vm.prank(dave);
        usdc.transfer(address(plan), 25e6);

        assertEq(plan.excess(), 25e6);

        vm.prank(guardian);
        uint256 rescued = plan.rescueExcess(guardian);
        assertEq(rescued, 25e6);
        assertEq(plan.usdcBalance(), 100e6); // principal untouched
        assertEq(plan.trackedLiabilities(), 100e6);

        // Nothing left to rescue.
        vm.prank(guardian);
        vm.expectRevert(EscrowBase.ZeroAmount.selector);
        plan.rescueExcess(guardian);
    }

    function test_rescueExcess_onlyCollectorOrGuardian() public {
        vm.prank(alice);
        vm.expectRevert(EscrowBase.NotAuthorized.selector);
        plan.rescueExcess(alice);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function test_claimableOf() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));

        // Early: 100 × 0.99 × 0.98 = 97.02
        assertEq(plan.claimableOf(alice), 97.02e6);
        vm.warp(plan.cycleEnd());
        // After cycle: 99
        assertEq(plan.claimableOf(alice), 99e6);
    }

    function test_currentPeriod_math() public {
        assertEq(plan.currentPeriod(), 0);
        vm.warp(block.timestamp + 7 days);
        assertEq(plan.currentPeriod(), 1);
        vm.warp(block.timestamp + 11 * 7 days);
        assertEq(plan.currentPeriod(), 12); // clamped at durationPeriods
    }

    // ---------------------------------------------------------------------
    // Reputation reporting
    // ---------------------------------------------------------------------

    function test_reputation_reportedOnNaturalCompletion() public {
        vm.prank(alice);
        plan.join(address(0));
        contributeToken(plan, alice, single(0));
        vm.warp(plan.cycleEnd());
        vm.prank(alice);
        plan.withdraw();

        CollectorReputation.Stats memory s = reputation.statsOf(collector);
        assertEq(s.plansCompleted, 1);
        assertEq(reputation.score(collector), 520); // 500 + 20 completion
    }

    function test_reputation_reportedOnEarlyEnd() public {
        vm.prank(collector);
        plan.endPlan();
        CollectorReputation.Stats memory s = reputation.statsOf(collector);
        assertEq(s.plansEndedEarly, 1);
        assertLt(reputation.score(collector), 500); // penalized
    }

    // ---------------------------------------------------------------------
    // Referral / protocol fees
    // ---------------------------------------------------------------------

    function test_protocolFee_referralSplit() public {
        // Protocol fee 1% with 50% of it shared to referrers.
        vm.prank(owner);
        factory.setConfig(guardian, treasury, address(reputation), 100, 5000);

        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        p.feeBps = 0; // isolate protocol fee
        vm.prank(collector);
        ArcawoPlan feePlan = ArcawoPlan(factory.createPlan(p, bytes32("feeplan"), referrer));

        vm.prank(alice);
        feePlan.join(referrer);
        contributeToken(feePlan, alice, single(0)); // 100 USDC

        vm.warp(feePlan.cycleEnd());
        vm.prank(alice);
        uint256 payout = feePlan.withdraw();
        assertEq(payout, 99e6); // 100 − 1% protocol

        // Protocol fee 1: half to referrer (50%), half to treasury.
        assertEq(feePlan.accruedReferralFees(referrer), 0.5e6);
        assertEq(feePlan.accruedProtocolFees(), 0.5e6);

        vm.prank(referrer);
        assertEq(feePlan.claimReferralFees(), 0.5e6);
        vm.prank(treasury);
        assertEq(feePlan.claimProtocolFees(), 0.5e6);
    }
}
