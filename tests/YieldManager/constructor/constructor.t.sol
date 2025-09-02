// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { YieldManager } from "src/YieldManager.sol";

contract ConstructorTest is BaseTest {
    function test_RevertWhen_AdminIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            address(0),
            users.automator,
            contracts.sebaPool,
            contracts.ethToBoldRouter,
            contracts.bold,
            contracts.sBOLD,
            contracts.pybSeba,
            contracts.eUsdUsdcBeefyYieldVault
        );
    }

    function test_RevertWhen_AutomatorIsZero() external whenAdminIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            address(0),
            contracts.sebaPool,
            contracts.ethToBoldRouter,
            contracts.bold,
            contracts.sBOLD,
            contracts.pybSeba,
            contracts.eUsdUsdcBeefyYieldVault
        );
    }

    function test_RevertWhen_SebaPoolIsZero() external whenAdminIsNotZero whenAutomatorIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            address(0),
            contracts.ethToBoldRouter,
            contracts.bold,
            contracts.sBOLD,
            contracts.pybSeba,
            contracts.eUsdUsdcBeefyYieldVault
        );
    }

    function test_RevertWhen_RouterIsZero() external whenAdminIsNotZero whenAutomatorIsNotZero whenSebaPoolIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            contracts.sebaPool,
            address(0),
            contracts.bold,
            contracts.sBOLD,
            contracts.pybSeba,
            contracts.eUsdUsdcBeefyYieldVault
        );
    }

    function test_RevertWhen_BoldIsZero()
        external
        whenAdminIsNotZero
        whenAutomatorIsNotZero
        whenSebaPoolIsNotZero
        whenRouterIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            contracts.sebaPool,
            contracts.ethToBoldRouter,
            address(0),
            contracts.sBOLD,
            contracts.pybSeba,
            contracts.eUsdUsdcBeefyYieldVault
        );
    }

    function test_RevertWhen_SBOLDIsZero()
        external
        whenAdminIsNotZero
        whenAutomatorIsNotZero
        whenSebaPoolIsNotZero
        whenRouterIsNotZero
        whenBoldIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            contracts.sebaPool,
            contracts.ethToBoldRouter,
            contracts.bold,
            address(0),
            contracts.pybSeba,
            contracts.eUsdUsdcBeefyYieldVault
        );
    }

    function test_RevertWhen_SebaVaultIsZero()
        external
        whenAdminIsNotZero
        whenAutomatorIsNotZero
        whenSebaPoolIsNotZero
        whenRouterIsNotZero
        whenBoldIsNotZero
        whenSBOLDIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            contracts.sebaPool,
            contracts.ethToBoldRouter,
            contracts.bold,
            contracts.sBOLD,
            address(0),
            contracts.eUsdUsdcBeefyYieldVault
        );
    }

    function test_RevertWhen_YieldVaultIsZero()
        external
        whenAdminIsNotZero
        whenAutomatorIsNotZero
        whenSebaPoolIsNotZero
        whenRouterIsNotZero
        whenBoldIsNotZero
        whenSBOLDIsNotZero
        whenSebaVaultIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidAddress.selector));
        new YieldManager(
            users.admin,
            users.automator,
            contracts.sebaPool,
            contracts.ethToBoldRouter,
            contracts.bold,
            contracts.sBOLD,
            contracts.pybSeba,
            address(0)
        );
    }

    function test_WhenYieldVaultIsNotZero()
        external
        whenAdminIsNotZero
        whenAutomatorIsNotZero
        whenSebaPoolIsNotZero
        whenRouterIsNotZero
        whenBoldIsNotZero
        whenSBOLDIsNotZero
        whenSebaVaultIsNotZero
    {
        YieldManager localYieldManager = new YieldManager(
            users.admin,
            users.automator,
            contracts.sebaPool,
            contracts.ethToBoldRouter,
            contracts.bold,
            contracts.sBOLD,
            contracts.pybSeba,
            contracts.eUsdUsdcBeefyYieldVault
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
            address(localYieldManager.sebaPool()),
            address(contracts.sebaPool),
            "YieldManager: sebapool should be set correctly"
        );
        // it should set router
        assertEq(
            address(localYieldManager.router()),
            address(contracts.ethToBoldRouter),
            "YieldManager: router should be set correctly"
        );
        // it should set BOLD
        assertEq(
            address(localYieldManager.BOLD()),
            address(contracts.bold),
            "YieldManager: BOLD should be set correctly"
        );
        // it should set sBOLD
        assertEq(
            address(localYieldManager.sBOLD()),
            address(contracts.sBOLD),
            "YieldManager: sBOLD should be set correctly"
        );
        // it should set sebavault
        assertEq(
            address(localYieldManager.sebaVault()),
            address(contracts.pybSeba),
            "YieldManager: sebaVault should be set correctly"
        );
        // it should set yieldvault
        assertEq(
            address(localYieldManager.yieldVault()),
            address(contracts.eUsdUsdcBeefyYieldVault),
            "YieldManager: yieldVault should be set correctly"
        );
    }
}
