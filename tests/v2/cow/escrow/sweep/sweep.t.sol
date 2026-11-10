// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../../module/CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
contract CowEscrowSweepTest is CowModuleTestBase {
    function test_sweepPreservesOneShotEscrowPolicy() public {
        (uint256 id, address escrow) = _open(2, 1 ether);
        SebaCowOrderEscrow e = SebaCowOrderEscrow(escrow);
        vm.expectRevert(I.Unauthorized.selector);
        e.sweep(address(bold));
        vm.prank(address(module));
        vm.expectRevert(I.PendingOrder.selector);
        e.sweep(address(bold));
        module.closeOrder(id, true);
        bold.mint(escrow, 1);
        vm.prank(safe);
        module.sweepOrderSurplus(id, address(bold));
        assertEq(bold.balanceOf(safe), 1);
    }
}
