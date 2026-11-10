// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { StackForkBase, ICowForkSettlement } from "../../fork/StackForkBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

/// @notice Real deployed CoW/relayer/WETH/rETH. Solver impersonation and BOLD inventory are synthetic test fixtures.
/// @dev Does NOT prove orderbook acceptance, live solver discovery, market execution or realizable quoted price.
contract CowSettlementForkTest is StackForkBase {
    function setUp() public override {
        super.setUp();
        _enableTestExecution();
        vm.prank(SAFE);
        manager.setIntakeEnabled(true);
        vm.deal(address(this), 1000 ether);
        vm.deal(address(pool), 40 ether);
        vm.prank(address(pool));
        manager.depositFunds{ value: 40 ether }();
    }
    function _open(uint8 source, uint256 amount, uint256 minimum) private returns (uint256 id, address escrow) {
        id = cow.nextOrderId();
        escrow = cow.predictEscrow(id);
        vm.prank(operator);
        manager.openCowOrder(source, amount, minimum, uint32(block.timestamp + 60), id, bytes32(id));
    }
    function test_RealSettlementPreservesLimitAndFokAndReconcilesAfterFillStorageCleanup() public {
        (uint256 id, address escrow) = _open(0, 1 ether, 1000 ether);
        _settleCow(id, 2000 ether, 96, 0.5 ether); // FOK ignores executedAmount; consumes full input.
        assertEq(IERC20(WETH).allowance(escrow, cow.relayer()), 0);
        assertEq(ICowForkSettlement(COW).filledAmount(cow.orderUid(id)), 1 ether);
        vm.warp(block.timestamp + 61);
        bytes[] memory ids = new bytes[](1);
        ids[0] = cow.orderUid(id);
        // Real protocol cleanup called in its onlyInteraction context; demonstrates nonpersistent fill storage.
        vm.prank(COW);
        ICowForkSettlement(COW).freeFilledAmountStorage(ids);
        assertEq(ICowForkSettlement(COW).filledAmount(ids[0]), 0);
        vm.prank(operator);
        manager.finalizeCowOrder(id);
        assertEq(manager.pendingBold(), 2000 ether);
        assertEq(cow.activeCount(), 0);
        vm.expectRevert();
        vm.prank(operator);
        manager.finalizeCowOrder(id);
    }
    function test_ActualSettlementRejectsLowerOutputAndAlteredPartialOrder() public {
        (uint256 id, ) = _open(0, 1 ether, 1000 ether);
        vm.expectRevert();
        this.settleForTest(id, 999 ether, 96, 1 ether);
        vm.expectRevert();
        this.settleForTest(id, 2000 ether, 98, 0.5 ether);
        assertEq(manager.pendingBold(), 0);
        assertEq(cow.activeCount(), 1);
        vm.prank(SAFE);
        manager.finalizeCowOrder(id);
        assertEq(manager.pendingEth(0), 20 ether);
    }
    function settleForTest(uint256 id, uint256 output, uint256 flags, uint256 executed) external {
        _settleCow(id, output, flags, executed);
    }
    function test_RealRethFiniteAllowanceAndConcurrentPrincipalRewardOrders() public {
        // Synthetic harvested input; only real-token spending/settlement semantics are asserted here.
        deal(RETH, address(manager), 1 ether);
        vm.prank(address(rVault));
        manager.onYieldReceived(0, 1 ether);
        (uint256 a, address rethEscrow) = _open(2, 1 ether, 1000 ether);
        (uint256 b, ) = _open(1, 2 ether, 1000 ether);
        _settleCow(b, 4000 ether, 96, 2 ether);
        _settleCow(a, 2400 ether, 96, 1 ether);
        assertEq(IERC20(RETH).allowance(rethEscrow, cow.relayer()), 0);
        vm.prank(operator);
        manager.finalizeCowOrder(b);
        vm.prank(operator);
        manager.finalizeCowOrder(a);
        assertEq(manager.pendingProtocolBold(), 4000 ether);
        assertEq(manager.pendingBold(), 2400 ether);
        vm.prank(operator);
        manager.deployYsyProtocolPrincipal(4000 ether, 1, 1, block.timestamp + 60);
        assertEq(manager.pendingProtocolBold(), 0);
        assertGt(yVault.bucket(1).basis, 0);
    }
    function test_PausedPendingOrderExpiryRefundAndSafeEarlyCancel() public {
        (uint256 a, ) = _open(0, 1 ether, 1000 ether);
        (uint256 b, ) = _open(1, 2 ether, 1000 ether);
        vm.startPrank(SAFE);
        manager.setExecutionEnabled(false);
        cow.setEnabled(false);
        vm.stopPrank();
        vm.expectRevert(IYieldManagerV2.ActiveCowOrders.selector);
        vm.prank(SAFE);
        manager.recoverBuffers(bytes32(uint256(1)));
        vm.prank(SAFE);
        manager.finalizeCowOrder(a);
        vm.warp(block.timestamp + 61);
        vm.prank(operator);
        manager.finalizeCowOrder(b);
        assertEq(manager.pendingEth(0), 20 ether);
        assertEq(manager.pendingEth(2), 10 ether);
        vm.prank(SAFE);
        manager.recoverBuffers(bytes32(uint256(1)));
        assertTrue(manager.buffersRecovered());
    }
    function test_LargeWethAndRethOrdersUseRealSettlementButSyntheticSolverInventory() public {
        // Synthetic capital and harvested rETH are fixtures, not treasury-liquidation evidence.
        vm.deal(address(manager), address(manager).balance + 100 ether);
        vm.prank(SAFE);
        manager.recognizeEthSurplus(0, 100 ether);
        deal(RETH, address(manager), 45 ether);
        vm.prank(address(rVault));
        manager.onYieldReceived(1, 45 ether);
        (uint256 a, ) = _open(0, 70 ether, 140_000 ether);
        (uint256 b, ) = _open(3, 45 ether, 100_000 ether);
        _settleCow(b, 110_000 ether, 96, 45 ether);
        _settleCow(a, 140_000 ether, 96, 70 ether);
        vm.prank(operator);
        manager.finalizeCowOrder(b);
        vm.prank(operator);
        manager.finalizeCowOrder(a);
        assertEq(manager.pendingBold(), 250_000 ether);
        assertEq(manager.pendingProtocolBold(), 0);
        assertEq(manager.harvestInventory(0, 1), 0);
        assertEq(cow.activeCount(), 0);
        _assertManagerCustody();
    }
}
