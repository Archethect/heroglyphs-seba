// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IBoostPool } from "src/interfaces/IBoostPool.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetPerpYieldBearingAutoPxEth is BaseTest {
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
        boostPool.setPerpYieldBearingAutoPxEth(address(0));
    }

    function test_RevertWhen_ThePybapxETHAddressIsZero() external whenTheAdminRole {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.InvalidAddress.selector));
        boostPool.setPerpYieldBearingAutoPxEth(address(0));
    }

    function test_WhenThePybapxETHAddressIsNotZero(address newPybapxETH) external whenTheAdminRole {
        assumeNotZeroAddress(newPybapxETH);

        // it should emit PerpYieldBearingAutoPxEthSet
        vm.expectEmit();
        emit IBoostPool.PerpYieldBearingAutoPxEthSet(newPybapxETH);
        boostPool.setPerpYieldBearingAutoPxEth(newPybapxETH);

        // it should set the new pybapxETH address
        assertEq(address(boostPool.pybapxETH()), newPybapxETH, "pybapxETH should be set correctly");
    }
}
