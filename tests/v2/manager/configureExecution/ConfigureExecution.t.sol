// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase, ManagerExecutorMock } from "../ManagerTestBase.t.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ConfigureExecutionTest is ManagerTestBase {
    function test_SafeConfiguresWhileDisabledAndReplacementHasNoAllowances() public {
        vm.prank(address(safe));
        manager.configureExecution(address(execution), 5, 6, 7);
        assertEq(address(manager.executor()), address(execution));
        assertEq(manager.maximumEth(), 5);
        assertEq(manager.maximumYieldTokens(0), 6);
        assertEq(manager.maximumYieldTokens(1), 7);
        ManagerExecutorMock replacement = new ManagerExecutorMock(execution.configuration());
        vm.prank(address(safe));
        manager.configureExecution(address(replacement), 8, 9, 10);
        assertEq(address(manager.executor()), address(replacement));
    }
    function test_AllWrongExecutorIdentitiesReject() public {
        for (uint8 i; i < 10; ++i) {
            IV2Executor.Config memory c = execution.configuration();
            address wrong = address(pool);
            if (i == 0) c.manager = wrong;
            if (i == 1) c.treasury = wrong;
            if (i == 2) c.reth = wrong;
            if (i == 3) c.ysyBold = wrong;
            if (i == 4) c.bold = wrong;
            if (i == 5) c.yBold = wrong;
            if (i == 6) c.weth = address(0);
            if (i == 7) c.usdc = address(0);
            if (i > 7) {
                vm.prank(address(safe));
                manager.configureExecution(address(execution), 1, 1, 1);
                if (i == 8) c.weth = wrong;
                else c.usdc = wrong;
            }
            ManagerExecutorMock bad = new ManagerExecutorMock(c);
            vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
            vm.prank(address(safe));
            manager.configureExecution(address(bad), 1, 1, 1);
        }
    }
    function test_CapsAndCodeAndAuthorityAndEnabledGate() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.configureExecution(address(execution), 1, 1, 1);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.configureExecution(address(0), 1, 1, 1);
        for (uint8 i; i < 3; ++i) {
            vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
            vm.prank(address(safe));
            manager.configureExecution(address(execution), i == 0 ? 0 : 1, i == 1 ? 0 : 1, i == 2 ? 0 : 1);
        }
        _enable();
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.configureExecution(address(execution), 1, 1, 1);
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.configureExecution(address(execution), 1, 1, 1);
    }
    function test_OldExecutorOutstandingAllowancePreventsReplacement() public {
        vm.prank(address(safe));
        manager.configureExecution(address(execution), 1, 1, 1);
        vm.prank(address(manager));
        rethToken.approve(address(execution), 1);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.configureExecution(address(execution), 1, 1, 1);
        vm.prank(address(manager));
        rethToken.approve(address(execution), 0);
        vm.prank(address(manager));
        ysyToken.approve(address(execution), 1);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.configureExecution(address(execution), 1, 1, 1);
    }
}
