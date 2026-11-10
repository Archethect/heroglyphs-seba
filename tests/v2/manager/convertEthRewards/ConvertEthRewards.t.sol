// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
contract ConvertEthRewardsTest is ManagerTestBase {
    function test_DeprecatedSynchronousEthRouteCannotSpendFunds() public {
        _enable();
        _fund(40 ether);
        vm.expectRevert(IYieldManagerV2.AsyncOrderRequired.selector);
        vm.prank(operator);
        manager.convertEthRewards(20 ether, 1, block.timestamp);
        assertEq(manager.pendingEth(0), 20 ether);
        assertEq(address(manager).balance, 40 ether);
        _settleReward(20 ether);
        assertEq(manager.pendingEth(0), 0);
        assertEq(manager.pendingEth(1), 10 ether);
        assertEq(manager.pendingEth(2), 10 ether);
        assertEq(manager.pendingBold(), 20 ether);
    }
    function test_DeprecatedRouteStillChecksOperator() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.convertEthRewards(1, 1, block.timestamp);
    }
}
