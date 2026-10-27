// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
contract SetExecutionEnabledTest is ManagerTestBase {
    function test_BothBootstrapGatesAndIndependentExecutorGate() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.setExecutionEnabled(true);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setExecutionEnabled(true);
        _bind();
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setExecutionEnabled(true);
        vm.prank(address(safe));
        manager.configureExecution(address(execution), 1, 1, 1);
        execution.setEnabled(false);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setExecutionEnabled(true);
        execution.setEnabled(true);
        vm.prank(address(safe));
        manager.setExecutionEnabled(true);
        assertTrue(manager.executionEnabled());
        vm.prank(address(safe));
        manager.setExecutionEnabled(false);
        assertFalse(manager.executionEnabled());
    }
}
