// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RetrievePrincipalFromYieldVaultTest is BaseTest {
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
        yieldManager.retrievePrincipalFromYieldVault();
    }

    function test_RevertWhen_ThePrincipalValueIs0() external whenTheAdmin {
        resetPrank(users.admin);

        // it should revert
        vm.expectRevert(IYieldManager.NoPrincipalDeployed.selector);
        yieldManager.retrievePrincipalFromYieldVault();
    }

    function test_WhenThePrincipalValueIsNot0() external whenTheAdmin {
        resetPrank(users.admin);
        vm.deal(address(contracts.yieldManager), 1 ether);

        yieldManager.depositPrincipalIntoYieldVault();

        assertEq(address(yieldManager).balance, 0);

        // it should emit PrincipalRetrieved
        vm.expectEmit();
        emit IYieldManager.PrincipalRetrieved();
        yieldManager.retrievePrincipalFromYieldVault();

        // it should retrieve the principal from the yieldvault
        assertGt(address(yieldManager).balance, 0);
        // it should set principalValue to 0
        assertEq(yieldManager.principalValue(), 0);
    }
}
