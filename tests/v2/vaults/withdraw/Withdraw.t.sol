// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { VaultBaseTest } from "../VaultBase.t.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";

contract VaultWithdrawTest is VaultBaseTest {
    function testFuzz_ImpairedExitOrderNeverFavorsFirstClaimantBeyondOneAtom(uint128 aSeed, uint128 bSeed) external {
        uint256 a = bound(aSeed, 1 ether, 1e30);
        uint256 b = bound(bSeed, 1 ether, 1e30);
        (uint256 ia, ) = _deposit(alice, a);
        balances.setRate(2, 1);
        (uint256 ib, ) = _deposit(bob, b);
        balances.setRate(1, 4);
        _unlock();
        uint256 snapshot = vm.snapshot();
        vm.prank(alice);
        uint256 aliceFirst = vault.withdraw(ia, 0, block.timestamp);
        vm.prank(bob);
        uint256 bobLast = vault.withdraw(ib, 0, block.timestamp);
        assertEq(aliceFirst + bobLast, a + b);
        assertTrue(vm.revertTo(snapshot));
        vm.prank(bob);
        uint256 bobFirst = vault.withdraw(ib, 0, block.timestamp);
        vm.prank(alice);
        uint256 aliceLast = vault.withdraw(ia, 0, block.timestamp);
        assertEq(aliceLast + bobFirst, a + b);
        assertLe(aliceFirst, aliceLast);
        assertLe(bobFirst, bobLast);
        assertLe(aliceLast - aliceFirst, 1);
        assertLe(bobLast - bobFirst, 1);
        assertEq(vault.bucket(0).basis, 0);
        assertEq(vault.bucket(0).tokens, 0);
    }
    function test_GivenNonstandardTransferDeltas_WhenPaying_ItRejectsEveryRebaseOrExtraDebitBoundary() external {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _deposit(bob, 10 ether);
        token.mint(alice, 20 ether);
        _unlock();
        for (uint8 mode = 2; mode <= 5; ++mode) {
            token.setMutation(mode);
            _expect(IV2SupporterVault.UnexpectedTokenDelta.selector);
            vm.prank(alice);
            vault.withdraw(id, 0, block.timestamp);
            assertFalse(vault.position(id).closed);
            assertEq(token.balanceOf(address(vault)), 20 ether);
            assertEq(token.balanceOf(alice), 20 ether);
        }
    }
    function test_GivenMultiplicationAboveUint256_WhenEnteringReservingAndWithdrawing_ItUsesFullPrecision() external {
        uint256 q = uint256(1) << 200;
        uint256 unit = uint256(1) << 100;
        balances.setRate(unit, unit);
        (uint256 id, uint256 b) = _deposit(alice, q);
        assertEq(b, q);
        (, , uint256 reserve, ) = vault.accounting(0);
        assertEq(reserve, q);
        _unlock();
        vm.prank(alice);
        assertEq(vault.withdraw(id, q, block.timestamp), q);
        assertEq(token.balanceOf(alice), q);
        assertEq(vault.bucket(0).tokens, 0);
    }
    function test_GivenRecognizedGrowth_WhenLastHealthyUserExits_ItRetainsAllCarry() external {
        balances.setRate(11 ether, 10 ether);
        (uint256 id, ) = _deposit(alice, 100 ether);
        _unlock();
        balances.setRate(12 ether, 10 ether);
        assertEq(vault.previewWithdraw(id), (uint256(110 ether) * 10) / 12);
        vm.prank(alice);
        uint256 q = vault.withdraw(id, 91 ether, block.timestamp);
        assertEq(q, (uint256(110 ether) * 10) / 12);
        assertEq(token.balanceOf(alice), q);
        assertEq(vault.bucket(0).basis, 0);
        assertEq(vault.bucket(0).tokens, 100 ether - q);
        assertGt(vault.bucket(0).tokens, 8 ether);
        assertTrue(vault.position(id).closed);
        _expect(IV2SupporterVault.ClosedPosition.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
    }
    function test_GivenLoss_WhenMultipleUsersExit_ItPaysProRataAndKeepsNominalRemainingBasis() external {
        (uint256 a, ) = _deposit(alice, 100 ether);
        (uint256 b, ) = _deposit(bob, 100 ether);
        balances.setRate(9, 10);
        _unlock();
        vm.prank(bob);
        assertEq(vault.withdraw(b, 0, block.timestamp), 100 ether);
        assertEq(vault.bucket(0).basis, 100 ether);
        assertEq(vault.bucket(0).tokens, 100 ether);
        assertEq(vault.bucket(0).realizedLossBasis, 10 ether);
        vm.prank(alice);
        assertEq(vault.withdraw(a, 0, block.timestamp), 100 ether);
        assertEq(vault.bucket(0).tokens, 0);
        assertEq(vault.bucket(0).basis, 0);
        assertEq(vault.bucket(0).realizedLossBasis, 20 ether);
    }
    function test_GivenZeroCanonicalValue_WhenExiting_ItReturnsRemainingTokensWithoutInverse() external {
        (uint256 id, ) = _deposit(alice, 20 ether);
        balances.setRate(0, 1);
        _unlock();
        vm.prank(alice);
        assertEq(vault.withdraw(id, 20 ether, block.timestamp), 20 ether);
    }
    function test_GivenLossThenRepair_WhenExiting_ItDoesNotDeductHistoricalLossTwice() external {
        (uint256 a, ) = _deposit(alice, 100 ether);
        (uint256 b, ) = _deposit(bob, 100 ether);
        balances.setRate(9, 10);
        _unlock();
        vm.prank(alice);
        vault.withdraw(a, 0, block.timestamp);
        balances.setRate(1, 1);
        vm.prank(bob);
        assertEq(vault.withdraw(b, 100 ether, block.timestamp), 100 ether);
        assertEq(vault.bucket(0).realizedLossBasis, 10 ether);
    }
    function test_GivenEntryHarvestPausedAndStaleReport_WhenExiting_ItRemainsIndependentOfManagerAndVenues() external {
        (uint256 id, ) = _deposit(alice, 100 ether);
        vm.startPrank(address(safe));
        vault.configureEntry(0, false);
        vault.configureHarvest(0, false);
        vm.stopPrank();
        coordinator.configure(true, address(0), "");
        _unlock();
        vm.prank(alice);
        assertEq(vault.withdraw(id, 100 ether, block.timestamp), 100 ether);
    }
    function test_WhenWrongOwnerLockedExpiredOrUnknown_ItPreservesClaim() external {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vm.prank(bob);
        vault.withdraw(id, 0, block.timestamp);
        _expect(IV2SupporterVault.PositionLocked.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        _expect(IV2SupporterVault.Expired.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp - 1);
        _expect(IV2SupporterVault.ClosedPosition.selector);
        vm.prank(alice);
        vault.withdraw(999, 0, block.timestamp);
        assertFalse(vault.position(id).closed);
    }
    function test_WhenMinOutOrTransferFails_ItRollsBackAccountingAndPositionClosure() external {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _unlock();
        _expect(IV2SupporterVault.Slippage.selector);
        vm.prank(alice);
        vault.withdraw(id, 11 ether, block.timestamp);
        assertFalse(vault.position(id).closed);
        token.setFail(true);
        vm.expectRevert();
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        assertFalse(vault.position(id).closed);
        assertEq(vault.bucket(0).basis, 10 ether);
        token.setFail(false);
        token.setFee(1);
        _expect(IV2SupporterVault.UnexpectedTokenDelta.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        assertFalse(vault.position(id).closed);
    }
    function test_GivenTinyClaimAndExtremeGrowth_WhenOrdinaryPayoutRoundsZero_ItRetainsClaimForRecovery() external {
        (uint256 id, ) = _deposit(alice, 1);
        balances.setRate(100, 1);
        _unlock();
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        assertFalse(vault.position(id).closed);
    }
    function test_GivenCustodyShortfall_WhenExitingEitherBucket_ItCannotRaceOtherBucket() external {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _protocol(10 ether);
        token.burn(address(vault), 1);
        _unlock();
        _expect(IV2SupporterVault.CustodyShortfall.selector);
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        _expect(IV2SupporterVault.CustodyShortfall.selector);
        vm.prank(address(safe));
        vault.withdrawProtocol(10 ether, 0, block.timestamp);
        assertEq(vault.bucket(0).basis, 10 ether);
        assertEq(vault.bucket(1).basis, 10 ether);
    }
    function test_GivenUnavailableRate_WhenWithdrawing_ItRequiresRecoveryRatherThanGuessing() external {
        (uint256 id, ) = _deposit(alice, 10 ether);
        _unlock();
        balances.setFail(true);
        vm.expectRevert();
        vm.prank(alice);
        vault.withdraw(id, 0, block.timestamp);
        assertFalse(vault.position(id).closed);
    }
    function test_GivenProtocolBucket_WhenSafeWithdraws_ItUsesFixedTreasuryAndSameMathWithoutLock() external {
        _deposit(alice, 25 ether);
        _protocol(100 ether);
        balances.setRate(2, 1);
        vm.prank(address(safe));
        assertEq(vault.withdrawProtocol(40 ether, 20 ether, block.timestamp), 20 ether);
        assertEq(token.balanceOf(address(safe)), 20 ether);
        assertEq(vault.bucket(1).basis, 60 ether);
        assertEq(vault.bucket(0).basis, 25 ether);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.withdrawProtocol(1, 0, block.timestamp);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.withdrawProtocol(0, 0, block.timestamp);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.withdrawProtocol(61 ether, 0, block.timestamp);
    }
    function testFuzz_HealthyWithdrawalNeverConsumesCeilingReserve(uint128 qSeed, uint64 growth) external {
        uint256 q = bound(qSeed, 1 ether, 1e30);
        (uint256 id, uint256 b) = _deposit(alice, q);
        uint256 n = bound(growth, 1e18, 10e18);
        balances.setRate(n, 1e18);
        _unlock();
        vm.prank(alice);
        uint256 paid = vault.withdraw(id, 0, block.timestamp);
        assertLe(paid, q);
        assertEq(token.balanceOf(alice) + token.balanceOf(address(vault)), q);
        assertLe((paid * n) / 1e18, b);
    }
}
