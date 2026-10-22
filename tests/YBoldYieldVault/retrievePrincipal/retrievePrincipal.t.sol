// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";

contract YBoldRetrievePrincipalTest is YBoldYieldVaultTestBase {
    function test_RevertWhenCallerIsNotYieldManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                vault.YIELDMANAGER_ROLE()
            )
        );
        vault.retrievePrincipal(1);
    }

    function test_RevertWhenValueIsZeroOrNoPrincipalExists() external {
        vm.expectRevert(IYBoldYieldVault.CannotRetrieveZero.selector);
        manager.retrieve(address(vault), 0);

        vm.expectRevert(IYBoldYieldVault.NoPrincipal.selector);
        manager.retrieve(address(vault), 1);
    }

    function test_RevertWhenPartialWithdrawalCannotBeQuoted() external {
        uint256 depositedValue = _deposit(1 ether);
        stYBold.setPreviewWithdrawReturnsZero(true);

        vm.expectRevert(IYBoldYieldVault.NoPrincipal.selector);
        manager.retrieve(address(vault), depositedValue / 2);
    }

    function test_RetrievesPartialPrincipalAndThenTheRemainder() external {
        uint256 depositedValue = _deposit(1 ether);
        uint256 managerBefore = address(manager).balance;

        manager.retrieve(address(vault), depositedValue / 2);

        assertEq(vault.principalValue(), depositedValue - (depositedValue / 2));
        assertGt(address(manager).balance - managerBefore, 0.49 ether);
        assertLt(address(manager).balance - managerBefore, 0.51 ether);
        assertGt(vault.principalShares(), 0);

        manager.retrieve(address(vault), vault.principalValue());
        assertEq(vault.principalValue(), 0);
        assertEq(vault.principalShares(), 0);
        assertEq(stYBold.balanceOf(address(vault)), 0);
    }

    function test_FinalPrincipalRetrievalPreservesUnclaimedYield() external {
        uint256 depositedValue = _deposit(1 ether);
        _donateStYBoldYield(100e18);

        manager.retrieve(address(vault), depositedValue * 2);

        assertEq(vault.principalValue(), 0);
        assertGt(vault.principalShares(), 0);
        assertGt(vault.claimableYield(), 90e18);
        assertLt(address(manager).balance, 1.01 ether);

        uint256 principalPaid = address(manager).balance;
        manager.claim(address(vault));
        assertGt(address(manager).balance, principalPaid);
    }

    function test_FinalRetrievalRejectsInvalidYearnShareQuote() external {
        uint256 depositedValue = _deposit(1 ether);
        _donateStYBoldYield(100e18);
        stYBold.setPreviewWithdrawReturnsZero(true);

        vm.expectRevert(IYBoldYieldVault.NoPrincipal.selector);
        manager.retrieve(address(vault), depositedValue);
        assertEq(vault.principalValue(), depositedValue);
    }

    function test_UnderwaterWithdrawalsShareLossProRata() external {
        uint256 firstDeposit = _deposit(1 ether);
        uint256 secondDeposit = _deposit(1 ether);
        stYBold.simulateLoss(stYBold.totalAssets() / 2);

        uint256 initialShares = vault.principalShares();
        manager.retrieve(address(vault), firstDeposit);
        uint256 firstPaid = address(manager).balance;
        uint256 remainingShares = vault.principalShares();

        assertApproxEqAbs(remainingShares, initialShares / 2, 1);
        assertApproxEqAbs(firstPaid, 0.5 ether, 0.01 ether);

        manager.retrieve(address(vault), secondDeposit);
        uint256 secondPaid = address(manager).balance - firstPaid;

        assertApproxEqAbs(secondPaid, firstPaid, 0.01 ether);
        assertEq(vault.principalShares(), 0);
        assertEq(vault.principalValue(), 0);
    }

    function testFuzz_UnequalDepositsShareLossProRata(uint96 firstEth, uint96 secondEth, uint16 lossBps) external {
        firstEth = uint96(bound(firstEth, 0.2 ether, 5 ether));
        secondEth = uint96(bound(secondEth, 0.2 ether, 5 ether));
        lossBps = uint16(bound(lossBps, 1000, 8000));

        uint256 firstValue = _deposit(firstEth);
        uint256 secondValue = _deposit(secondEth);
        stYBold.simulateLoss((stYBold.totalAssets() * lossBps) / 10_000);

        manager.retrieve(address(vault), firstValue);
        uint256 firstPaid = address(manager).balance;
        manager.retrieve(address(vault), secondValue);
        uint256 secondPaid = address(manager).balance - firstPaid;

        assertApproxEqRel((firstPaid * secondValue) / firstValue, secondPaid, 0.01e18);
        assertEq(vault.principalValue(), 0);
        assertEq(vault.principalShares(), 0);
    }

    function test_RevertAtomicallyWhenEitherYearnVaultHasInsufficientLiquidity() external {
        uint256 depositedValue = _deposit(1 ether);
        uint256 sharesBefore = vault.principalShares();
        uint256 sharesToRedeem = stYBold.previewWithdraw(depositedValue / 2);
        stYBold.setRedeemLimit(0);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.InsufficientLiquidity.selector, address(stYBold), sharesToRedeem, 0)
        );
        manager.retrieve(address(vault), depositedValue / 2);
        assertEq(vault.principalShares(), sharesBefore);
        assertEq(vault.principalValue(), depositedValue);

        stYBold.setRedeemLimit(type(uint256).max);
        uint256 yBoldToRedeem = stYBold.previewRedeem(sharesToRedeem);
        yBold.setRedeemLimit(0);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.InsufficientLiquidity.selector, address(yBold), yBoldToRedeem, 0)
        );
        manager.retrieve(address(vault), depositedValue / 2);
        assertEq(vault.principalShares(), sharesBefore);
        assertEq(vault.principalValue(), depositedValue);
    }

    function test_EmergencyModeKeepsRetrievalOpenAndUsesEmergencyMaxLoss() external {
        uint256 depositedValue = _deposit(1 ether);
        vm.startPrank(admin);
        vault.pause();
        vault.setEmergencyMode(true);
        vm.stopPrank();

        manager.retrieve(address(vault), depositedValue);

        assertEq(vault.principalValue(), 0);
        assertEq(stYBold.lastMaxLoss(), 100);
        assertEq(yBold.lastMaxLoss(), 100);
        assertGt(address(manager).balance, 0.99 ether);
    }

    function testFuzz_RepeatedPartialRetrievalConservesBookValue(uint8 partsSeed) external {
        uint256 parts = bound(partsSeed, 2, 20);
        uint256 depositedValue = _deposit(10 ether);
        uint256 slice = depositedValue / parts;

        for (uint256 i; i < parts - 1; ++i) {
            manager.retrieve(address(vault), slice);
        }
        manager.retrieve(address(vault), vault.principalValue());

        assertEq(vault.principalValue(), 0);
        assertEq(vault.principalShares(), 0);
        assertGt(address(manager).balance, 9.9 ether);
    }
}
