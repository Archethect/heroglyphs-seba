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

contract CowModuleTestOpenOrderTest is CowModuleTestBase {
    function test_SeparateNativeInputCapsAndExactEthValue() public {
        vm.startPrank(safe);
        module.setEnabled(false);
        module.configureLimits(1 ether, 2 ether, 60);
        module.setEnabled(true);
        vm.stopPrank();
        vm.expectRevert(I.InvalidOrder.selector);
        module.openOrder{ value: 1 ether + 1 }(0, 1 ether + 1, 1, uint32(block.timestamp + 60), 1, 0);
        vm.expectRevert(I.InvalidOrder.selector);
        module.openOrder(2, 2 ether + 1, 1, uint32(block.timestamp + 60), 1, 0);
        vm.expectRevert(I.InvalidOrder.selector);
        module.openOrder(0, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        (uint256 a, ) = _open(0, 1 ether);
        (uint256 b, ) = _open(2, 2 ether);
        assertEq(module.activeCount(), 2);
        module.closeOrder(a, true);
        module.closeOrder(b, true);
    }
    function test_InvalidOrdersAndExclusiveSourceAreAtomic() public {
        vm.prank(safe);
        module.setEnabled(false);
        vm.expectRevert(I.ExecutionDisabled.selector);
        module.openOrder{ value: 1 ether }(0, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        vm.prank(safe);
        module.setEnabled(true);
        for (uint8 i; i < 9; ++i) {
            vm.expectRevert(I.InvalidOrder.selector);
            module.openOrder{ value: i == 8 ? 1 : 0 }(
                i == 0 ? 4 : 2,
                i == 1
                    ? 0
                    : i == 2
                        ? type(uint256).max
                        : i == 3
                            ? 101 ether
                            : 1 ether,
                i == 4 ? 0 : 1,
                i == 5
                    ? uint32(block.timestamp)
                    : i == 6
                        ? uint32(block.timestamp + 901)
                        : uint32(block.timestamp + 60),
                i == 7 ? 2 : 1,
                0
            );
        }
        (uint256 id, address escrow) = _open(2, 1 ether);
        vm.expectRevert(I.InvalidOrder.selector);
        module.openOrder(2, 1, 1, uint32(block.timestamp + 1), 2, 0);
        I.Data memory d = module.orderData(id);
        assertEq(d.sellToken, address(reth));
        assertEq(d.buyToken, address(bold));
        assertEq(d.receiver, escrow);
        assertEq(d.sellAmount, 1 ether);
        assertEq(d.buyAmount, 1 ether);
        assertEq(d.feeAmount, 0);
        assertEq(d.kind, keccak256("sell"));
        assertFalse(d.partiallyFillable);
        assertEq(d.sellTokenBalance, keccak256("erc20"));
        assertEq(d.buyTokenBalance, keccak256("erc20"));
        assertEq(module.orderUid(id).length, 56);
        assertTrue(settlement.signed(module.orderUid(id)));
        vm.prank(safe);
        vm.expectRevert(I.PendingOrder.selector);
        module.sweepOrderSurplus(id, address(bold));
        module.closeOrder(id, true);
        assertFalse(settlement.signed(module.orderUid(id)));
        assertTrue(module.order(id).closed);
    }

    function test_DeltaFaultsAndInsufficientFillFailClosed() public {
        // Explicit nonstandard-token fault injection, not behavior of mainnet WETH/rETH.
        weth.mint(address(module), 1);
        weth.setExtraDebit(address(module), 1);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.openOrder{ value: 1 ether }(0, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        weth.setExtraDebit(address(0), 0);
        reth.setExtraDebit(address(this), 1);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.openOrder(2, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        reth.setExtraDebit(address(0), 0);
        weth.setMintBps(9999);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.openOrder{ value: 1 ether }(0, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        weth.setMintBps(10000);
        weth.setTax(address(module), 1);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.openOrder{ value: 1 ether }(0, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        weth.setTax(address(0), 0);
        reth.setTax(address(this), 1);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.openOrder(2, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        reth.setTax(address(0), 0);
        (uint256 id, address escrow) = _open(0, 1 ether);
        settlement.fill(escrow, address(weth), address(bold), 1 ether, 0.9 ether);
        vm.expectRevert(I.InvalidFill.selector);
        module.closeOrder(id, false);
        bold.mint(escrow, 0.1 ether);
        bold.setTax(escrow, 1);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.closeOrder(id, false);
        bold.setTax(address(module), 1);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.closeOrder(id, false);
        bold.setTax(address(0), 0);
        module.closeOrder(id, false);
        (uint256 b, ) = _open(1, 1 ether);
        rejectEth = true;
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.closeOrder(b, true);
        rejectEth = false;
        module.closeOrder(b, true);
        (uint256 c, address r) = _open(2, 1 ether);
        reth.setTax(r, 1);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.closeOrder(c, true);
        reth.setTax(address(module), 1);
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.closeOrder(c, true);
        reth.setTax(address(0), 0);
        module.closeOrder(c, true);
    }
}
