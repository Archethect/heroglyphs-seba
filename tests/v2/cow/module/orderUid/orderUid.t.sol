// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
contract CowModuleOrderUidTest is CowModuleTestBase {
    function test_orderUidPreservesTypedLifecycle() public {
        vm.expectRevert(I.InvalidOrder.selector);
        module.orderUid(1);
        (uint256 id, ) = _open(0, 1 ether);
        bytes memory uid = module.orderUid(id);
        assertEq(uid.length, 56);
        module.closeOrder(id, true);
        assertEq(module.orderUid(id), uid);
    }
}
