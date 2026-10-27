// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";

contract SafeMaintenanceTest is ManagerTestBase {
    function test_SafeMayUseEveryBoundedMaintenanceRoute() public {
        _enable();
        _fund(40 ether);
        rVault.harvest(0, 3);
        yVault.harvest(1, 7);
        vm.startPrank(address(safe));
        manager.deployProtocolPrincipal(0, 1 ether, 1, 1, block.timestamp);
        manager.deployProtocolPrincipal(1, 1 ether, 1, 1, block.timestamp);
        manager.convertHarvest(0, 0, 3, 1, block.timestamp);
        manager.convertHarvest(1, 1, 7, 1, block.timestamp);
        manager.convertEthRewards(1 ether, 1, block.timestamp);
        manager.convertBoldToSBold(1 ether, 1, block.timestamp);
        manager.donateSBold(1 ether);
        vm.stopPrank();
        assertEq(sBoldToken.balanceOf(address(sink)), 1 ether);
    }
}
