// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../../module/CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
contract CowEscrowOrderUidTest is CowModuleTestBase {
    function test_orderUidPreservesOneShotEscrowPolicy() public {
        (uint256 id, address escrow) = _open(0, 1 ether);
        assertEq(SebaCowOrderEscrow(escrow).orderUid(), module.orderUid(id));
        assertEq(module.orderUid(id).length, 56);
    }
}
