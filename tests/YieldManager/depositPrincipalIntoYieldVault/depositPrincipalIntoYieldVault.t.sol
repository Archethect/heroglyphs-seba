// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DepositPrincipalIntoYieldVaultTest is BaseTest {
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
        yieldManager.depositPrincipalIntoYieldVault();
    }

    function test_WhenTheAdmin() external {
        resetPrank(users.admin);
        vm.deal(address(contracts.yieldManager), 1 ether);

        // it should emit PrincipalDeposited
        vm.expectEmit();
        emit IYieldManager.PrincipalDeposited(1 ether);
        yieldManager.depositPrincipalIntoYieldVault();
        // it should deposit the principal into the yieldvault
        assertEq(address(yieldManager).balance, 0);
        assertGt(yieldManager.principalValue(), 0);
    }
}
