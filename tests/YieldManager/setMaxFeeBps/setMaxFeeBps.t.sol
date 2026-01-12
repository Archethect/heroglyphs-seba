// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetMaxFeeBpsTest is BaseTest {
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
        yieldManager.setMaxFeeBPS(0);
    }

    function test_RevertWhen_TheMaxFeeExceeds10000(uint16 maxFee) external whenTheAdmin {
        resetPrank(users.admin);
        vm.assume(maxFee > 10000);
        vm.assume(maxFee < type(uint16).max);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.MaxFeeTooHigh.selector));
        yieldManager.setMaxFeeBPS(maxFee);
    }

    function test_WhenTheMaxFeeDoesNotExceed10000(uint16 maxFee) external whenTheAdmin {
        resetPrank(users.admin);
        vm.assume(maxFee <= 10000);
        uint16 previousMaxFee = yieldManager.MAX_FEE_BPS();

        // it should emit MaxFeeBpsSet
        vm.expectEmit();
        emit IYieldManager.MaxFeeBpsSet(previousMaxFee, maxFee);
        yieldManager.setMaxFeeBPS(maxFee);

        // it should set the new max fee
        assertEq(yieldManager.MAX_FEE_BPS(), maxFee);
    }
}
