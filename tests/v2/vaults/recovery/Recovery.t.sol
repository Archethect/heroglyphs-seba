// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { VaultBaseTest } from "../VaultBase.t.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";

contract VaultRecoveryTest is VaultBaseTest {
    function test_RefundableRepairUsedForPrincipalCannotBeRefundedAgain() external {
        (uint256 id, ) = _deposit(alice, 100 ether);
        _recover();
        _fund(0, 100 ether, false);
        token.mint(address(safe), 100 ether);
        vm.startPrank(address(safe));
        token.approve(address(vault), 100 ether);
        vault.fundRefundableRecovery(0, 100 ether);
        vm.stopPrank();
        balances.setRate(1, 2);
        _activate(150 ether, 0, false);
        _unlock();
        vm.prank(alice);
        assertEq(vault.withdraw(id, 150 ether, block.timestamp), 150 ether);
        vm.prank(address(safe));
        vault.finalizeRecovery();
        assertEq(token.balanceOf(address(safe)), 50 ether);
        assertEq(token.balanceOf(alice), 150 ether);
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(coordinator.received(0), 0);
    }
    function test_PublicRecoveryRepairDonationIsNeverRefundedToTreasuryAsItsOwnOverfunding() external {
        (uint256 id, ) = _deposit(alice, 100 ether);
        _recover();
        _fund(0, 100 ether, false);
        token.mint(bob, 20 ether);
        vm.startPrank(bob);
        token.approve(address(vault), 20 ether);
        vault.repairRecovery(0, 20 ether);
        vm.stopPrank();
        balances.setRate(2, 1);
        _activate(50 ether, 0, false);
        _unlock();
        vm.prank(alice);
        vault.withdraw(id, 50 ether, block.timestamp);
        vm.prank(address(safe));
        vault.finalizeRecovery();
        assertEq(token.balanceOf(address(safe)), 0, "a public repair donation became treasury's refund");
        assertEq(coordinator.received(0), 70 ether);
    }
    function test_GivenUnavailableValuation_WhenManualBudgetHasNoBasisOrExceedsItsOwnBacking_ItRejects() external {
        _deposit(alice, 10 ether);
        _recover();
        _fund(0, 10 ether, false);
        _fund(1, 1 ether, true);
        balances.setFail(true);
        _expect(IV2SupporterVault.InvalidBudget.selector);
        _activate(10 ether, 1 ether, true);
        _expect(IV2SupporterVault.InvalidBudget.selector);
        _activate(11 ether, 0, true);
    }
    function test_GivenOpenPositions_WhenRecoveryBegins_ItExportsExactAccountedTokensAndPreservesClaims() external {
        (uint256 id, ) = _deposit(alice, 100 ether);
        _protocol(50 ether);
        token.mint(address(vault), 7 ether);
        uint256 unlock = vault.position(id).unlockAt;
        _recover();
        assertEq(token.balanceOf(address(safe)), 150 ether);
        assertEq(token.balanceOf(address(vault)), 7 ether);
        assertEq(vault.recoverySurplus(), 7 ether);
        assertEq(vault.recoveryBucket(0).exportedTokens, 100 ether);
        assertEq(vault.recoveryBucket(1).exportedTokens, 50 ether);
        assertEq(vault.recoveryBucket(0).snapshot.enteredBasis, 100 ether);
        assertEq(vault.bucket(0).basis, 100 ether);
        assertEq(vault.bucket(0).tokens, 0);
        assertEq(vault.position(id).unlockAt, unlock);
        assertFalse(vault.position(id).closed);
        assertEq(vault.initialManifest(), evidence);
        assertFalse(vault.entriesEnabled());
        assertFalse(vault.harvestEnabled());
        assertEq(uint256(vault.recoveryState()), 1);
        assertEq(vault.recoveryPositionBoundary(), 2);
        assertNotEq(vault.recoveryInstance(), bytes32(0));
        _expect(IV2SupporterVault.WrongState.selector);
        vm.prank(address(safe));
        vault.beginRecovery(evidence);
        _expect(IV2SupporterVault.WrongState.selector);
        vault.deposit(1, 0, block.timestamp);
        _expect(IV2SupporterVault.WrongState.selector);
        vault.repair(0, 1);
        _expect(IV2SupporterVault.WrongState.selector);
        vm.prank(address(safe));
        vault.recognizeSurplus(0, 1, true);
        _expect(IV2SupporterVault.WrongState.selector);
        vm.prank(operator);
        vault.collectYield(0, 1);
        _unlock();
        _expect(IV2SupporterVault.WrongState.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        _expect(IV2SupporterVault.WrongState.selector);
        vault.previewWithdraw(id);
    }
    function test_GivenUnavailableValuation_WhenExporting_ItDoesNotRequireAnyPriceOrRedemptionCall() external {
        _deposit(alice, 10 ether);
        balances.setFail(true);
        _recover();
        assertEq(token.balanceOf(address(safe)), 10 ether);
        assertEq(vault.recoveryBucket(0).snapshot.basis, 10 ether);
    }
    function test_GivenPhysicalShortage_WhenRecovering_ItAttributesByPreShortageTokensWithoutProtocolPriority()
        external
    {
        _deposit(alice, 10);
        _protocol(20);
        token.burn(address(vault), 8);
        _recover();
        assertEq(vault.recoveryBucket(0).exportedTokens, 7);
        assertEq(vault.recoveryBucket(1).exportedTokens, 15);
        assertEq(vault.recoverySurplus(), 0);
        assertEq(token.balanceOf(address(safe)), 22);
        _fund(0, 7, false);
        _fund(1, 15, false);
        _activate(7, 15, false);
        _unlock();
        vm.prank(alice);
        assertEq(vault.withdraw(1, 7, block.timestamp), 7);
        vm.prank(address(safe));
        assertEq(vault.withdrawProtocol(20, 15, block.timestamp), 15);
    }
    function test_GivenBothBucketsFunded_WhenFixedSettlementActivates_ItPreservesLocksAndIndependentEscrows() external {
        (uint256 a, ) = _deposit(alice, 100 ether);
        (uint256 b, ) = _deposit(bob, 100 ether);
        _protocol(50 ether);
        _recover();
        _fund(0, 200 ether, false);
        _fund(1, 50 ether, false);
        _activate(180 ether, 40 ether, false);
        assertEq(vault.previewWithdraw(a), 90 ether);
        _expect(IV2SupporterVault.PositionLocked.selector);
        vm.prank(alice);
        vault.withdraw(a, 0, block.timestamp);
        _unlock();
        // Subsequent protocol rate appreciation cannot change the fixed token budgets.
        balances.setRate(10, 1);
        vm.prank(bob);
        assertEq(vault.withdraw(b, 90 ether, block.timestamp), 90 ether);
        vm.prank(address(safe));
        assertEq(vault.withdrawProtocol(50 ether, 40 ether, block.timestamp), 40 ether);
        assertEq(token.balanceOf(address(vault)), 120 ether);
        vm.prank(alice);
        assertEq(vault.withdraw(a, 90 ether, block.timestamp), 90 ether);
        assertEq(vault.recoveryBucket(0).paidTokens, 180 ether);
        assertEq(vault.recoveryBucket(0).closedBasis, 200 ether);
        assertEq(vault.bucket(1).basis, 0);
        _expect(IV2SupporterVault.ClosedPosition.selector);
        vm.prank(alice);
        vault.withdraw(a, 0, block.timestamp);
        assertEq(vault.initialManifest(), evidence);
        assertEq(vault.settlementManifest(), classification);
        vm.prank(address(safe));
        vault.finalizeRecovery();
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(coordinator.received(0), 20 ether);
        assertEq(coordinator.received(1), 10 ether);
        assertEq(uint256(vault.recoveryState()), 3);
        _expect(IV2SupporterVault.WrongState.selector);
        vm.prank(address(safe));
        vault.finalizeRecovery();
    }
    function test_GivenTotalLossBudget_WhenClaimingZero_ItClosesWithoutTokenTransferAndCannotDoubleClaim() external {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _recover();
        _activate(0, 0, false);
        _unlock();
        token.setFail(true);
        vm.prank(alice);
        assertEq(vault.withdraw(id, 0, block.timestamp), 0);
        assertTrue(vault.position(id).closed);
        assertEq(vault.bucket(0).basis, 0);
        assertEq(vault.recoveryBucket(0).closedBasis, 10 ether);
        _expect(IV2SupporterVault.ClosedPosition.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        vm.prank(address(safe));
        vault.finalizeRecovery();
    }
    function test_GivenAvailableValuation_WhenExceptionalModeAttempted_ItRejectsManualFallback() external {
        _deposit(alice, 10 ether);
        _recover();
        _fund(0, 10 ether, false);
        _expect(IV2SupporterVault.ValuationAvailable.selector);
        _activate(10 ether, 0, true);
        assertEq(uint256(vault.recoveryState()), 1);
    }
    function test_GivenUnavailableCanonicalGetter_WhenSafeAttestsPublishedBudget_ItActivatesExplicitException()
        external
    {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _recover();
        _fund(0, 10 ether, false);
        balances.setFail(true);
        _activate(9 ether, 0, true);
        assertTrue(vault.exceptionalSettlement());
        _unlock();
        vm.prank(alice);
        assertEq(vault.withdraw(id, 9 ether, block.timestamp), 9 ether);
        assertEq(token.balanceOf(alice), 9 ether);
    }
    function test_GivenAvailableZeroCanonicalValue_WhenActivating_ItTreatsAllBackingAsImpairedWithoutInverse()
        external
    {
        _deposit(alice, 10 ether);
        _recover();
        _fund(0, 10 ether, false);
        balances.setRate(0, 1);
        uint256[2] memory caps = vault.recoveryCaps();
        assertEq(caps[0], 10 ether);
        assertEq(caps[1], 0);
        _activate(10 ether, 0, false);
    }
    function test_GivenHealthyCarry_WhenActivating_ItCapsPrincipalAndDoesNotCountReturnedBackingTwice() external {
        _deposit(alice, 100 ether);
        _recover();
        _fund(0, 100 ether, false);
        balances.setRate(2, 1);
        assertEq(vault.recoveryCaps()[0], 50 ether);
        _expect(IV2SupporterVault.InvalidBudget.selector);
        _activate(100 ether, 0, false);
        _activate(50 ether, 0, false);
    }
    function test_GivenBudgetWithoutFullFunding_WhenActivating_ItCannotOpenFirstComeSettlement() external {
        _deposit(alice, 100 ether);
        _protocol(50 ether);
        _recover();
        _expect(IV2SupporterVault.UnfundedSettlement.selector);
        _activate(100 ether, 0, false);
        _fund(0, 100 ether, false);
        _expect(IV2SupporterVault.UnfundedSettlement.selector);
        _activate(100 ether, 50 ether, false);
        assertEq(uint256(vault.recoveryState()), 1);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.fundRecovery(0, 1);
        token.mint(address(vault), 50 ether);
        _expect(IV2SupporterVault.UnfundedSettlement.selector);
        _activate(100 ether, 50 ether, false);
        _fund(1, 50 ether, false);
        _activate(100 ether, 50 ether, false);
        _expect(IV2SupporterVault.WrongState.selector);
        vault.fundRecovery(0, 1);
        _expect(IV2SupporterVault.WrongState.selector);
        vault.repairRecovery(0, 1);
        _expect(IV2SupporterVault.WrongState.selector);
        _activate(100 ether, 50 ether, false);
    }
    function test_GivenVoluntaryRepairOverfunding_WhenFinalizing_ItRefundsOnlyUnusedRepairAndDonatesCarryAndDust()
        external
    {
        (uint256 a, ) = _deposit(alice, 1);
        (uint256 b, ) = _deposit(bob, 2);
        token.mint(address(vault), 5);
        _recover();
        _fund(0, 3, false);
        token.mint(address(safe), 4);
        vm.startPrank(address(safe));
        token.approve(address(vault), 4);
        vault.fundRefundableRecovery(0, 4);
        vm.stopPrank();
        _activate(2, 0, false);
        _unlock();
        vm.prank(alice);
        assertEq(vault.withdraw(a, 0, block.timestamp), 0);
        vm.prank(bob);
        assertEq(vault.withdraw(b, 0, block.timestamp), 1);
        vm.prank(address(safe));
        vault.finalizeRecovery();
        assertEq(token.balanceOf(address(safe)), 4);
        // 2 unused original tokens + 5 quarantined surplus; no last-claimant dust bonus.
        assertEq(coordinator.received(0), 7);
        assertEq(token.balanceOf(address(vault)), 0);
    }
    function test_GivenEmptyRecovery_WhenActivatingZeroBudgets_ItNeedsNoFakeFunding() external {
        _recover();
        _activate(0, 0, false);
        vm.prank(address(safe));
        vault.finalizeRecovery();
        assertEq(uint256(vault.recoveryState()), 3);
    }
    function test_RefundableRecoveryFundingRequiresSafeReturnedBackingValidBucketStateAndPositiveTokens() external {
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.fundRefundableRecovery(0, 1);
        _expect(IV2SupporterVault.WrongState.selector);
        vm.prank(address(safe));
        vault.fundRefundableRecovery(0, 1);
        _deposit(alice, 10 ether);
        _recover();
        _expect(IV2SupporterVault.InvalidBucket.selector);
        vm.prank(address(safe));
        vault.fundRefundableRecovery(2, 1);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.fundRefundableRecovery(0, 1);
        _fund(0, 10 ether, false);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.fundRefundableRecovery(0, 0);
        token.mint(address(safe), 2 ether);
        vm.startPrank(address(safe));
        token.approve(address(vault), 2 ether);
        vault.fundRefundableRecovery(0, 2 ether);
        vm.stopPrank();
        assertEq(vault.recoveryBucket(0).repairTokens, 2 ether);
        assertEq(vault.recoveryBucket(0).refundableRepairTokens, 2 ether);
        _activate(10 ether, 0, false);
        _expect(IV2SupporterVault.WrongState.selector);
        vm.prank(address(safe));
        vault.fundRefundableRecovery(0, 1);
    }
    function test_WhenUnauthorizedPrematureOrBadManifest_ItRejectsAllRecoveryAuthorityEscalations() external {
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.beginRecovery(evidence);
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vm.prank(address(safe));
        vault.beginRecovery(bytes32(0));
        _expect(IV2SupporterVault.WrongState.selector);
        vault.fundRecovery(0, 1);
        _expect(IV2SupporterVault.WrongState.selector);
        vm.prank(address(safe));
        vault.finalizeRecovery();
        _deposit(alice, 10 ether);
        _recover();
        uint256[2] memory budgets = [uint256(0), uint256(0)];
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.activateSettlement(budgets, classification);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.activateExceptionalSettlement(budgets, classification);
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vm.prank(address(safe));
        vault.activateSettlement(budgets, bytes32(0));
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vm.prank(address(safe));
        vault.activateSettlement(budgets, evidence);
        _activate(0, 0, false);
        _expect(IV2SupporterVault.OutstandingLiabilities.selector);
        vm.prank(address(safe));
        vault.finalizeRecovery();
    }
    function test_FinalizationCannotSweepProtocolEscrowAfterLastSupporterClaimCloses() external {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _protocol(10 ether);
        _recover();
        _fund(0, 10 ether, false);
        _fund(1, 10 ether, false);
        _activate(10 ether, 10 ether, false);
        _unlock();
        vm.prank(alice);
        vault.withdraw(id, 10 ether, block.timestamp);
        _expect(IV2SupporterVault.OutstandingLiabilities.selector);
        vm.prank(address(safe));
        vault.finalizeRecovery();
        assertEq(token.balanceOf(address(vault)), 10 ether);
    }
    function test_GivenFundingCustodyShortfall_WhenClaiming_ItCannotDrainAnotherBucketEscrow() external {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _protocol(10 ether);
        _recover();
        _fund(0, 10 ether, false);
        _fund(1, 10 ether, false);
        _activate(10 ether, 10 ether, false);
        token.burn(address(vault), 1);
        _unlock();
        _expect(IV2SupporterVault.CustodyShortfall.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        _expect(IV2SupporterVault.CustodyShortfall.selector);
        vm.prank(address(safe));
        vault.withdrawProtocol(10 ether, 0, block.timestamp);
        assertFalse(vault.position(id).closed);
    }
    function test_GivenExportTransferFailure_WhenBeginning_ItRollsBackFreezeAndSnapshot() external {
        _deposit(alice, 10 ether);
        token.setFail(true);
        vm.expectRevert();
        vm.prank(address(safe));
        vault.beginRecovery(evidence);
        assertEq(uint256(vault.recoveryState()), 0);
        assertEq(vault.initialManifest(), bytes32(0));
        assertEq(vault.bucket(0).tokens, 10 ether);
    }
    function testFuzz_FixedSettlementHasNoOrderAdvantageBeyondOneAtomPerClaim(
        uint96 aSeed,
        uint96 bSeed,
        uint96 budgetSeed,
        bool reverse
    ) external {
        uint256 a = bound(aSeed, 1, 1e25);
        uint256 b = bound(bSeed, 1, 1e25);
        (uint256 ia, ) = _deposit(alice, a);
        (uint256 ib, ) = _deposit(bob, b);
        uint256 budget = bound(budgetSeed, 0, a + b);
        _recover();
        _fund(0, a + b, false);
        _activate(budget, 0, false);
        _unlock();
        if (reverse) {
            vm.prank(bob);
            vault.withdraw(ib, 0, block.timestamp);
            vm.prank(alice);
            vault.withdraw(ia, 0, block.timestamp);
        } else {
            vm.prank(alice);
            vault.withdraw(ia, 0, block.timestamp);
            vm.prank(bob);
            vault.withdraw(ib, 0, block.timestamp);
        }
        assertEq(token.balanceOf(alice), (budget * a) / (a + b));
        assertEq(token.balanceOf(bob), (budget * b) / (a + b));
        uint256 paid = token.balanceOf(alice) + token.balanceOf(bob);
        assertLe(budget - paid, 1);
        assertEq(token.balanceOf(address(vault)) + paid, a + b);
    }
}
