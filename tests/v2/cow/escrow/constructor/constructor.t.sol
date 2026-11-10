// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../../module/CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
contract CowEscrowConstructorTest is CowModuleTestBase {
    function test_constructorPreservesOneShotEscrowPolicy() public {
        SebaCowOrderEscrow e = SebaCowOrderEscrow(module.implementation());
        assertEq(e.module(), address(module));
        assertEq(e.treasury(), safe);
        assertEq(e.bold(), address(bold));
        assertEq(e.settlement(), address(settlement));
        assertEq(e.relayer(), address(settlement));
        vm.prank(address(module));
        vm.expectRevert(I.InvalidOrder.selector);
        e.initialize(address(weth), 1, 1, 1, 0);
    }
}
