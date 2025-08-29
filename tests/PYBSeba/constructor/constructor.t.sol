// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IPYBSeba } from "src/interfaces/IPYBSeba.sol";
import { PYBSeba } from "src/PYBSeba.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

contract ConstructorTest is BaseTest {
    function test_RevertWhen_AdminIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPYBSeba.InvalidAddress.selector));
        new PYBSeba(address(0), ERC20(address(sBOLD)));
    }

    function test_WhenAdminIsNotZero() external {
        PYBSeba localPYBSeba = new PYBSeba(users.admin, ERC20(address(sBOLD)));

        // it should grant admin the admin role
        assertTrue(
            localPYBSeba.hasRole(localPYBSeba.ADMIN_ROLE(), users.admin),
            "PYBSeba: admin should have the admin role"
        );
        assertEq(
            localPYBSeba.getRoleAdmin(localPYBSeba.ADMIN_ROLE()),
            localPYBSeba.ADMIN_ROLE(),
            "PYBSeba: admin role should be admin"
        );
        // it should set the asset
        assertEq(
            address(localPYBSeba.asset()),
            contracts.sBOLD,
            "PYBSeba: asset should be set correctly"
        );
        // it should set the name of the ERC20
        assertEq(
            localPYBSeba.name(),
            "Perpetual Yield Bearing Seba",
            "PYBSeba: name should be set correctly"
        );
        // it should set the symbol of the ERC20
        assertEq(
            localPYBSeba.symbol(),
            "pybSeba",
            "PYBSeba: symbol should be set correctly"
        );
    }
}
