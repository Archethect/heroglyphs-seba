// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IBoostPool } from "src/interfaces/IBoostPool.sol";
import { BoostPool } from "src/BoostPool.sol";

contract ConstructorTest is BaseTest {
    function test_RevertWhen_AdminIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.InvalidAddress.selector));
        new BoostPool(address(0), users.automator, contracts.poap);
    }

    function test_RevertWhen_AutomatorIsZero() external whenAdminIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.InvalidAddress.selector));
        new BoostPool(users.admin, address(0), contracts.poap);
    }

    function test_RevertWhen_PoapIsZero() external whenAdminIsNotZero whenAutomatorIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.InvalidAddress.selector));
        new BoostPool(users.admin, users.automator, address(0));
    }

    function test_WhenPoapIsNotZero(
        address admin,
        address automator,
        address poap
    ) external whenAdminIsNotZero whenAutomatorIsNotZero {
        assumeNotZeroAddress(admin);
        assumeNotZeroAddress(automator);
        assumeNotZeroAddress(poap);

        BoostPool localBoostPool = new BoostPool(admin, automator, poap);

        // it should set the correct poap
        assertEq(address(localBoostPool.poap()), poap, "BoostPool: invalid POAP address");
        // it should give admin the admin role
        assertTrue(
            localBoostPool.hasRole(keccak256("ADMIN_ROLE"), admin),
            "BoostPool: admin should have the admin role"
        );
        assertEq(
            localBoostPool.getRoleAdmin(keccak256("ADMIN_ROLE")),
            keccak256("ADMIN_ROLE"),
            "BoostPool: admin role should be admin"
        );
        // it should give automator the automator role
        assertTrue(
            localBoostPool.hasRole(keccak256("AUTOMATOR_ROLE"), automator),
            "BoostPool: automator should have the automator role"
        );
        assertEq(
            localBoostPool.getRoleAdmin(keccak256("AUTOMATOR_ROLE")),
            keccak256("ADMIN_ROLE"),
            "BoostPool: automator role should be admin"
        );
    }
}
