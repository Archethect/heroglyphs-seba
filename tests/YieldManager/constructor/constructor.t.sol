// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { YieldManager } from "src/YieldManager.sol";

contract ConstructorTest is BaseTest {
    function test_RevertWhen_AdminIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            address(0),
            users.automator,
            contracts.boostPool,
            contracts.apxETH,
            contracts.apxETHVault,
            contracts.pybapxETH
        );
    }

    function test_RevertWhen_AutomatorIsZero() external whenAdminIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            address(0),
            contracts.boostPool,
            contracts.apxETH,
            contracts.apxETHVault,
            contracts.pybapxETH
        );
    }

    function test_RevertWhen_BoostpoolIsZero() external whenAdminIsNotZero whenAutomatorIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            address(0),
            contracts.apxETH,
            contracts.apxETHVault,
            contracts.pybapxETH
        );
    }

    function test_RevertWhen_ApxETHIsZero() external whenAdminIsNotZero whenAutomatorIsNotZero whenBoostpoolIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            contracts.boostPool,
            address(0),
            contracts.apxETHVault,
            contracts.pybapxETH
        );
    }

    function test_RevertWhen_ApxEthVaultIsZero()
        external
        whenAdminIsNotZero
        whenAutomatorIsNotZero
        whenBoostpoolIsNotZero
        whenApxETHIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            contracts.boostPool,
            contracts.apxETH,
            address(0),
            contracts.pybapxETH
        );
    }

    function test_RevertWhen_PybapxEthIsZero()
        external
        whenAdminIsNotZero
        whenAutomatorIsNotZero
        whenBoostpoolIsNotZero
        whenApxETHIsNotZero
        whenApxEthVaultIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            contracts.boostPool,
            contracts.apxETH,
            contracts.apxETHVault,
            address(0)
        );
    }

    function test_WhenPybapxEthIsNotZero()
        external
        whenAdminIsNotZero
        whenAutomatorIsNotZero
        whenBoostpoolIsNotZero
        whenApxETHIsNotZero
        whenApxEthVaultIsNotZero
    {
        YieldManager localYieldManager = new YieldManager(
            users.admin,
            users.automator,
            contracts.boostPool,
            contracts.apxETH,
            contracts.apxETHVault,
            contracts.pybapxETH
        );

        // it should give admin the admin role
        assertTrue(
            localYieldManager.hasRole(localYieldManager.ADMIN_ROLE(), users.admin),
            "YieldManager: admin should have the admin role"
        );
        assertEq(
            localYieldManager.getRoleAdmin(localYieldManager.ADMIN_ROLE()),
            localYieldManager.ADMIN_ROLE(),
            "YieldManager: admin role should be admin"
        );
        // it should give automator the automator role
        assertTrue(
            localYieldManager.hasRole(localYieldManager.AUTOMATOR_ROLE(), users.automator),
            "YieldManager: automator should have the automator role"
        );
        assertEq(
            localYieldManager.getRoleAdmin(localYieldManager.AUTOMATOR_ROLE()),
            localYieldManager.ADMIN_ROLE(),
            "YieldManager: automator role should be admin"
        );
        // it should set boostpool
        assertEq(
            address(localYieldManager.boostPool()),
            address(contracts.boostPool),
            "YieldManager: boostpool should be set correctly"
        );
        // it should set apxETH
        assertEq(
            address(localYieldManager.apxETH()),
            address(contracts.apxETH),
            "YieldManager: apxETH should be set correctly"
        );
        // it should sep apxEthVault
        assertEq(
            address(localYieldManager.apxEthVault()),
            address(contracts.apxETHVault),
            "YieldManager: apxEthVault should be set correctly"
        );
        // it should set pybapxEth
        assertEq(
            address(localYieldManager.pybapxEth()),
            address(contracts.pybapxETH),
            "YieldManager: pybapxEth should be set correctly"
        );
    }
}*/
