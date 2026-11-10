// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../../../manager/ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { CowSettlementMock } from "../../CowMocks.sol";
import { ManagerCowTestBase } from "../ManagerCowTestBase.sol";

contract ManagerCowTestFinalizeCowOrderTest is ManagerCowTestBase {
    function test_AllFourSourcesCanCoexistAndCloseOutOfOrder() public {
        rVault.harvest(0, 3 ether);
        rVault.harvest(1, 4 ether);
        (uint256 a, address reward) = _openSource(0, 2 ether);
        (uint256 b, ) = _openSource(1, 2 ether);
        (uint256 c, ) = _openSource(2, 3 ether);
        (uint256 d, address protocolCarry) = _openSource(3, 4 ether);
        assertEq(cow.activeCount(), 4);
        vm.expectRevert(IYieldManagerV2.ActiveCowOrders.selector);
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
        cowSettlement.fill(protocolCarry, address(rethToken), address(boldToken), 4 ether, 5 ether);
        vm.prank(operator);
        manager.finalizeCowOrder(d);
        vm.prank(address(safe));
        manager.setExecutionEnabled(false);
        vm.prank(address(safe));
        cow.setEnabled(false);
        // Pausing new orders does not revoke an already authorized order.
        cowSettlement.fill(reward, address(wethToken), address(boldToken), 2 ether, 3 ether);
        vm.prank(operator);
        manager.finalizeCowOrder(a);
        vm.prank(address(safe));
        manager.finalizeCowOrder(b);
        vm.warp(block.timestamp + 61);
        vm.prank(operator);
        manager.finalizeCowOrder(c);
        assertEq(manager.pendingBold(), 8 ether);
        assertEq(manager.pendingEth(2), 10 ether);
        assertEq(manager.harvestInventory(0, 0), 3 ether);
        assertEq(manager.harvestInventory(0, 1), 0);
        assertEq(cow.activeCount(), 0);
    }

    function test_NoFillExpiredReturnsOriginalPurposeAndBlocksDoubleFinalization() public {
        (uint256 id, ) = _openSource(0, 2 ether);
        vm.expectRevert();
        vm.prank(operator);
        manager.finalizeCowOrder(id);
        assertEq(manager.pendingEth(0), 18 ether);
        vm.warp(block.timestamp + 61);
        vm.prank(operator);
        manager.finalizeCowOrder(id);
        assertEq(manager.pendingEth(0), 20 ether);
        vm.expectRevert();
        vm.prank(operator);
        manager.finalizeCowOrder(id);
    }
}
