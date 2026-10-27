// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { VaultBaseTest } from "../VaultBase.t.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";

contract VaultCollectYieldTest is VaultBaseTest {
    function test_GivenGrowth_WhenOperatorCollects_ItPreservesCeilingReserveAndAtomicallyClassifiesManagerInventory()
        external
    {
        (uint256 id, ) = _deposit(alice, 100 ether);
        _protocol(50 ether);
        balances.setRate(12, 10);
        uint256 lockBefore = vault.position(id).unlockAt;
        vm.prank(operator);
        uint256 amount = vault.collectYield(0, 100 ether);
        uint256 reserve = (uint256(100 ether) * 10 + 11) / 12;
        assertEq(amount, 100 ether - reserve);
        assertEq(coordinator.received(0), amount);
        assertEq(token.balanceOf(address(coordinator)), amount);
        assertEq(vault.bucket(0).tokens, reserve);
        assertEq(vault.bucket(0).basis, 100 ether);
        assertEq(vault.position(id).unlockAt, lockBefore);
        assertEq(vault.bucket(1).tokens, 50 ether);
        vm.prank(address(safe));
        assertEq(vault.collectYield(1, 1 ether), 1 ether);
        assertEq(coordinator.received(1), 1 ether);
    }
    function test_GivenNoRecognizedCarryOrLoss_WhenCollecting_ItReturnsZeroAndPreservesPrincipal() external {
        _deposit(alice, 100 ether);
        vm.prank(operator);
        assertEq(vault.collectYield(0, 100 ether), 0);
        balances.setRate(9, 10);
        vm.prank(operator);
        assertEq(vault.collectYield(0, 100 ether), 0);
        balances.setRate(0, 10);
        vm.prank(operator);
        assertEq(vault.collectYield(0, 100 ether), 0);
        assertEq(vault.bucket(0).tokens, 100 ether);
        assertEq(coordinator.received(0), 0);
    }
    function test_GivenEmptyBasisCarry_WhenCollecting_ItCannotEnlargeTheNextDepositor() external {
        token.mint(address(vault), 10 ether);
        vm.prank(address(safe));
        vault.recognizeSurplus(0, 10 ether, false);
        vm.prank(operator);
        assertEq(vault.collectYield(0, 5 ether), 5 ether);
        _deposit(alice, 10 ether);
        assertEq(vault.bucket(0).basis, 10 ether);
        assertEq(vault.bucket(0).tokens, 15 ether);
    }
    function test_WhenWrongBucketCallerCapPauseOrStaleReport_ItCannotHarvest() external {
        _expect(IV2SupporterVault.InvalidBucket.selector);
        vault.collectYield(2, 1);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.collectYield(0, 1);
        vm.prank(address(safe));
        vault.configureHarvest(100, true);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(operator);
        vault.collectYield(0, 0);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(operator);
        vault.collectYield(0, 101);
        vm.prank(address(safe));
        vault.configureHarvest(0, false);
        _expect(IV2SupporterVault.HarvestDisabled.selector);
        vm.prank(operator);
        vault.collectYield(0, 1);
        vm.prank(address(safe));
        vault.configureHarvest(100, true);
        vm.warp(block.timestamp + 3 days);
        _expect(IV2SupporterVault.StaleReport.selector);
        vm.prank(operator);
        vault.collectYield(0, 1);
    }
    function test_GivenManagerCallbackFailureOrReentry_WhenHarvesting_ItRollsBackTransferAndCounters() external {
        _deposit(alice, 100 ether);
        balances.setRate(2, 1);
        coordinator.configure(true, address(0), "");
        vm.expectRevert();
        vm.prank(operator);
        vault.collectYield(0, 10 ether);
        assertEq(vault.bucket(0).tokens, 100 ether);
        assertEq(vault.bucket(0).harvestedTokens, 0);
        assertEq(token.balanceOf(address(coordinator)), 0);
        coordinator.configure(false, address(vault), abi.encodeCall(vault.collectYield, (0, 1)));
        vm.expectRevert();
        vm.prank(operator);
        vault.collectYield(0, 10 ether);
        assertEq(vault.bucket(0).tokens, 100 ether);
    }
    function test_GivenYearnRecognizedGrowth_WhenHarvestingAndExiting_ItDoesNotRedeemYearn() external {
        (uint256 id, ) = _yDeposit(alice, 100 ether);
        yearn.setRate(11, 10);
        vm.prank(address(safe));
        uint256 harvested = yvault.collectYield(0, 100 ether);
        assertEq(harvested, 100 ether - (uint256(100 ether) * 10 + 10) / 11);
        _unlock();
        vm.prank(alice);
        uint256 paid = yvault.withdraw(id, 0, block.timestamp);
        assertEq(paid, (uint256(100 ether) * 10) / 11);
        assertLe(harvested + paid, 100 ether);
        assertEq(yearn.balanceOf(alice), paid);
    }
}
