// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { VaultBaseTest } from "../VaultBase.t.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";

contract VaultRepairTest is VaultBaseTest {
    function test_GivenDeficit_WhenDonorRepairs_ItRestoresOnlyChosenBucketWithoutMintingBasis() external {
        _deposit(alice, 100 ether);
        _protocol(50 ether);
        balances.setRate(1, 2);
        token.mint(bob, 100 ether);
        vm.startPrank(bob);
        token.approve(address(vault), 100 ether);
        vault.repair(0, 100 ether);
        vm.stopPrank();
        assertEq(vault.bucket(0).tokens, 200 ether);
        assertEq(vault.bucket(0).basis, 100 ether);
        assertEq(vault.bucket(0).repairTokens, 100 ether);
        assertEq(vault.bucket(1).tokens, 50 ether);
        assertEq(vault.bucket(1).basis, 50 ether);
        assertEq(vault.nextPositionId(), 2);
        (uint256 v, uint256 deficit, uint256 reserve, uint256 carry) = vault.accounting(0);
        assertEq(v, 100 ether);
        assertEq(deficit, 0);
        assertEq(reserve, 200 ether);
        assertEq(carry, 0);
        (, uint256 pd, , ) = vault.accounting(1);
        assertEq(pd, 25 ether);
    }
    function test_GivenSurplus_WhenSafeClassifiesRepairOrYield_ItCannotClassifyNonexistentTokensOrMintBasis() external {
        _deposit(alice, 100 ether);
        token.mint(address(vault), 50 ether);
        balances.setRate(2, 3);
        _expect(IV2SupporterVault.Deficit.selector);
        vm.prank(address(safe));
        vault.recognizeSurplus(0, 50 ether, false);
        vm.prank(address(safe));
        vault.recognizeSurplus(0, 50 ether, true);
        assertEq(vault.bucket(0).basis, 100 ether);
        assertEq(vault.bucket(0).repairTokens, 50 ether);
        token.mint(address(vault), 3 ether);
        vm.prank(address(safe));
        vault.recognizeSurplus(1, 3 ether, false);
        assertEq(vault.bucket(1).tokens, 3 ether);
        assertEq(vault.bucket(1).basis, 0);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.recognizeSurplus(1, 1, false);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.recognizeSurplus(1, 0, false);
    }
    function test_WhenWrongBucketZeroOrCustodyShortage_ItRejectsRepairAndClassification() external {
        _expect(IV2SupporterVault.InvalidBucket.selector);
        vault.repair(2, 1);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vault.repair(0, 0);
        _expect(IV2SupporterVault.InvalidBucket.selector);
        vm.prank(address(safe));
        vault.recognizeSurplus(2, 1, true);
        _deposit(alice, 10 ether);
        token.burn(address(vault), 1);
        _expect(IV2SupporterVault.CustodyShortfall.selector);
        vault.repair(0, 1);
    }
    function test_GivenNoncoreAsset_WhenSafeRescues_ItCannotSweepCoreTokenOrChooseAnotherRecipient() external {
        ybold.mint(address(vault), 10 ether);
        vm.prank(address(safe));
        vault.rescueNoncore(address(ybold), 10 ether);
        assertEq(ybold.balanceOf(address(safe)), 10 ether);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.rescueNoncore(address(token), 1);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.rescueNoncore(address(0), 1);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(address(safe));
        vault.rescueNoncore(address(ybold), 0);
    }
}
