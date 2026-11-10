// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
contract CowModuleOrderDataTest is CowModuleTestBase {
    function test_orderDataPreservesTypedLifecycle() public {
        vm.expectRevert(I.InvalidOrder.selector);
        module.orderData(1);
        (uint256 id, address escrow) = _open(2, 1 ether);
        I.Data memory d = module.orderData(id);
        assertEq(d.receiver, escrow);
        assertEq(d.sellToken, address(reth));
        assertEq(d.buyToken, address(bold));
        assertEq(d.feeAmount, 0);
        assertFalse(d.partiallyFillable);
    }
}
