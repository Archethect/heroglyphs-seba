// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
contract SetIntakeEnabledTest is ManagerTestBase {
    function test_OnlySafeAndBoundVaultsAndCanPauseWithoutVenues() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.setIntakeEnabled(true);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setIntakeEnabled(true);
        vm.prank(address(safe));
        manager.setIntakeEnabled(false);
        _bind();
        vm.prank(address(safe));
        manager.setIntakeEnabled(true);
        assertTrue(manager.intakeEnabled());
        ysyToken.setBrokenBalance(true);
        vm.prank(address(safe));
        manager.setIntakeEnabled(false);
        assertFalse(manager.intakeEnabled());
    }
}
