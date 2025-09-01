// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IPYBSeba } from "src/interfaces/IPYBSeba.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetSebaPoolTest is BaseTest {
    function test_RevertWhen_TheCallerHasNoAdminRole(address caller) external {
        vm.assume(caller != users.admin);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                pybSeba.ADMIN_ROLE()
            )
        );
        resetPrank(caller);
        pybSeba.setSebaPool(caller);
    }

    function test_RevertWhen_TheNewSebapoolAddressIsZero() external whenTheCallerHasTheAdminRole {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPYBSeba.InvalidAddress.selector));
        pybSeba.setSebaPool(address(0));
    }

    function test_WhenTheNewSebapoolAddressIsNotZero(address newSebaPool) external whenTheCallerHasTheAdminRole {
        assumeNotZeroAddress(newSebaPool);

        // it should emit SebaPoolChanged
        vm.expectEmit();
        emit IPYBSeba.SebaPoolChanged(newSebaPool);
        pybSeba.setSebaPool(newSebaPool);

        // it should set the new sebapool address
        assertEq(pybSeba.sebaPool(), newSebaPool, "sebapool address should be equal to the new sebapool address");
    }
}
