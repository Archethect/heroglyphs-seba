// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IBoostPool } from "src/interfaces/IBoostPool.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetYieldManagerTest is BaseTest {
    function test_RevertWhen_NotTheAdminRole(address caller) external {
        vm.assume(caller != users.admin);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                boostPool.ADMIN_ROLE()
            )
        );
        resetPrank(caller);
        boostPool.setYieldManager(address(0));
    }

    function test_RevertWhen_TheYieldManagerAddressIsZero() external whenTheAdminRole {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.InvalidAddress.selector));
        boostPool.setYieldManager(address(0));
    }

    function test_WhenTheYieldManagerAddressIsNotZero(address newYieldManager) external whenTheAdminRole {
        assumeNotZeroAddress(newYieldManager);

        // it should emit YieldManagerSet
        vm.expectEmit();
        emit IBoostPool.YieldManagerSet(newYieldManager);
        boostPool.setYieldManager(newYieldManager);

        // it should set the new yield manager address
        assertEq(address(boostPool.yieldManager()), newYieldManager, "yield manager should be set correctly");
    }
}
