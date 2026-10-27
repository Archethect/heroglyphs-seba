// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { VaultBaseTest } from "../VaultBase.t.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";

contract VaultConfigureTest is VaultBaseTest {
    function test_GivenMissingReportBlock_WhenAdminBoundsAreWide_ItStillRejectsInvalidReport() external {
        vm.prank(address(safe));
        vault.configureReportBounds(2 days, type(uint256).max);
        balances.setReport(block.timestamp, 0);
        token.mint(alice, 1 ether);
        vm.prank(alice);
        token.approve(address(vault), 1 ether);
        _expect(IV2SupporterVault.StaleReport.selector);
        vm.prank(alice);
        vault.deposit(1 ether, 0, block.timestamp);
    }
    function test_WhenUnauthorized_ItRejectsEveryRoutineAuthorityPath() external {
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.configureEntry(1, true);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.configureHarvest(1, true);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.setOperator(alice, true);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.configureReportBounds(1, 1);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.recognizeSurplus(0, 1, true);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.rescueNoncore(address(ybold), 1);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vm.prank(operator);
        vault.setOperator(operator, true);
    }
    function test_WhenUnsafeConfiguration_ItRejectsZeroBoundsAndOperatorEscalation() external {
        vm.startPrank(address(safe));
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vault.configureEntry(0, true);
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vault.configureHarvest(0, true);
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vault.configureReportBounds(0, 1);
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vault.configureReportBounds(1, 0);
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vault.setOperator(address(0), true);
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vault.setOperator(address(safe), true);
        vault.setOperator(operator, false);
        vm.stopPrank();
        _expect(IV2SupporterVault.Unauthorized.selector);
        vm.prank(operator);
        vault.collectYield(0, 1);
    }
    function test_GivenStaleFutureOrMissingReport_WhenDepositing_ItFailsClosedAtApprovedBounds() external {
        token.mint(alice, 100 ether);
        vm.prank(alice);
        token.approve(address(vault), 100 ether);
        balances.setReport(0, block.number);
        _expect(IV2SupporterVault.StaleReport.selector);
        vm.prank(alice);
        vault.deposit(1 ether, 0, block.timestamp);
        balances.setReport(block.timestamp + 1, block.number);
        _expect(IV2SupporterVault.StaleReport.selector);
        vm.prank(alice);
        vault.deposit(1 ether, 0, block.timestamp);
        balances.setReport(block.timestamp - 2 days - 1, block.number);
        _expect(IV2SupporterVault.StaleReport.selector);
        vm.prank(alice);
        vault.deposit(1 ether, 0, block.timestamp);
        balances.setReport(block.timestamp, block.number + 1);
        _expect(IV2SupporterVault.StaleReport.selector);
        vm.prank(alice);
        vault.deposit(1 ether, 0, block.timestamp);
        balances.setReport(block.timestamp, block.number - 20_001);
        _expect(IV2SupporterVault.StaleReport.selector);
        vm.prank(alice);
        vault.deposit(1 ether, 0, block.timestamp);
        balances.setReport(block.timestamp - 2 days, block.number - 20_000);
        vm.prank(alice);
        vault.deposit(1 ether, 1 ether, block.timestamp);
        assertEq(vault.bucket(0).basis, 1 ether);
    }
    function test_GivenRegistryIdentityChangedOrMissing_WhenValuing_ItCannotUseAnotherTokenOrEOA() external {
        registry.set(address(ybold), address(balances));
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vault.rateSnapshot();
        registry.set(address(token), alice);
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        vault.rateSnapshot();
    }
    function test_GivenTerminalRecovery_WhenConfiguring_ItCannotReopenOrdinaryOperations() external {
        _recover();
        vm.startPrank(address(safe));
        _expect(IV2SupporterVault.WrongState.selector);
        vault.configureEntry(1, true);
        _expect(IV2SupporterVault.WrongState.selector);
        vault.configureHarvest(1, true);
        _expect(IV2SupporterVault.WrongState.selector);
        vault.configureReportBounds(1, 1);
        vm.stopPrank();
    }
}
