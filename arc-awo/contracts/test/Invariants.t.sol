// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ArcawoFactory} from "../src/ArcawoFactory.sol";
import {ArcawoPlan} from "../src/ArcawoPlan.sol";
import {IsusuGroup} from "../src/IsusuGroup.sol";
import {CollectorReputation} from "../src/CollectorReputation.sol";
import {ArcUsdcLib} from "../src/libraries/ArcUsdcLib.sol";
import {MockArcUsdc} from "./mocks/MockArcUsdc.sol";

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev Handler driving random interleavings of user actions against one plan + one group.
contract SolvencyHandler is Test {
    ArcawoPlan public plan;
    IsusuGroup public group;
    address[] public actors;

    constructor(ArcawoPlan plan_, IsusuGroup group_, address[] memory actors_) {
        plan = plan_;
        group = group_;
        actors = actors_;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _joinPlan(address who) internal {
        if (plan.memberOf(who).joinedAt == 0) {
            vm.prank(who);
            try plan.join(address(0)) {} catch {}
        }
    }

    function _joinGroup(address who) internal {
        if (!group.memberOf(who).joined && group.state() == IsusuGroup.GroupState.Open) {
            vm.prank(who);
            try group.join(address(0)) {} catch {}
        }
    }

    function contributePlan(uint256 actorSeed, uint256 period) external {
        address who = _actor(actorSeed);
        _joinPlan(who);
        period = period % 12;
        if (plan.isComplete() || plan.hasContributed(who, period)) return;
        vm.prank(who);
        IERC20Approve(ArcUsdcLib.USDC).approve(address(plan), 100e6);
        uint256[] memory periods = new uint256[](1);
        periods[0] = period;
        vm.prank(who);
        try plan.contribute(periods) {} catch {}
    }

    function withdrawPlan(uint256 actorSeed) external {
        address who = _actor(actorSeed);
        if (plan.memberOf(who).joinedAt == 0 || plan.memberOf(who).withdrawn) return;
        vm.prank(who);
        if (plan.isComplete()) {
            try plan.withdraw() {} catch {}
        } else {
            try plan.withdrawEarly() {} catch {}
        }
    }

    function contributeGroup(uint256 actorSeed, uint256 round) external {
        address who = _actor(actorSeed);
        _joinGroup(who);
        if (group.state() != IsusuGroup.GroupState.Active) return;
        round = round % 3;
        if (round > group.currentRound()) return;
        if (group.memberOf(who).paidBitmap & (1 << round) != 0) return;
        vm.prank(who);
        IERC20Approve(ArcUsdcLib.USDC).approve(address(group), 200e6);
        vm.prank(who);
        try group.contribute(round) {} catch {}
    }

    function claimGroupPot(uint256 round) external {
        round = round % 3;
        if (group.potClaimed(round)) return;
        if (block.timestamp <= group.roundEnd(round)) return;
        address winner = group.winnerOf(round);
        if (winner == address(0)) winner = group.memberAt(round); // FixedOrder
        vm.prank(winner);
        try group.claimPot(round) {} catch {}
    }

    function warpTime(uint256 seconds_) external {
        vm.warp(block.timestamp + (seconds_ % (2 days)));
    }
}

/// @notice Invariant: at every reachable state, each escrow's USDC balance covers its tracked
///         liabilities — no interleaving of contributions/withdrawals/claims can render an
///         escrow insolvent. Executable form of "the collector can never run away with funds
///         and the contract can always pay what it owes".
contract SolvencyInvariantTest is Test {
    SolvencyHandler internal handler;

    function setUp() public {
        MockArcUsdc impl = new MockArcUsdc();
        vm.etch(ArcUsdcLib.USDC, address(impl).code);

        address owner = makeAddr("owner");
        address guardian = makeAddr("guardian");
        address treasury = makeAddr("treasury");
        address collector = makeAddr("collector");

        CollectorReputation rep = new CollectorReputation(address(1), owner);
        ArcawoFactory f = new ArcawoFactory(owner, guardian, treasury, address(rep), 0, 0);
        vm.prank(owner);
        rep.setFactory(address(f));

        address[] memory actors = new address[](4);
        actors[0] = makeAddr("a1");
        actors[1] = makeAddr("a2");
        actors[2] = makeAddr("a3");
        actors[3] = collector;
        for (uint256 i = 0; i < actors.length; ++i) {
            vm.deal(actors[i], 100_000 ether);
        }

        ArcawoPlan.PlanParams memory pp = ArcawoPlan.PlanParams({
            collector: collector,
            guardian: guardian,
            contributionAmount: 100e6,
            frequency: ArcawoPlan.Frequency.Daily,
            startTime: uint64(block.timestamp),
            durationPeriods: 12,
            feeBps: 100,
            earlyWithdrawPenaltyBps: 200,
            protocolFeeBps: 0,
            referralShareBps: 0,
            treasury: treasury,
            reputation: address(rep),
            approvalRequired: false,
            maxMembers: 0,
            metadataURI: "invariant-plan"
        });
        vm.prank(collector);
        ArcawoPlan plan = ArcawoPlan(f.createPlan(pp, bytes32("ip"), address(0)));

        IsusuGroup.GroupParams memory gp = IsusuGroup.GroupParams({
            collector: collector,
            guardian: guardian,
            contributionAmount: 50e6,
            frequency: IsusuGroup.Frequency.Daily,
            memberCount: 3,
            payoutMode: IsusuGroup.PayoutMode.FixedOrder,
            feeBps: 100,
            lateFeeBps: 200,
            protocolFeeBps: 0,
            startDelay: 0,
            treasury: treasury,
            reputation: address(rep),
            collectorPlays: false,
            metadataURI: "invariant-group"
        });
        vm.prank(collector);
        IsusuGroup group = IsusuGroup(f.createGroup(gp, bytes32("ig"), address(0)));

        handler = new SolvencyHandler(plan, group, actors);
        targetContract(address(handler));
    }

    function invariant_escrowAlwaysSolvent() public view {
        assertGe(ArcUsdcLib.balanceOf(address(handler.plan())), handler.plan().trackedLiabilities());
        assertGe(ArcUsdcLib.balanceOf(address(handler.group())), handler.group().trackedLiabilities());
    }
}
