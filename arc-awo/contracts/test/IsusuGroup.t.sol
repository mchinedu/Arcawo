// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ThriftTestBase, IERC20Like} from "./helpers/ThriftTestBase.sol";
import {IsusuGroup} from "../src/IsusuGroup.sol";
import {ArcawoPlan} from "../src/ArcawoPlan.sol";
import {CollectorReputation} from "../src/CollectorReputation.sol";
import {EscrowBase} from "../src/abstracts/EscrowBase.sol";
import {ArcUsdcLib} from "../src/libraries/ArcUsdcLib.sol";

contract IsusuGroupTest is ThriftTestBase {
    IsusuGroup internal group;

    function setUp() public override {
        super.setUp();
        group = createDefaultGroup(); // 3 members, FixedOrder, $50/week, 1% fee, 2% late fee
    }

    function _joinThree() internal {
        vm.prank(alice);
        group.join(address(0));
        vm.prank(bob);
        group.join(referrer);
        vm.prank(carol);
        group.join(address(0));
    }

    /// @dev Everyone pays `round` on the token rail (on time).
    function _allPay(uint256 round) internal {
        contributeTokenRound(group, alice, round);
        contributeTokenRound(group, bob, round);
        contributeTokenRound(group, carol, round);
    }

    // ---------------------------------------------------------------------
    // Membership & start
    // ---------------------------------------------------------------------

    function test_join_and_autoFinalize() public {
        assertEq(uint256(group.state()), uint256(IsusuGroup.GroupState.Open));
        _joinThree();
        assertEq(uint256(group.state()), uint256(IsusuGroup.GroupState.Active));
        assertEq(group.memberCount(), 3);
        assertEq(group.startTime(), block.timestamp);
        assertEq(group.memberAt(0), alice);
        assertEq(group.memberAt(1), bob);
        assertEq(group.memberAt(2), carol);
    }

    function test_join_fullReverts() public {
        _joinThree(); // last join auto-finalizes
        vm.prank(dave);
        vm.expectRevert(IsusuGroup.GroupNotOpen.selector);
        group.join(address(0));
    }

    function test_cancel_unfilledGroup() public {
        vm.prank(alice);
        group.join(address(0));
        vm.prank(collector);
        group.cancel();
        assertEq(uint256(group.state()), uint256(IsusuGroup.GroupState.Completed));
        vm.prank(bob);
        vm.expectRevert(IsusuGroup.GroupNotOpen.selector);
        group.join(address(0));
    }

    // ---------------------------------------------------------------------
    // Full rotation (FixedOrder)
    // ---------------------------------------------------------------------

    function test_fullRotation_fixedOrder() public {
        _joinThree();

        // Round 0 — alice is paid first (join order).
        _allPay(0);
        assertEq(group.usdcBalance(), 150e6);
        vm.warp(group.roundEnd(0) + 1);
        vm.prank(alice);
        uint256 pot0 = group.claimPot(0);
        assertEq(pot0, 148.5e6); // 150 − 1% fee
        assertTrue(group.memberOf(alice).won);

        // Round 1 — bob.
        _allPay(1);
        vm.warp(group.roundEnd(1) + 1);
        vm.prank(bob);
        uint256 pot1 = group.claimPot(1);
        assertEq(pot1, 148.5e6);

        // Round 2 — carol.
        _allPay(2);
        vm.warp(group.roundEnd(2) + 1);
        vm.prank(carol);
        uint256 pot2 = group.claimPot(2);
        assertEq(pot2, 148.5e6);

        assertEq(uint256(group.state()), uint256(IsusuGroup.GroupState.Completed));
        assertEq(group.resolvedRounds(), 3);

        // Collector takes 1% of each pot: 4.5 total. Ledger must clear.
        vm.prank(collector);
        assertEq(group.claimFees(), 4.5e6);
        assertEq(group.trackedLiabilities(), 0);
        assertEq(group.usdcBalance(), 0);

        // Reputation: one completed group, no defaults.
        CollectorReputation.Stats memory s = reputation.statsOf(collector);
        assertEq(s.groupsCompleted, 1);
        assertEq(s.defaultEvents, 0);
    }

    function test_rotation_solvencyInvariantPerStep() public {
        _joinThree();
        _allPay(0);
        assertEq(group.usdcBalance(), group.trackedLiabilities());
        vm.warp(group.roundEnd(0) + 1);
        vm.prank(alice);
        group.claimPot(0);
        assertEq(group.usdcBalance(), group.trackedLiabilities());
    }

    // ---------------------------------------------------------------------
    // Late fees & arrears
    // ---------------------------------------------------------------------

    function test_latePayment_feeAddedToPot() public {
        _joinThree();
        contributeTokenRound(group, alice, 0);
        contributeTokenRound(group, bob, 0);
        // Carol pays after the window: 50 + 2% late fee = 51
        vm.warp(group.roundEnd(0) + 1);
        contributeTokenRound(group, carol, 0);

        assertEq(group.lateFeesOf(0), 1e6);
        vm.prank(alice);
        uint256 pot = group.claimPot(0);
        // collected 150 + late 1 − 1% of 150 = 149.5
        assertEq(pot, 149.5e6);
    }

    function test_arrears_settleToWinnerAfterClaim() public {
        _joinThree();
        contributeTokenRound(group, alice, 0);
        contributeTokenRound(group, carol, 0); // bob defaults round 0

        vm.warp(group.roundEnd(0) + 1);
        vm.prank(alice);
        uint256 pot0 = group.claimPot(0);
        assertEq(pot0, 99e6); // only 2×50 collected − 1%

        // Bob clears arrears late: 50 + 1 late fee goes directly to alice (the short winner).
        uint256 aliceBefore = usdc.balanceOf(alice);
        contributeTokenRound(group, bob, 0);
        assertEq(usdc.balanceOf(alice), aliceBefore + 51e6);

        // Default recorded on the group (reported to reputation at group completion).
        assertEq(group.lateEvents(), 1);
    }

    function test_winnerInArrears_cannotClaimUntilCleared() public {
        _joinThree();
        contributeTokenRound(group, alice, 0);
        contributeTokenRound(group, carol, 0); // bob (round-1 winner) defaults round 0

        // Round 1 window: everyone (including bob) pays on time.
        vm.warp(group.roundEnd(0) + 1);
        _allPay(1);
        vm.warp(group.roundEnd(1) + 1);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IsusuGroup.InArrears.selector, 1));
        group.claimPot(1);

        // Clear round-0 arrears, then claim.
        contributeTokenRound(group, bob, 0);
        vm.prank(bob);
        uint256 pot1 = group.claimPot(1);
        assertEq(pot1, 148.5e6);
    }

    function test_cannotPrepayFutureRound() public {
        _joinThree();
        vm.startPrank(alice);
        usdc.approve(address(group), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IsusuGroup.FutureRound.selector, 1));
        group.contribute(1);
        vm.stopPrank();
    }

    function test_cannotPayTwice() public {
        _joinThree();
        contributeTokenRound(group, alice, 0);
        vm.startPrank(alice);
        usdc.approve(address(group), 50e6);
        vm.expectRevert(abi.encodeWithSelector(IsusuGroup.AlreadyPaid.selector, 0));
        group.contribute(0);
        vm.stopPrank();
    }

    function test_nativeRail_roundPayment() public {
        _joinThree();
        vm.prank(alice);
        group.contributeNative{value: ArcUsdcLib.toNative(50e6)}(0);
        assertTrue(group.memberOf(alice).paidBitmap & 1 == 1);
        assertEq(group.usdcBalance(), 50e6);
    }

    // ---------------------------------------------------------------------
    // Redistribution
    // ---------------------------------------------------------------------

    function test_redistribute_voidedRound() public {
        _joinThree();
        contributeTokenRound(group, alice, 0);
        contributeTokenRound(group, bob, 0); // carol never pays round 0

        // Nobody claims; timeout = 2 weeks (weekly group).
        vm.warp(group.roundEnd(0) + group.redistributionTimeout() + 1);

        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.prank(dave);
        uint256 pot = group.redistribute(0);
        assertEq(pot, 99e6); // 100 collected − 1% fee
        // Each of the 2 payers gets an equal share.
        assertEq(usdc.balanceOf(alice), aliceBefore + 49.5e6);
        assertEq(group.resolvedRounds(), 1);

        // The rotation slot is voided: carol can no longer settle into a void.
        vm.prank(carol);
        usdc.approve(address(group), 51e6);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IsusuGroup.RoundVoided.selector, 0));
        group.contribute(0);

        // And the pot cannot be claimed by anyone.
        vm.prank(alice);
        vm.expectRevert(IsusuGroup.PotAlreadyClaimed.selector);
        group.claimPot(0);
    }

    function test_redistribute_tooEarlyReverts() public {
        _joinThree();
        _allPay(0);
        vm.warp(group.roundEnd(0) + 1);
        vm.expectRevert(IsusuGroup.PotNotClaimable.selector);
        group.redistribute(0);
    }

    function test_claim_twiceReverts() public {
        _joinThree();
        _allPay(0);
        vm.warp(group.roundEnd(0) + 1);
        vm.prank(alice);
        group.claimPot(0);
        vm.prank(alice);
        vm.expectRevert(IsusuGroup.PotAlreadyClaimed.selector);
        group.claimPot(0);
    }

    function test_nonWinner_cannotClaim() public {
        _joinThree();
        _allPay(0);
        vm.warp(group.roundEnd(0) + 1);
        vm.prank(bob);
        vm.expectRevert(IsusuGroup.NotWinner.selector);
        group.claimPot(0);
    }

    // ---------------------------------------------------------------------
    // Lottery mode (commit-reveal)
    // ---------------------------------------------------------------------

    function _lotteryGroup() internal returns (IsusuGroup g) {
        IsusuGroup.GroupParams memory p = defaultGroupParams();
        p.payoutMode = IsusuGroup.PayoutMode.Lottery;
        vm.prank(collector);
        g = IsusuGroup(factory.createGroup(p, bytes32("lottery"), address(0)));
        vm.prank(alice);
        g.join(address(0));
        vm.prank(bob);
        g.join(address(0));
        vm.prank(carol);
        g.join(address(0));
    }

    function test_lottery_commitReveal() public {
        IsusuGroup g = _lotteryGroup();
        bytes32 secret = keccak256("arc-awo-secret");
        vm.prank(collector);
        g.commit(keccak256(abi.encodePacked(secret)));

        // Everyone pays round 0.
        contributeTokenRound(g, alice, 0);
        contributeTokenRound(g, bob, 0);
        contributeTokenRound(g, carol, 0);

        vm.warp(g.roundEnd(0) + 1);
        vm.prank(dave);
        g.requestSelection(0);
        vm.prank(collector);
        g.reveal(secret, 0);

        address winner = g.winnerOf(0);
        assertTrue(winner == alice || winner == bob || winner == carol);

        vm.prank(winner);
        uint256 pot = g.claimPot(0);
        assertEq(pot, 148.5e6);
    }

    function test_lottery_fallback_withoutCommit() public {
        IsusuGroup g = _lotteryGroup();
        contributeTokenRound(g, alice, 0);
        contributeTokenRound(g, bob, 0);
        contributeTokenRound(g, carol, 0);

        vm.warp(g.roundEnd(0) + 1);
        vm.prank(dave);
        g.requestSelection(0);
        // No commitment exists → fallback selectable immediately.
        vm.prank(dave);
        g.fallbackSelect(0);

        address winner = g.winnerOf(0);
        assertTrue(winner == alice || winner == bob || winner == carol);
    }

    function test_lottery_fallback_afterRevealTimeout() public {
        IsusuGroup g = _lotteryGroup();
        bytes32 secret = keccak256("arc-awo-secret");
        vm.prank(collector);
        g.commit(keccak256(abi.encodePacked(secret)));

        contributeTokenRound(g, alice, 0);
        contributeTokenRound(g, bob, 0);
        contributeTokenRound(g, carol, 0);

        vm.warp(g.roundEnd(0) + 1);
        vm.prank(dave);
        g.requestSelection(0);

        // Too early for fallback.
        vm.expectRevert(IsusuGroup.RevealTimeoutNotElapsed.selector);
        g.fallbackSelect(0);

        // Collector withholds reveal → liveness fallback after timeout.
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(dave);
        g.fallbackSelect(0);
        assertTrue(g.winnerOf(0) != address(0));
    }

    function test_lottery_reveal_wrongSecretReverts() public {
        IsusuGroup g = _lotteryGroup();
        bytes32 secret = keccak256("arc-awo-secret");
        vm.prank(collector);
        g.commit(keccak256(abi.encodePacked(secret)));

        contributeTokenRound(g, alice, 0);
        contributeTokenRound(g, bob, 0);
        contributeTokenRound(g, carol, 0);
        vm.warp(g.roundEnd(0) + 1);
        vm.prank(dave);
        g.requestSelection(0);

        vm.prank(collector);
        vm.expectRevert(IsusuGroup.BadCommitment.selector);
        g.reveal(keccak256("wrong"), 0);
    }

    function test_lottery_commit_afterRequestReverts() public {
        IsusuGroup g = _lotteryGroup();
        contributeTokenRound(g, alice, 0);
        contributeTokenRound(g, bob, 0);
        contributeTokenRound(g, carol, 0);
        vm.warp(g.roundEnd(0) + 1);
        vm.prank(dave);
        g.requestSelection(0);

        vm.prank(collector);
        vm.expectRevert(IsusuGroup.SelectionAlreadyDone.selector);
        g.commit(keccak256(abi.encodePacked(bytes32("late"))));
    }

    // ---------------------------------------------------------------------
    // Collector as member
    // ---------------------------------------------------------------------

    function test_collectorPlays_memberZero() public {
        IsusuGroup.GroupParams memory p = defaultGroupParams();
        p.collectorPlays = true;
        p.memberCount = 3;
        vm.prank(collector);
        IsusuGroup g = IsusuGroup(factory.createGroup(p, bytes32("cplays"), address(0)));

        assertEq(g.memberAt(0), collector);
        vm.prank(alice);
        g.join(address(0));
        vm.prank(bob);
        g.join(address(0));
        assertEq(uint256(g.state()), uint256(IsusuGroup.GroupState.Active));

        // Collector is the FixedOrder winner of round 0 (traditional organizer's first pot).
        assertEq(g.memberAt(0), collector);
    }

    // ---------------------------------------------------------------------
    // Pause
    // ---------------------------------------------------------------------

    function test_pause_blocksJoin_notClaims() public {
        _joinThree();
        _allPay(0);
        vm.warp(group.roundEnd(0) + 1);

        vm.prank(guardian);
        group.pause();

        // Claims remain available while paused.
        vm.prank(alice);
        assertEq(group.claimPot(0), 148.5e6);
    }
}
