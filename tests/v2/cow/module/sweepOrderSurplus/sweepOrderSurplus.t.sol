// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
import { CowTokenMock, CowSettlementMock } from "../../CowMocks.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { CowModuleTestBase } from "../CowModuleTestBase.sol";

contract CowModuleTestSweepOrderSurplusTest is CowModuleTestBase {
    function test_InitializationAndTerminalSurplusPermissions() public {
        SebaCowOrderEscrow implementation = SebaCowOrderEscrow(module.implementation());
        vm.expectRevert(I.Unauthorized.selector);
        implementation.initialize(address(weth), 1, 1, 1, 0);
        vm.prank(address(module));
        vm.expectRevert(I.InvalidOrder.selector);
        implementation.initialize(address(weth), 1, 1, 1, 0);
        address empty = Clones.clone(module.implementation());
        vm.prank(address(module));
        vm.expectRevert(I.ClosedOrder.selector);
        SebaCowOrderEscrow(empty).close(true);
        (uint256 id, address escrow) = _open(0, 1 ether);
        vm.prank(address(module));
        vm.expectRevert(I.InvalidOrder.selector);
        SebaCowOrderEscrow(escrow).initialize(address(weth), 1, 1, 1, 0);
        vm.expectRevert(I.Unauthorized.selector);
        SebaCowOrderEscrow(escrow).close(true);
        vm.expectRevert(I.Unauthorized.selector);
        SebaCowOrderEscrow(escrow).sweep(address(bold));
        vm.prank(address(module));
        vm.expectRevert(I.PendingOrder.selector);
        SebaCowOrderEscrow(escrow).sweep(address(bold));
        module.closeOrder(id, true);
        vm.prank(address(module));
        vm.expectRevert(I.ClosedOrder.selector);
        SebaCowOrderEscrow(escrow).close(true);
        vm.deal(escrow, 2 ether);
        vm.prank(safe);
        module.sweepOrderSurplus(id, address(0));
        assertEq(safe.balance, 2 ether);
        vm.deal(escrow, 1 ether);
        vm.etch(safe, hex"60006000fd");
        vm.prank(safe);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.sweepOrderSurplus(id, address(0));
    }
}
