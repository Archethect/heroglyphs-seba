// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../../module/CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
contract CowEscrowOrderDataTest is CowModuleTestBase {
    function test_orderDataPreservesOneShotEscrowPolicy() public {
        (, address escrow) = _open(3, 1 ether);
        I.Data memory d = SebaCowOrderEscrow(escrow).orderData();
        assertEq(d.receiver, escrow);
        assertEq(d.sellAmount, 1 ether);
        assertEq(d.buyAmount, 1 ether);
        assertEq(d.kind, keccak256("sell"));
        assertFalse(d.partiallyFillable);
    }
}
