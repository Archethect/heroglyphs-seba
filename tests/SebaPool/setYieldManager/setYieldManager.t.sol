// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import {ISebaPool} from "src/interfaces/ISebaPool.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetYieldManagerTest is BaseTest {
    function test_RevertWhen_NotTheAdminRole(address caller) external {
        vm.assume(caller != users.admin);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                sebaPool.ADMIN_ROLE()
            )
        );
        resetPrank(caller);
        sebaPool.setYieldManager(address(0));
    }

    function test_RevertWhen_TheYieldManagerAddressIsZero() external whenTheAdminRole {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.InvalidAddress.selector));
        sebaPool.setYieldManager(address(0));
    }

    function test_WhenTheYieldManagerAddressIsNotZero(address newYieldManager) external whenTheAdminRole {
        assumeNotZeroAddress(newYieldManager);

        // it should emit YieldManagerSet
        vm.expectEmit();
        emit ISebaPool.YieldManagerSet(newYieldManager);
        sebaPool.setYieldManager(newYieldManager);

        // it should set the new yield manager address
        assertEq(address(sebaPool.yieldManager()), newYieldManager, "yield manager should be set correctly");
    }
}
