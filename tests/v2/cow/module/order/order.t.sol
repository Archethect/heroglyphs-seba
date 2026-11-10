// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
contract CowModuleOrderTest is CowModuleTestBase {
    function test_orderPreservesTypedLifecycle() public {
        assertEq(module.order(1).escrow, address(0));
        (uint256 id, address escrow) = _open(3, 1 ether);
        I.Order memory o = module.order(id);
        assertEq(o.escrow, escrow);
        assertEq(o.source, 3);
        module.closeOrder(id, true);
        assertTrue(module.order(id).closed);
    }
}
