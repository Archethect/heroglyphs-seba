// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RetrievePrincipalTest is BaseTest {
    function test_RevertWhen_NotTheYieldManager(address invocator) external {
        vm.assume(invocator != users.yieldManager);
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                invocator,
                eUsdUsdcBeefyYieldVault.YIELDMANAGER_ROLE()
            )
        );
        resetPrank(invocator);
        eUsdUsdcBeefyYieldVault.retrievePrincipal(0);
    }

    function test_RevertWhen_TheDepositValueIsZero() external whenTheYieldManager {
        resetPrank(users.yieldManager);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.CannotRetrieveZero.selector));
        eUsdUsdcBeefyYieldVault.retrievePrincipal(0);
    }

    function test_RevertWhen_ThereAreNoSharesToWithdraw() external whenTheYieldManager whenTheDepositValueIsNotZero {
        resetPrank(users.yieldManager);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.NoSharesToWithdraw.selector));
        eUsdUsdcBeefyYieldVault.retrievePrincipal(1);
    }

    function test_WhenTheSharesToWithdrawAreBiggerThanThePrincipalShares()
        external
        whenTheYieldManager
        whenTheDepositValueIsNotZero
        whenThereAreSharesToWithdraw
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);
        uint256 depositValue = eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        //uint256 principalShares = eUsdUsdcBeefyYieldVault.principalShares();
        uint256 balanceBefore = users.yieldManager.balance;

        // it should emit PrincipalRetrieved
        // vm.expectEmit();
        // emit IEUSDUSDCBeefyYieldVault.PrincipalRetrieved(principalShares, 998594580790510476);
        eUsdUsdcBeefyYieldVault.retrievePrincipal(depositValue * 2);

        // it should set the sharesToWithdraw equal to the principal shares
        // it should set the new principalShares
        assertEq(eUsdUsdcBeefyYieldVault.principalShares(), 0);
        // it should set the new principalValue
        assertEq(eUsdUsdcBeefyYieldVault.principalValue(), 0);
        // it should convert the to be withdrawn shares into eth and send it to the caller
        uint256 balanceAfter = users.yieldManager.balance;
        assertGt(balanceAfter, balanceBefore);
    }

    function test_WhenTheSharesToWithdrawAreNotBiggerThanThePrincipalShares()
        external
        whenTheYieldManager
        whenTheDepositValueIsNotZero
        whenThereAreSharesToWithdraw
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);
        uint256 depositValue = eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 principalShares = eUsdUsdcBeefyYieldVault.principalShares();
        uint256 principalValue = eUsdUsdcBeefyYieldVault.principalValue();
        uint256 balanceBefore = users.yieldManager.balance;
        uint256 pps = beefy.getPricePerFullShare();
        uint256 expectedSharesToWithdraw = ((depositValue / 2) * 1e18) / pps;

        uint256 expectedPrincipalShares = principalShares - expectedSharesToWithdraw;
        uint256 expectedPrincipalValue = principalValue - (principalValue * expectedSharesToWithdraw) / principalShares;

        // it should emit PrincipalRetrieved
        // vm.expectEmit();
        // emit IEUSDUSDCBeefyYieldVault.PrincipalRetrieved(principalShares, 499305686253512692);
        eUsdUsdcBeefyYieldVault.retrievePrincipal(depositValue / 2);

        // it should set the new principalShares
        assertEq(eUsdUsdcBeefyYieldVault.principalShares(), expectedPrincipalShares);
        // it should set the new principalValue
        assertEq(eUsdUsdcBeefyYieldVault.principalValue(), expectedPrincipalValue);
        // it should convert the to be withdrawn shares into eth and send it to the caller
        uint256 balanceAfter = users.yieldManager.balance;
        assertGt(balanceAfter, balanceBefore);
    }
}
