// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { EUSDUSDCBeefyYieldVault } from "src/EUSDUSDCBeefyYieldVault.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetYieldVaultTest is BaseTest {
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
        yieldManager.setYieldVault(address(0));
    }

    function test_WhenThePrincipalValueIsBiggerThan0() external whenTheAdmin {
        resetPrank(users.admin);
        vm.deal(address(contracts.yieldManager), 1 ether);

        yieldManager.depositPrincipalIntoYieldVault();

        assertEq(address(yieldManager).balance, 0);

        EUSDUSDCBeefyYieldVault localYieldVault = new EUSDUSDCBeefyYieldVault(
            users.admin,
            address(yieldManager),
            address(weth),
            address(usdc),
            address(swapRouter),
            address(quoter),
            address(curvePool),
            address(beefy),
            address(ethUsdFeed),
            address(usdcUsdFeed)
        );

        // it should emit PrincipalRetrieved
        // it should emit NewYieldVaultSet
        vm.expectEmit();
        emit IYieldManager.PrincipalRetrieved();
        emit IYieldManager.NewYieldVaultSet(address(localYieldVault));
        yieldManager.setYieldVault(address(localYieldVault));
        // it should retrieve the principal from the current vault
        assertGt(address(yieldManager).balance, 0);
        // it should set principalValue to 0
        assertEq(yieldManager.principalValue(), 0);
        // it should set the new yieldvault
        assertEq(address(yieldManager.yieldVault()), address(localYieldVault));
    }

    function test_WhenThePrincipalValueIs0() external whenTheAdmin {
        resetPrank(users.admin);

        EUSDUSDCBeefyYieldVault localYieldVault = new EUSDUSDCBeefyYieldVault(
            users.admin,
            address(yieldManager),
            address(weth),
            address(usdc),
            address(swapRouter),
            address(quoter),
            address(curvePool),
            address(beefy),
            address(ethUsdFeed),
            address(usdcUsdFeed)
        );

        // it should emit NewYieldVaultSet
        vm.expectEmit();
        emit IYieldManager.NewYieldVaultSet(address(localYieldVault));
        yieldManager.setYieldVault(address(localYieldVault));

        // it should set the new yieldvault
        assertEq(address(yieldManager.yieldVault()), address(localYieldVault));
    }
}
