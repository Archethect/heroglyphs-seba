// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { ISebaPool } from "src/interfaces/ISebaPool.sol";
import { SebaPool } from "src/SebaPool.sol";

contract ConstructorTest is BaseTest {
    function test_RevertWhen_AdminIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.InvalidAddress.selector));
        new SebaPool(address(0), users.automator);
    }

    function test_RevertWhen_AutomatorIsZero() external whenAdminIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.InvalidAddress.selector));
        new SebaPool(users.admin, address(0));
    }

    function test_WhenAutomatorIsNotZero(address admin, address automator) external whenAdminIsNotZero {
        assumeNotZeroAddress(admin);
        assumeNotZeroAddress(automator);

        SebaPool localBoostPool = new SebaPool(admin, automator);

        // it should give admin the admin role
        assertTrue(
            localBoostPool.hasRole(keccak256("ADMIN_ROLE"), admin),
            "SebaPool: admin should have the admin role"
        );
        assertEq(
            localBoostPool.getRoleAdmin(keccak256("ADMIN_ROLE")),
            keccak256("ADMIN_ROLE"),
            "SebaPool: admin role should be admin"
        );
        // it should give automator the automator role
        assertTrue(
            localBoostPool.hasRole(keccak256("AUTOMATOR_ROLE"), automator),
            "SebaPool: automator should have the automator role"
        );
        assertEq(
            localBoostPool.getRoleAdmin(keccak256("AUTOMATOR_ROLE")),
            keccak256("ADMIN_ROLE"),
            "SebaPool: automator role should be admin"
        );
    }
}
