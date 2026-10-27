// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { VaultBaseTest } from "../VaultBase.t.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";

contract VaultEntryBranchesTest is VaultBaseTest {
    function test_GivenRebasingDownDuringReceipt_ItRejectsNegativeVaultDeltaAndRollsBack() external {
        _deposit(bob, 100 ether);
        token.mint(alice, 10 ether);
        vm.prank(alice);
        token.approve(address(vault), 10 ether);
        token.setMutation(1);
        _expect(IV2SupporterVault.UnexpectedTokenDelta.selector);
        vm.prank(alice);
        vault.deposit(10 ether, 0, block.timestamp);
        assertEq(vault.bucket(0).basis, 100 ether);
        assertEq(token.balanceOf(address(vault)), 100 ether);
    }
    function test_GivenNativeValueBeyondUint256_ItFailsClosedWithoutPartialCustodyCredit() external {
        uint256 q = uint256(1) << 200;
        token.mint(alice, q);
        vm.prank(alice);
        token.approve(address(vault), q);
        balances.setRate(uint256(1) << 100, 1);
        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(q, 0, block.timestamp);
        assertEq(token.balanceOf(alice), q);
        assertEq(vault.bucket(0).basis, 0);
    }
    function test_GivenDifferentEntryRates_WhenUsersDeposit_ItCreditsEntryBasisNotHistoricalTokenCost() external {
        balances.setRate(11, 10);
        (uint256 a, uint256 ab) = _deposit(alice, 100 ether);
        balances.setRate(12, 10);
        (uint256 b, uint256 bb) = _deposit(alice, 100 ether);
        assertEq(ab, 110 ether);
        assertEq(bb, 120 ether);
        assertEq(vault.bucket(0).basis, 230 ether);
        assertEq(vault.position(a).owner, alice);
        assertEq(vault.position(b).unlockAt, block.timestamp + 30 days);
        assertEq(vault.nextPositionId(), 3);
    }
    function test_GivenUnsolicitedTokens_WhenDepositing_ItQuarantinesSurplusWithoutInflatingBasis() external {
        token.mint(address(vault), 1_000 ether);
        _deposit(alice, 100 ether);
        assertEq(vault.bucket(0).tokens, 100 ether);
        assertEq(vault.bucket(0).basis, 100 ether);
        assertEq(token.balanceOf(address(vault)), 1_100 ether);
    }
    function test_WhenQuantityBasisMinimumOrDeadlineInvalid_ItCreatesNoPosition() external {
        token.mint(alice, 20 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 20 ether);
        _expect(IV2SupporterVault.Expired.selector);
        vault.deposit(10 ether, 0, block.timestamp - 1);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vault.deposit(0, 0, block.timestamp);
        _expect(IV2SupporterVault.Slippage.selector);
        vault.deposit(10 ether, 11 ether, block.timestamp);
        vm.stopPrank();
        vm.prank(address(safe));
        vault.configureEntry(11 ether, true);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(alice);
        vault.deposit(10 ether, 0, block.timestamp);
        vm.prank(address(safe));
        vault.configureEntry(1, true);
        balances.setRate(1, 100);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(alice);
        vault.deposit(1, 0, block.timestamp);
        balances.setRate(11, 10);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vm.prank(alice);
        vault.deposit(1, 0, block.timestamp);
        assertEq(vault.nextPositionId(), 1);
        assertEq(token.balanceOf(alice), 20 ether);
    }
    function test_GivenSuccessfulZeroValue_WhenEntryAttempted_ItRejectsWithoutDivisionByZero() external {
        balances.setRate(0, 1);
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);
        _expect(IV2SupporterVault.InvalidAmount.selector);
        vault.deposit(10 ether, 0, block.timestamp);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 10 ether);
    }
    function test_GivenProtocolOrSupporterDeficit_WhenEitherBucketReceivesNewCapital_ItBlocksEntireLeg() external {
        _protocol(10 ether);
        balances.setRate(9, 10);
        token.mint(alice, 10 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 10 ether);
        _expect(IV2SupporterVault.Deficit.selector);
        vault.deposit(10 ether, 0, block.timestamp);
        vm.stopPrank();
        balances.setRate(1, 1);
        _deposit(alice, 10 ether);
        balances.setRate(9, 10);
        token.mint(address(coordinator), 10 ether);
        vm.startPrank(address(coordinator));
        token.approve(address(vault), 10 ether);
        _expect(IV2SupporterVault.Deficit.selector);
        vault.depositProtocol(10 ether, 0, block.timestamp);
        vm.stopPrank();
        // The unrelated native token vault remains available.
        _yDeposit(bob, 10 ether);
        assertEq(yvault.bucket(0).basis, 10 ether);
    }
    function test_GivenPausedEntry_WhenPublicOrProtocolDeposits_ItRejectsWithoutAffectingBalances() external {
        vm.prank(address(safe));
        vault.configureEntry(0, false);
        _expect(IV2SupporterVault.EntriesDisabled.selector);
        vault.deposit(1, 0, block.timestamp);
        _expect(IV2SupporterVault.EntriesDisabled.selector);
        vm.prank(address(coordinator));
        vault.depositProtocol(1, 0, block.timestamp);
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.depositProtocol(1, 0, block.timestamp);
    }
    function test_GivenBadTokenTransfer_WhenDepositAttempted_ItRejectsFeeAndReentrancyWithoutCreditingBasis() external {
        token.mint(alice, 10 ether);
        vm.prank(alice);
        token.approve(address(vault), 10 ether);
        token.setFee(1);
        _expect(IV2SupporterVault.UnexpectedTokenDelta.selector);
        vm.prank(alice);
        vault.deposit(10 ether, 0, block.timestamp);
        token.setFee(0);
        token.setHook(address(vault), abi.encodeCall(vault.deposit, (1, 0, block.timestamp)));
        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(10 ether, 0, block.timestamp);
        assertEq(vault.bucket(0).basis, 0);
        assertEq(token.balanceOf(alice), 10 ether);
    }
    function test_GivenProtocolCredit_WhenManagerDeposits_ItCreatesNoSupporterIDAndTreasurySupportersStaySeparate()
        external
    {
        _protocol(25 ether);
        _deposit(address(safe), 5 ether);
        assertEq(vault.nextPositionId(), 2);
        assertEq(vault.bucket(1).basis, 25 ether);
        assertEq(vault.bucket(0).basis, 5 ether);
        assertEq(vault.position(1).owner, address(safe));
    }
    function test_GivenZeroReportedSupply_WhenDepositing_ItUsesCanonicalOneToOneConvention() external {
        balances.setRate(999, 0);
        _deposit(alice, 10 ether);
        assertEq(vault.bucket(0).basis, 10 ether);
        yearn.setRate(999, 0);
        _yDeposit(alice, 10 ether);
        assertEq(yvault.bucket(0).basis, 10 ether);
    }
    function testFuzz_EntryUsesFloorRateAndNoOtherBucket(
        uint128 quantity,
        uint64 numerator,
        uint64 denominator
    ) external {
        uint256 q = bound(quantity, 1 ether, 1e30);
        uint256 n = bound(numerator, 1e12, 1e20);
        uint256 d = bound(denominator, 1e12, 1e20);
        balances.setRate(n, d);
        (, uint256 b) = _deposit(alice, q);
        assertEq(b, (q * n) / d);
        assertEq(vault.bucket(1).basis, 0);
        assertEq(vault.bucket(0).tokens, q);
    }
}
