// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ThriftTestBase} from "./helpers/ThriftTestBase.sol";
import {ArcawoFactory} from "../src/ArcawoFactory.sol";
import {ArcawoPlan} from "../src/ArcawoPlan.sol";
import {IsusuGroup} from "../src/IsusuGroup.sol";
import {CollectorReputation} from "../src/CollectorReputation.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract FactoryTest is ThriftTestBase {
    // ---------------------------------------------------------------------
    // Creation & registry
    // ---------------------------------------------------------------------

    function test_createPlan_registers() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        vm.prank(collector);
        address plan = factory.createPlan(p, bytes32("s1"), referrer);

        assertTrue(factory.isPlan(plan));
        assertFalse(factory.isGroup(plan));
        assertEq(factory.planCount(), 1);
        assertEq(factory.plansOf(collector)[0], plan);
        assertEq(factory.referralCount(referrer), 1);
        assertEq(factory.referralVolume(referrer), 100e6 * 12); // stake × periods estimate
    }

    function test_createGroup_registers() public {
        IsusuGroup.GroupParams memory p = defaultGroupParams();
        vm.prank(collector);
        address group = factory.createGroup(p, bytes32("s1"), address(0));

        assertTrue(factory.isGroup(group));
        assertEq(factory.groupCount(), 1);
        assertEq(factory.groupsOf(collector)[0], group);
    }

    function test_createPlan_distinctSalts_distinctAddresses() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        vm.prank(collector);
        address a = factory.createPlan(p, bytes32("s1"), address(0));
        vm.prank(collector);
        address b = factory.createPlan(p, bytes32("s2"), address(0));
        assertTrue(a != b);
    }

    function test_createPlan_sameSaltSameCreatorCollides() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        vm.prank(collector);
        factory.createPlan(p, bytes32("s1"), address(0));
        vm.prank(collector);
        vm.expectRevert();
        factory.createPlan(p, bytes32("s1"), address(0));
    }

    function test_createPlan_otherCreatorSameSalt_noCollision() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        p.collector = alice;
        vm.prank(collector);
        address a = factory.createPlan(p, bytes32("s1"), address(0));
        vm.prank(bob);
        address b = factory.createPlan(p, bytes32("s1"), address(0));
        assertTrue(a != b); // salt is bound to msg.sender
    }

    function test_registry_pagination() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        for (uint256 i = 0; i < 3; ++i) {
            vm.prank(collector);
            factory.createPlan(p, bytes32(i), address(0));
        }
        address[] memory page = factory.plans(1, 2);
        assertEq(page.length, 2);
        assertEq(page[0], factory.allPlans(1));
    }

    // ---------------------------------------------------------------------
    // Validation
    // ---------------------------------------------------------------------

    function test_createPlan_feeCapEnforced() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        p.feeBps = 101; // > 1%
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(ArcawoFactory.BadFee.selector, "feeBps"));
        factory.createPlan(p, bytes32("s1"), address(0));
    }

    function test_createPlan_penaltyCapEnforced() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        p.earlyWithdrawPenaltyBps = 501; // > 5%
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(ArcawoFactory.BadFee.selector, "earlyWithdrawPenaltyBps"));
        factory.createPlan(p, bytes32("s1"), address(0));
    }

    function test_createGroup_lateFeeCapEnforced() public {
        IsusuGroup.GroupParams memory p = defaultGroupParams();
        p.lateFeeBps = 501;
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(ArcawoFactory.BadFee.selector, "lateFeeBps"));
        factory.createGroup(p, bytes32("s1"), address(0));
    }

    function test_createPlan_metadataTooLong() public {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        p.metadataURI = string(new bytes(513));
        vm.prank(collector);
        vm.expectRevert(ArcawoFactory.MetadataTooLong.selector);
        factory.createPlan(p, bytes32("s1"), address(0));
    }

    function test_createGroup_badMemberCount() public {
        IsusuGroup.GroupParams memory p = defaultGroupParams();
        p.memberCount = 101;
        vm.prank(collector);
        vm.expectRevert(IsusuGroup.BadParams.selector);
        factory.createGroup(p, bytes32("s1"), address(0));
    }

    function test_createPlan_stampsProtocolFields() public {
        vm.prank(owner);
        factory.setConfig(guardian, treasury, address(reputation), 50, 2500);

        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        p.guardian = address(0xdead); // ignored input
        p.protocolFeeBps = 9999; // ignored input
        vm.prank(collector);
        ArcawoPlan plan = ArcawoPlan(factory.createPlan(p, bytes32("stamp"), address(0)));

        ArcawoPlan.PlanParams memory stamped = plan.params();
        assertEq(stamped.guardian, guardian);
        assertEq(stamped.protocolFeeBps, 50);
        assertEq(stamped.referralShareBps, 2500);
        assertEq(stamped.treasury, treasury);
        assertEq(stamped.reputation, address(reputation));
    }

    // ---------------------------------------------------------------------
    // Config & pause
    // ---------------------------------------------------------------------

    function test_setConfig_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setConfig(guardian, treasury, address(reputation), 0, 0);
    }

    function test_setConfig_capsEnforced() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ArcawoFactory.BadFee.selector, "fee"));
        factory.setConfig(guardian, treasury, address(reputation), 101, 0);
    }

    function test_pauseFactory_blocksCreation() public {
        vm.prank(guardian);
        factory.pauseFactory();

        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        vm.prank(collector);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        factory.createPlan(p, bytes32("s1"), address(0));

        vm.prank(owner);
        factory.unpauseFactory();
        vm.prank(collector);
        factory.createPlan(p, bytes32("s1"), address(0));
    }

    function test_pauseFactory_onlyGuardian() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.pauseFactory();
    }

    // ---------------------------------------------------------------------
    // Reputation access control
    // ---------------------------------------------------------------------

    function test_reputation_rejectsNonInstance() public {
        vm.prank(alice);
        vm.expectRevert(CollectorReputation.OnlyFactoryInstance.selector);
        reputation.reportPlanOutcome(alice, 100e6, true);
    }

    function test_reputation_score_math() public {
        // Fresh collector: neutral 500.
        assertEq(reputation.score(alice), 500);

        // Report a completed plan worth 25,000 USDC via a real instance.
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        p.contributionAmount = uint256(25_000e6) / 12;
        p.durationPeriods = 12;
        vm.prank(collector);
        ArcawoPlan plan = ArcawoPlan(factory.createPlan(p, bytes32("rep"), address(0)));
        vm.prank(collector);
        plan.endPlan(); // reports ended-early (−15)

        // 500 − 15 = 485 (volume from ended-early still counts: +100)
        // volume = 0 contributions... endPlan reports totalContributed = 0.
        CollectorReputation.Stats memory s = reputation.statsOf(collector);
        assertEq(s.plansEndedEarly, 1);
        assertEq(reputation.score(collector), 485);
    }
}
