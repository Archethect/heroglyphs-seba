// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ActivateYieldFlowTest is BaseTest {
    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertWhen_NotTheAutomatorRole(address caller) external {
        vm.assume(caller != users.automator);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                yieldManager.AUTOMATOR_ROLE()
            )
        );
        resetPrank(caller);
        yieldManager.activateYieldFlow();
    }

    function test_RevertWhen_TheYieldFlowIsAlreadyActive() external whenTheAutomatorRole {
        resetPrank(users.automator);
        yieldManager.activateYieldFlow();

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.YieldFlowAlreadyActivated.selector));
        yieldManager.activateYieldFlow();
    }

    function test_WhenTheYieldFlowIsNotYetActive() external whenTheAutomatorRole {
        resetPrank(users.automator);

        // it should emit YieldFlowActivated
        vm.expectEmit();
        emit IYieldManager.YieldFlowActivated();
        yieldManager.activateYieldFlow();

        // it should set yieldFlowActive to true
        assertTrue(yieldManager.yieldFlowActive());
    }
}
