// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetRouterSlippageBpsTest is BaseTest {
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
        yieldManager.setRouterSlippageBps(0);
    }

    function test_RevertWhen_TheSlippageExceeds10000(uint16 slippage) external whenTheAdmin {
        resetPrank(users.admin);
        vm.assume(slippage > 10000);
        vm.assume(slippage < type(uint16).max);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.SlippageTooHigh.selector));
        yieldManager.setRouterSlippageBps(slippage);
    }

    function test_WhenTheSlippageDoesNotExceed10000(uint16 slippage) external whenTheAdmin {
        resetPrank(users.admin);
        vm.assume(slippage <= 10000);
        uint16 previousSlippage = yieldManager.ROUTER_SLIPPAGE_BPS();

        // it should emit RouterSlippageBpsSet
        vm.expectEmit();
        emit IYieldManager.RouterSlippageBpsSet(previousSlippage, slippage);
        yieldManager.setRouterSlippageBps(slippage);

        // it should set the new router slippage
        assertEq(yieldManager.ROUTER_SLIPPAGE_BPS(), slippage);
    }
}
