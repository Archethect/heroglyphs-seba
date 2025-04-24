// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IPerpYieldBearingAutoPxEth } from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";
import { PerpYieldBearingAutoPxEth } from "src/PerpYieldBearingAutoPxEth.sol";

contract ConstructorTest is BaseTest {
    function test_RevertWhen_AdminIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPerpYieldBearingAutoPxEth.InvalidAddress.selector));
        new PerpYieldBearingAutoPxEth(address(0), apxETH);
    }

    function test_WhenAdminIsNotZero() external {
        PerpYieldBearingAutoPxEth localPerpYieldBearingAutoPxEth = new PerpYieldBearingAutoPxEth(users.admin, apxETH);

        // it should grant admin the admin role
        assertTrue(
            localPerpYieldBearingAutoPxEth.hasRole(localPerpYieldBearingAutoPxEth.ADMIN_ROLE(), users.admin),
            "PerpYieldBearingAutoPxEth: admin should have the admin role"
        );
        assertEq(
            localPerpYieldBearingAutoPxEth.getRoleAdmin(localPerpYieldBearingAutoPxEth.ADMIN_ROLE()),
            localPerpYieldBearingAutoPxEth.ADMIN_ROLE(),
            "PerpYieldBearingAutoPxEth: admin role should be admin"
        );
        // it should set the asset
        assertEq(
            address(localPerpYieldBearingAutoPxEth.asset()),
            contracts.apxETH,
            "PerpYieldBearingAutoPxEth: asset should be set correctly"
        );
        // it should set the name of the ERC20
        assertEq(
            localPerpYieldBearingAutoPxEth.name(),
            "Perpetual Yield Bearing Autocompounding Pirex Ether",
            "PerpYieldBearingAutoPxEth: name should be set correctly"
        );
        // it should set the symbol of the ERC20
        assertEq(
            localPerpYieldBearingAutoPxEth.symbol(),
            "pybapxETH",
            "PerpYieldBearingAutoPxEth: symbol should be set correctly"
        );
    }
}
