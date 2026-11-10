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

contract CowModuleTestCloseOrderTest is CowModuleTestBase {
    function test_UnexpectedEscrowReceiptCannotCloseOrder() public {
        (uint256 id, address escrow) = _open(2, 1 ether);
        // Synthetic escrow-return fault; the pinned standard implementation cannot normally lie this way.
        vm.mockCall(
            escrow,
            abi.encodeCall(SebaCowOrderEscrow.close, (true)),
            abi.encode(false, uint256(1 ether), uint256(0))
        );
        vm.expectRevert(I.UnexpectedTokenDelta.selector);
        module.closeOrder(id, true);
        assertFalse(module.order(id).closed);
        assertEq(module.activeCount(), 1);
    }
    function test_FillAndExpiryRefundAreIsolatedAndExactlyOnce() public {
        (uint256 first, address a) = _open(0, 1 ether);
        (uint256 second, address b) = _open(1, 2 ether);
        settlement.fill(a, address(weth), address(bold), 1 ether, 3 ether);
        (uint8 source, uint256 sell, bool filled, uint256 refund, uint256 received) = module.closeOrder(first, false);
        assertEq(source, 0);
        assertEq(sell, 1 ether);
        assertTrue(filled);
        assertEq(refund, 0);
        assertEq(received, 3 ether);
        assertEq(bold.balanceOf(address(this)), 3 ether);
        assertEq(module.activeCount(), 1);
        assertEq(weth.allowance(a, address(settlement)), 0);
        vm.expectRevert();
        module.closeOrder(second, false);
        vm.warp(block.timestamp + 61);
        uint256 beforeEth = address(this).balance;
        (source, sell, filled, refund, received) = module.closeOrder(second, false);
        assertEq(source, 1);
        assertFalse(filled);
        assertEq(refund, 2 ether);
        assertEq(received, 0);
        assertEq(address(this).balance - beforeEth, 2 ether);
        assertEq(module.activeCount(), 0);
        assertEq(weth.balanceOf(b), 0);
        vm.expectRevert();
        module.closeOrder(first, false);
    }

    function test_DonationsCannotFakeFillAndRemainQuarantinedOnCancel() public {
        (uint256 id, address escrow) = _open(2, 4 ether);
        bold.mint(escrow, 100 ether);
        reth.mint(escrow, 1 ether);
        vm.warp(block.timestamp + 61);
        uint256 beforeReth = reth.balanceOf(address(this));
        (, , bool filled, uint256 refund, uint256 received) = module.closeOrder(id, false);
        assertFalse(filled);
        assertEq(refund, 4 ether);
        assertEq(received, 0);
        assertEq(reth.balanceOf(address(this)) - beforeReth, 4 ether);
        assertEq(bold.balanceOf(escrow), 100 ether);
        vm.prank(safe);
        module.sweepOrderSurplus(id, address(bold));
        assertEq(bold.balanceOf(safe), 100 ether);
    }

    function test_PartialSpendCannotBeMisclassified() public {
        (uint256 id, address escrow) = _open(3, 4 ether);
        settlement.fill(escrow, address(reth), address(bold), 2 ether, 4 ether);
        vm.expectRevert();
        module.closeOrder(id, true);
        assertEq(module.activeCount(), 1);
    }

    function testFuzz_ConcurrentOrdersConserveInput(uint96 raw) public {
        uint256 amount = bound(raw, 1, 100 ether);
        (uint256 a, address first) = _open(2, amount);
        (uint256 b, ) = _open(3, amount);
        settlement.fill(first, address(reth), address(bold), amount, amount + 1);
        module.closeOrder(a, false);
        module.closeOrder(b, true);
        assertEq(reth.balanceOf(address(this)) + reth.balanceOf(address(settlement)), 1_000 ether);
        assertEq(bold.balanceOf(address(this)), amount + 1);
        assertEq(module.activeCount(), 0);
    }
}
