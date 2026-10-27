// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ConvertEthRewardsTest is ManagerTestBase {
    function setUp() public override {
        super.setUp();
        _enable();
        _fund(40 ether);
    }
    function test_OnlyRewardCashCanConvert() public {
        vm.prank(operator);
        manager.convertEthRewards(20 ether, 20 ether, block.timestamp);
        assertEq(manager.pendingEth(0), 0);
        assertEq(manager.pendingEth(1), 10 ether);
        assertEq(manager.pendingEth(2), 10 ether);
        assertEq(manager.pendingBold(), 20 ether);
    }
    function test_OutputFaultsAndSlippageRollBack() public {
        for (uint8 mode = 1; mode <= 3; ++mode) {
            execution.setMode(mode);
            vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
            vm.prank(operator);
            manager.convertEthRewards(1 ether, 1, block.timestamp);
            assertEq(manager.pendingEth(0), 20 ether);
            assertEq(manager.pendingBold(), 0);
        }
        execution.setMode(0);
        vm.expectRevert(IYieldManagerV2.InsufficientOutput.selector);
        vm.prank(operator);
        manager.convertEthRewards(1 ether, 2 ether, block.timestamp);
    }
    function test_PausedExpiredUnauthorizedAndInvalidAmount() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.convertEthRewards(1, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.Expired.selector);
        vm.prank(operator);
        manager.convertEthRewards(1, 1, block.timestamp - 1);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertEthRewards(0, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertEthRewards(21 ether, 1, block.timestamp);
        vm.prank(address(safe));
        manager.setExecutionEnabled(false);
        vm.expectRevert(IYieldManagerV2.ExecutionDisabled.selector);
        vm.prank(operator);
        manager.convertEthRewards(1, 1, block.timestamp);
    }
    function test_SiblingFailureDoesNotBlockRewardPath() public {
        ysyToken.setBrokenBalance(true);
        rethToken.setBrokenBalance(true);
        vm.prank(operator);
        manager.convertEthRewards(1 ether, 1, block.timestamp);
        assertEq(manager.pendingBold(), 1 ether);
    }
    function test_EthAndBoldDeficitsRejectBeforeSpending() public {
        vm.deal(address(manager), 39 ether);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(operator);
        manager.convertEthRewards(1, 1, block.timestamp);
        vm.deal(address(manager), 40 ether);
        vm.prank(operator);
        manager.convertEthRewards(1 ether, 1, block.timestamp);
        boldToken.burn(address(manager), 1);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(operator);
        manager.convertEthRewards(1, 1, block.timestamp);
    }
}
