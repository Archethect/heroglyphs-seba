// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IPerpYieldBearingAutoPxEth } from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetBoostPoolTest is BaseTest {
    function test_RevertWhen_TheCallerHasNoAdminRole(address caller) external {
        vm.assume(caller != users.admin);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                pybapxEth.ADMIN_ROLE()
            )
        );
        resetPrank(caller);
        pybapxEth.setBoostPool(caller);
    }

    function test_RevertWhen_TheNewBoostpoolAddressIsZero() external whenTheCallerHasTheAdminRole {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPerpYieldBearingAutoPxEth.InvalidAddress.selector));
        pybapxEth.setBoostPool(address(0));
    }

    function test_WhenTheNewBoostpoolAddressIsNotZero(address newBoostPool) external whenTheCallerHasTheAdminRole {
        assumeNotZeroAddress(newBoostPool);

        // it should emit BoostPoolChanged
        vm.expectEmit();
        emit IPerpYieldBearingAutoPxEth.BoostPoolChanged(newBoostPool);
        pybapxEth.setBoostPool(newBoostPool);

        // it should set the new boostpool address
        assertEq(pybapxEth.boostPool(), newBoostPool, "boostpool address should be equal to the new boostpool address");
    }
}
