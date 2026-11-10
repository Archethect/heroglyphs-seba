// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../../module/CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
contract CowEscrowCloseTest is CowModuleTestBase {
    function test_closePreservesOneShotEscrowPolicy() public {
        (uint256 id, address escrow) = _open(0, 1 ether);
        SebaCowOrderEscrow e = SebaCowOrderEscrow(escrow);
        vm.expectRevert(I.Unauthorized.selector);
        e.close(true);
        module.closeOrder(id, true);
        assertTrue(e.closed());
        vm.prank(address(module));
        vm.expectRevert(I.ClosedOrder.selector);
        e.close(true);
    }
}
