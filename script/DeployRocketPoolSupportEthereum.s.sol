// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/src/Script.sol";
import { ISebaPool } from "src/interfaces/ISebaPool.sol";
import { RocketPoolBackPay } from "src/RocketPoolBackPay.sol";

contract DeployRocketPoolSupportEthereum is Script {
    ISebaPool internal sebaPool = ISebaPool(0xe3B17b4533b339d3CBC26F57199d3fb937129894); // Mainnet SebaPool contract

    function run() external {
        //We use a keystore here
        address deployer = msg.sender;
        bytes32 versionSalt = vm.envBytes32("VERSION_SALT_ETHEREUM");
        vm.startBroadcast(deployer);

        new RocketPoolBackPay{ salt: versionSalt }(address(sebaPool));
        vm.stopBroadcast();
    }
}
