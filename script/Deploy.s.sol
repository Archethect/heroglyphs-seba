// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { MockApxETH } from "src/mocks/MockApxETH.sol";
import { Script } from "forge-std/src/Script.sol";
import { MockPirexETH } from "src/mocks/MockPirexETH.sol";
import { YieldManager } from "src/YieldManager.sol";
import { BoostPool } from "src/BoostPool.sol";
import {SebaYieldVault} from "src/PerpYieldBearingAutoPxEth.sol";
import { MockPOAP } from "../src/mocks/MockPoap.sol";
import { ApxETHVault } from "../src/liquidity/ApxETHVault.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";

contract Deploy is Script {
    error InvalidApxETHAddress();
    error InvalidYieldManagerAddress();
    error InvalidBoostPoolAddress();

    function run() external {
        //We use a keystore here
        address deployer = msg.sender;
        bytes32 versionSalt = vm.envBytes32("VERSION_SALT");
        vm.startBroadcast(deployer);
        MockERC721 mockKamisama = new MockERC721{ salt: versionSalt }();
       /* MockPOAP mockPoap = new MockPOAP{ salt: versionSalt }(deployer);
        MockPirexETH pirexETH = new MockPirexETH{ salt: versionSalt }(deployer, 10_000);
        MockApxETH apxETH = new MockApxETH{ salt: versionSalt }(address(pirexETH));
        pirexETH.setApxETH(address(apxETH));
        PerpYieldBearingAutoPxEth pybapxEth = new PerpYieldBearingAutoPxEth{ salt: versionSalt }(deployer, apxETH);
        BoostPool boostPool = new BoostPool{ salt: versionSalt }(deployer, deployer, address(mockPoap));
        ApxETHVault apxETHVault = new ApxETHVault{ salt: versionSalt }(deployer, address(apxETH), address(pybapxEth));
        YieldManager yieldManager = new YieldManager{ salt: versionSalt }(
            deployer,
            deployer,
            address(boostPool),
            address(apxETH),
            address(apxETHVault),
            address(pybapxEth)
        );
        pybapxEth.setBoostPool(address(boostPool));
        boostPool.setPerpYieldBearingAutoPxEth(address(pybapxEth));
        boostPool.setYieldManager(address(yieldManager));
        apxETHVault.setYieldManager(address(yieldManager));*/
        /*vm.stopBroadcast();
    }
}
*/
