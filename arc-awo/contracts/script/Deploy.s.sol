// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {ArcawoFactory} from "../src/ArcawoFactory.sol";
import {CollectorReputation} from "../src/CollectorReputation.sol";

/// @notice Deploys the Arc-awo core: CollectorReputation + ArcawoFactory.
///         Plan/Group instances are created by users through the factory at runtime.
///
///         Usage:
///           forge script script/Deploy.s.sol --rpc-url arc_testnet --broadcast \
///             --verify --etherscan-api-key $BLOCK_EXPLORER_API_KEY
///
///         Required env:
///           PRIVATE_KEY          — deployer key (pays gas in native USDC on Arc)
///           GUARDIAN_ADDRESS     — ops multisig (pause switches)
///           TREASURY_ADDRESS     — protocol fee destination (can be deployer at first)
///           PROTOCOL_FEE_BPS     — optional (default 0)
///           REFERRAL_SHARE_BPS   — optional (default 0)
contract Deploy is Script {
    function run() external returns (ArcawoFactory factory, CollectorReputation reputation) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint16 protocolFeeBps = uint16(vm.envOr("PROTOCOL_FEE_BPS", uint256(0)));
        uint16 referralShareBps = uint16(vm.envOr("REFERRAL_SHARE_BPS", uint256(0)));

        vm.startBroadcast(pk);
        address deployer = vm.addr(pk);

        // Reputation needs the factory address for instance verification and the factory
        // needs the reputation address — deploy reputation with the deployer as temporary
        // factory pointer holder, then wire both.
        CollectorReputation rep = new CollectorReputation(deployer, deployer);
        ArcawoFactory f = new ArcawoFactory(deployer, guardian, treasury, address(rep), protocolFeeBps, referralShareBps);
        rep.setFactory(address(f));

        vm.stopBroadcast();

        console2.log("CollectorReputation:", address(rep));
        console2.log("ArcawoFactory:      ", address(f));
        console2.log("USDC (Arc native):  ", 0x3600000000000000000000000000000000000000);

        return (f, rep);
    }
}
