// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";

contract YBoldRecoveryTest is YBoldYieldVaultTestBase {
    function test_RecoverySnapshotsOnlyOutstandingPrincipalAfterNormalWithdrawal() external {
        uint256 withdrawnValue = _deposit(1 ether);
        uint256 remainingValue = _deposit(2 ether);

        manager.retrieve(address(vault), withdrawnValue);
        uint256 sharesBeforeRecovery = vault.principalShares();
        assertEq(vault.principalValue(), remainingValue);

        vm.prank(recoveryTreasury);
        vault.initiateRecovery();

        IYBoldYieldVault.RecoveryAccounting memory accounting = vault.recoveryAccounting();
        assertEq(accounting.principalSnapshot, remainingValue);
        assertEq(accounting.sharesTransferred, sharesBeforeRecovery);
        assertEq(stYBold.balanceOf(recoveryTreasury), sharesBeforeRecovery);
    }

    function test_TransfersExactlyReconciledSharesAndFreezesEveryNormalExitDependency() external {
        uint256 depositedValue = _deposit(1 ether);
        uint256 depositedShares = vault.principalShares();
        stYBold.setRedeemLimit(0);
        yBold.setRedeemLimit(0);
        ethUsdFeed.setRound(1, 2000e8, block.timestamp - 2 hours, 1);
        curve.setOraclePrice(2e18);

        vm.expectEmit(true, false, false, true, address(vault));
        emit IYBoldYieldVault.RecoveryInitiated(recoveryTreasury, depositedValue, depositedShares);
        vm.prank(recoveryTreasury);
        vault.initiateRecovery();

        assertTrue(vault.paused());
        assertTrue(vault.emergencyMode());
        assertEq(uint256(vault.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.SharesTransferred));
        IYBoldYieldVault.RecoveryAccounting memory accounting = vault.recoveryAccounting();
        assertEq(accounting.principalSnapshot, depositedValue);
        assertEq(accounting.sharesTransferred, depositedShares);
        assertEq(vault.principalValue(), depositedValue);
        assertEq(vault.principalShares(), 0);
        assertEq(stYBold.balanceOf(address(vault)), 0);
        assertEq(stYBold.balanceOf(recoveryTreasury), depositedShares);

        vm.deal(address(this), 1 ether);
        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        manager.deposit{ value: 1 ether }(address(vault));
        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        manager.claim(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidRecoveryState.selector,
                IYBoldYieldVault.RecoveryState.SharesTransferred
            )
        );
        manager.retrieve(address(vault), depositedValue);
    }

    function test_RevertWhenRecoveryCallerIsUnauthorizedOrStateIsWrong() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                vault.RECOVERY_ROLE()
            )
        );
        vault.initiateRecovery();

        vm.prank(recoveryTreasury);
        vm.expectRevert(IYBoldYieldVault.NoPrincipal.selector);
        vault.initiateRecovery();

        vm.deal(recoveryTreasury, 1 ether);
        vm.prank(recoveryTreasury);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidRecoveryState.selector,
                IYBoldYieldVault.RecoveryState.Normal
            )
        );
        vault.fundRecovery{ value: 1 ether }();
    }

    function test_RevertWhenShareAccountingDoesNotMatchCustody() external {
        _deposit(1 ether);
        _donateStYBoldYield(1e18);
        bold.mint(address(this), 1e18);
        bold.approve(address(yBold), 1e18);
        uint256 yBoldShares = yBold.deposit(1e18, address(this));
        IERC20(address(yBold)).approve(address(stYBold), yBoldShares);
        stYBold.deposit(yBoldShares, address(vault));

        uint256 tracked = vault.principalShares();
        uint256 actual = stYBold.balanceOf(address(vault));
        vm.prank(recoveryTreasury);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.ShareAccountingMismatch.selector, tracked, actual));
        vault.initiateRecovery();
    }

    function test_FundingAndActivationRequireTreasuryAuthorityAndSufficientEth() external {
        _deposit(1 ether);
        vm.prank(recoveryTreasury);
        vault.initiateRecovery();

        vm.deal(recoveryTreasury, 2 ether);
        vm.prank(recoveryTreasury);
        vm.expectRevert(IYBoldYieldVault.ZeroOutput.selector);
        vault.fundRecovery{ value: 0 }();

        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.UnauthorizedRecoveryFunder.selector, stranger));
        vault.fundRecovery{ value: 1 ether }();

        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 1 ether }();
        assertEq(vault.recoveryAccounting().ethFunded, 1 ether);

        vm.prank(recoveryTreasury);
        vm.expectRevert(IYBoldYieldVault.ZeroOutput.selector);
        vault.activateRecoverySettlement(0);

        vm.prank(recoveryTreasury);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.RecoveryUnderfunded.selector, 1 ether + 1, 1 ether));
        vault.activateRecoverySettlement(1 ether + 1);
    }

    function test_RevertWhenRecoveryRateRoundsToZero() external {
        _deposit(1 ether);
        vm.prank(recoveryTreasury);
        vault.initiateRecovery();
        vm.deal(recoveryTreasury, 1);
        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 1 }();

        vm.prank(recoveryTreasury);
        vm.expectRevert(IYBoldYieldVault.RecoveryRateTooLow.selector);
        vault.activateRecoverySettlement(1);
    }

    function test_RevertWithoutAccountingChangesIfSettlementEthBecomesUnavailable() external {
        uint256 depositedValue = _deposit(1 ether);
        vm.prank(recoveryTreasury);
        vault.initiateRecovery();
        vm.deal(recoveryTreasury, 1 ether);
        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 1 ether }();
        vm.prank(recoveryTreasury);
        vault.activateRecoverySettlement(1 ether);

        vm.deal(address(vault), 0);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.RecoveryUnderfunded.selector, 1 ether, 0));
        manager.retrieve(address(vault), depositedValue);

        assertEq(vault.principalValue(), depositedValue);
        assertEq(vault.recoveryAccounting().principalSettled, 0);
    }

    function test_SettlesMultipleClaimsAtOneFullRecoveryRateAndSweepsOnlySurplus() external {
        uint256 firstValue = _deposit(1 ether);
        uint256 secondValue = _deposit(2 ether);
        uint256 totalValue = firstValue + secondValue;

        vm.prank(recoveryTreasury);
        vault.initiateRecovery();
        vm.deal(recoveryTreasury, 3.1 ether);
        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 3.1 ether }();
        vm.prank(recoveryTreasury);
        vault.activateRecoverySettlement(3 ether);

        assertEq(vault.recoveryAccounting().payoutRateWad, (3 ether * 1e18) / totalValue);
        uint256 managerBefore = address(manager).balance;
        manager.retrieve(address(vault), secondValue);
        uint256 secondPaid = address(manager).balance - managerBefore;
        managerBefore = address(manager).balance;
        manager.retrieve(address(vault), firstValue);
        uint256 firstPaid = address(manager).balance - managerBefore;

        assertApproxEqAbs(firstPaid, 1 ether, 1);
        assertApproxEqAbs(secondPaid, 2 ether, 1);
        assertEq(secondPaid, firstPaid * 2);
        assertEq(vault.principalValue(), 0);
        IYBoldYieldVault.RecoveryAccounting memory accounting = vault.recoveryAccounting();
        assertEq(accounting.principalSettled, totalValue);
        assertEq(accounting.ethPaid, firstPaid + secondPaid);
        assertEq(uint256(vault.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.Settled));

        uint256 treasuryBefore = recoveryTreasury.balance;
        vm.prank(recoveryTreasury);
        vault.sweepRecoveryExcess();
        assertEq(recoveryTreasury.balance - treasuryBefore, 3.1 ether - firstPaid - secondPaid);

        vm.prank(recoveryTreasury);
        vm.expectRevert(IYBoldYieldVault.ZeroOutput.selector);
        vault.sweepRecoveryExcess();
    }

    function test_SettlesPartialLossProRataIndependentOfClaimSize() external {
        uint256 firstValue = _deposit(1 ether);
        uint256 secondValue = _deposit(3 ether);

        vm.prank(recoveryTreasury);
        vault.initiateRecovery();
        vm.deal(recoveryTreasury, 2 ether);
        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 2 ether }();
        vm.prank(recoveryTreasury);
        vault.activateRecoverySettlement(2 ether);

        manager.retrieve(address(vault), firstValue);
        uint256 firstPaid = address(manager).balance;
        manager.retrieve(address(vault), secondValue);
        uint256 secondPaid = address(manager).balance - firstPaid;

        assertApproxEqAbs(firstPaid, 0.5 ether, 1);
        assertApproxEqAbs(secondPaid, 1.5 ether, 1);
        assertApproxEqAbs(secondPaid, firstPaid * 3, 2);
    }

    function test_LargePositionsRemainProRataWhenLargerClaimSettlesFirst() external {
        uint256 smallerValue = _deposit(1_000 ether);
        uint256 largerValue = _deposit(3_000 ether);

        vm.prank(recoveryTreasury);
        vault.initiateRecovery();
        vm.deal(recoveryTreasury, 2_000 ether);
        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 2_000 ether }();
        vm.prank(recoveryTreasury);
        vault.activateRecoverySettlement(2_000 ether);

        uint256 before = address(manager).balance;
        manager.retrieve(address(vault), largerValue);
        uint256 largerPaid = address(manager).balance - before;
        before = address(manager).balance;
        manager.retrieve(address(vault), smallerValue);
        uint256 smallerPaid = address(manager).balance - before;

        assertApproxEqAbs(largerPaid, 1_500 ether, 1);
        assertApproxEqAbs(smallerPaid, 500 ether, 1);
        assertApproxEqAbs(largerPaid, smallerPaid * 3, 2);
    }

    function test_OverlargeFinalClaimCannotExceedSnapshotAndCannotBeRepeated() external {
        uint256 depositedValue = _deposit(1 ether);
        vm.prank(recoveryTreasury);
        vault.initiateRecovery();
        vm.deal(recoveryTreasury, 1 ether);
        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 1 ether }();
        vm.prank(recoveryTreasury);
        vault.activateRecoverySettlement(1 ether);

        manager.retrieve(address(vault), depositedValue * 2);
        assertEq(address(manager).balance, 1 ether);
        assertEq(vault.recoveryAccounting().principalSettled, depositedValue);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidRecoveryState.selector,
                IYBoldYieldVault.RecoveryState.Settled
            )
        );
        manager.retrieve(address(vault), depositedValue);
    }

    function test_RevertWhenRecoveryTransitionsAreRepeatedOrCalledByWrongRole() external {
        uint256 value = _deposit(1 ether);
        vm.prank(recoveryTreasury);
        vault.initiateRecovery();

        vm.prank(recoveryTreasury);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidRecoveryState.selector,
                IYBoldYieldVault.RecoveryState.SharesTransferred
            )
        );
        vault.initiateRecovery();

        vm.deal(recoveryTreasury, 1 ether);
        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 1 ether }();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                vault.RECOVERY_ROLE()
            )
        );
        vault.activateRecoverySettlement(1 ether);

        vm.prank(recoveryTreasury);
        vault.activateRecoverySettlement(1 ether);
        vm.prank(recoveryTreasury);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidRecoveryState.selector,
                IYBoldYieldVault.RecoveryState.SettlementActive
            )
        );
        vault.activateRecoverySettlement(1 ether);

        vm.prank(recoveryTreasury);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidRecoveryState.selector,
                IYBoldYieldVault.RecoveryState.SettlementActive
            )
        );
        vault.sweepRecoveryExcess();

        manager.retrieve(address(vault), value);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                vault.RECOVERY_ROLE()
            )
        );
        vault.sweepRecoveryExcess();
    }
}
