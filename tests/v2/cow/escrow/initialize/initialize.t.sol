// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../../module/CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
contract CowEscrowInitializeTest is CowModuleTestBase {
    function test_initializePreservesOneShotEscrowPolicy() public {
        (, address escrow) = _open(0, 1 ether);
        SebaCowOrderEscrow e = SebaCowOrderEscrow(escrow);
        vm.expectRevert(I.Unauthorized.selector);
        e.initialize(address(weth), 1, 1, 1, 0);
        vm.prank(address(module));
        vm.expectRevert(I.InvalidOrder.selector);
        e.initialize(address(weth), 1, 1, 1, 0);
    }
}
