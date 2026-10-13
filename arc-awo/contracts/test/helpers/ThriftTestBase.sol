// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ArcawoFactory} from "../../src/ArcawoFactory.sol";
import {ArcawoPlan} from "../../src/ArcawoPlan.sol";
import {IsusuGroup} from "../../src/IsusuGroup.sol";
import {CollectorReputation} from "../../src/CollectorReputation.sol";
import {ArcUsdcLib} from "../../src/libraries/ArcUsdcLib.sol";
import {MockArcUsdc} from "../mocks/MockArcUsdc.sol";

/// @notice Shared harness: etches `MockArcUsdc` at the canonical Arc USDC address so every test
///         runs against Arc's real "one balance, two precisions" semantics (native 18-dec and
///         ERC-20 6-dec draw from one pool). Users are funded with native units, which the mock
///         exposes as USDC at 1e12 scale — exactly like Arc.
abstract contract ThriftTestBase is Test {
    // Actors
    address internal owner = makeAddr("owner");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");
    address internal collector = makeAddr("collector");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal referrer = makeAddr("referrer");

    ArcawoFactory internal factory;
    CollectorReputation internal reputation;

    // Canonical Arc USDC (6-dec ERC-20 face).
    IERC20Like internal usdc = IERC20Like(ArcUsdcLib.USDC);

    uint256 internal constant USDC_UNIT = 1e6; // 1 USDC in app units

    function setUp() public virtual {
        // Etch the Arc-semantics mock at the production USDC address.
        MockArcUsdc impl = new MockArcUsdc();
        vm.etch(ArcUsdcLib.USDC, address(impl).code);

        // Reputation needs the factory; factory needs reputation — deploy factory with a
        // placeholder then wire (or deploy reputation first with predicted factory... simpler:
        // deploy factory with reputation = address(0) is disallowed, so deploy reputation with
        // a temporary factory then setFactory).
        CollectorReputation rep = new CollectorReputation(address(1), owner);
        ArcawoFactory f = new ArcawoFactory(owner, guardian, treasury, address(rep), 0, 0);
        vm.prank(owner);
        rep.setFactory(address(f));

        factory = f;
        reputation = rep;

        // Fund actors with native USDC (mock exposes these as ERC-20 USDC at 1e12 scale).
        address[7] memory actors = [owner, guardian, collector, alice, bob, carol, dave];
        for (uint256 i = 0; i < actors.length; ++i) {
            vm.deal(actors[i], 1_000_000 ether); // 1M native USDC (= $1,000,000)
        }
        vm.deal(referrer, 100 ether);
    }

    // ---------------------------------------------------------------------
    // Param builders
    // ---------------------------------------------------------------------

    function defaultPlanParams() internal view returns (ArcawoPlan.PlanParams memory p) {
        p = ArcawoPlan.PlanParams({
            collector: collector,
            guardian: guardian,
            contributionAmount: 100 * USDC_UNIT, // $100 per period
            frequency: ArcawoPlan.Frequency.Weekly,
            startTime: uint64(block.timestamp),
            durationPeriods: 12,
            feeBps: 100, // 1%
            earlyWithdrawPenaltyBps: 200, // 2%
            protocolFeeBps: 0, // stamped by factory anyway
            referralShareBps: 0,
            treasury: treasury,
            reputation: address(reputation),
            approvalRequired: false,
            maxMembers: 0,
            metadataURI: "Arc-awo test plan"
        });
    }

    function defaultGroupParams() internal view returns (IsusuGroup.GroupParams memory p) {
        p = IsusuGroup.GroupParams({
            collector: collector,
            guardian: guardian,
            contributionAmount: 50 * USDC_UNIT, // $50 per round
            frequency: IsusuGroup.Frequency.Weekly,
            memberCount: 3,
            payoutMode: IsusuGroup.PayoutMode.FixedOrder,
            feeBps: 100, // 1%
            lateFeeBps: 200, // 2%
            protocolFeeBps: 0,
            startDelay: 0,
            treasury: treasury,
            reputation: address(reputation),
            collectorPlays: false,
            metadataURI: "Arc-awo test group"
        });
    }

    function createDefaultPlan() internal returns (ArcawoPlan plan) {
        ArcawoPlan.PlanParams memory p = defaultPlanParams();
        vm.prank(collector);
        plan = ArcawoPlan(factory.createPlan(p, bytes32("plan-1"), address(0)));
    }

    function createDefaultGroup() internal returns (IsusuGroup group) {
        IsusuGroup.GroupParams memory p = defaultGroupParams();
        vm.prank(collector);
        group = IsusuGroup(factory.createGroup(p, bytes32("group-1"), address(0)));
    }

    /// @dev Approve + contribute on the ERC-20 rail.
    function contributeToken(ArcawoPlan plan, address who, uint256[] memory periods) internal {
        ArcawoPlan.PlanParams memory pp = plan.params();
        uint256 amount = pp.contributionAmount * periods.length;
        vm.prank(who);
        usdc.approve(address(plan), amount);
        vm.prank(who);
        plan.contribute(periods);
    }

    function contributeTokenRound(IsusuGroup group, address who, uint256 round) internal {
        (uint256 amount, uint256 lateFee) = _groupDue(group, round);
        vm.prank(who);
        usdc.approve(address(group), amount + lateFee);
        vm.prank(who);
        group.contribute(round);
    }

    function _groupDue(IsusuGroup group, uint256 round) internal view returns (uint256 amount, uint256 lateFee) {
        IsusuGroup.GroupParams memory gp = group.params();
        amount = gp.contributionAmount;
        if (block.timestamp > group.roundEnd(round)) {
            lateFee = (amount * gp.lateFeeBps) / 10_000;
        }
    }

    function single(uint256 v) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = v;
    }

    function two(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }
}

/// @dev Minimal ERC-20 surface used in tests (the etched mock).
interface IERC20Like {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
