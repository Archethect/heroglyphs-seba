// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase, ManagerVaultMock } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract BindVaultsTest is ManagerTestBase {
    function test_OnlySafeBindsOnceAndEveryReciprocalIdentityChecked() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.bindVaults(address(rVault), address(yVault));
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.bindVaults(address(rVault), address(rVault));
        for (uint8 i; i < 4; ++i) {
            ManagerVaultMock bad = new ManagerVaultMock(
                i == 0 ? address(ysyToken) : address(rethToken),
                i == 1 ? address(yBoldToken) : address(0),
                i == 2 ? address(pool) : address(manager),
                i == 3 ? address(pool) : address(safe)
            );
            vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
            vm.prank(address(safe));
            manager.bindVaults(address(bad), address(yVault));
        }
        _bind();
        assertEq(manager.vaults(0), address(rVault));
        assertEq(manager.vaults(1), address(yVault));
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.bindVaults(address(rVault), address(yVault));
        vm.prank(address(safe));
        manager.setIntakeEnabled(true);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.bindVaults(address(rVault), address(yVault));
    }
}
