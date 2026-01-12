// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetRouterValiditySecsTest is BaseTest {
    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertWhen_NotTheAdmin(address caller) external {
        vm.assume(caller != users.admin);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                yieldManager.ADMIN_ROLE()
            )
        );
        resetPrank(caller);
        yieldManager.setRouterValiditySecs(0);
    }

    function test_RevertWhen_TheValidityIs0() external whenTheAdmin {
        resetPrank(users.admin);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidValidity.selector));
        yieldManager.setRouterValiditySecs(0);
    }

    function test_WhenTheValidityIsNot0(uint32 validity) external whenTheAdmin {
        resetPrank(users.admin);
        vm.assume(validity > 0);
        vm.assume(validity <= type(uint32).max);
        uint32 previousValidity = yieldManager.ROUTER_VALIDITY_SECS();

        // it should emit RouterValiditySecsSet
        vm.expectEmit();
        emit IYieldManager.RouterValiditySecsSet(previousValidity, validity);
        yieldManager.setRouterValiditySecs(validity);

        // it should set the new router validity seconds
        assertEq(yieldManager.ROUTER_VALIDITY_SECS(), validity);
    }
}
