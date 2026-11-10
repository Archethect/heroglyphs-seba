// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { StdInvariant } from "forge-std/src/StdInvariant.sol";
import { CowTokenMock, CowSettlementMock } from "./CowMocks.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";

/// @notice Stateful local solver harness; no assertion here proves market fill availability.
contract CowOrderHandler is Test {
    SebaCowIntentModule public module;
    CowTokenMock public weth;
    CowTokenMock public reth;
    CowTokenMock public bold;
    CowSettlementMock public settlement;
    uint256[4] public available;
    uint256[4] public spent;
    uint256[4] public settledBold;
    receive() external payable {}
    function initialize(
        SebaCowIntentModule m,
        CowTokenMock w,
        CowTokenMock r,
        CowTokenMock b,
        CowSettlementMock s
    ) external {
        require(address(module) == address(0));
        module = m;
        weth = w;
        reth = r;
        bold = b;
        settlement = s;
        available = [uint256(500 ether), 500 ether, 500 ether, 500 ether];
        r.approve(address(m), 1000 ether);
    }
    function open(uint8 rawSource, uint96 rawAmount) external {
        uint8 source = rawSource % 4;
        if (module.activeOrder(source) != 0 || available[source] == 0) return;
        uint256 amount = bound(rawAmount, 1, available[source] > 100 ether ? 100 ether : available[source]);
        available[source] -= amount;
        module.openOrder{ value: source < 2 ? amount : 0 }(
            source,
            amount,
            amount,
            uint32(block.timestamp + 60),
            module.nextOrderId(),
            bytes32(uint256(source))
        );
    }
    function fill(uint8 rawSource, uint96 bonus) external {
        uint8 source = rawSource % 4;
        uint256 id = module.activeOrder(source);
        if (id == 0) return;
        I.Order memory o = module.order(id);
        CowTokenMock token = source < 2 ? weth : reth;
        if (token.allowance(o.escrow, address(settlement)) == 0 || block.timestamp > o.validTo) return;
        spent[source] += o.sellAmount;
        settlement.fill(o.escrow, address(token), address(bold), o.sellAmount, o.minBold + bound(bonus, 0, 10 ether));
    }
    function finalize(uint8 rawSource) external {
        uint8 source = rawSource % 4;
        uint256 id = module.activeOrder(source);
        if (id == 0) return;
        I.Order memory o = module.order(id);
        bool filled = (source < 2 ? weth : reth).allowance(o.escrow, address(settlement)) == 0;
        if (!filled && block.timestamp <= o.validTo) return;
        (uint8 actual, , bool proven, uint256 refund, uint256 output) = module.closeOrder(id, false);
        assertEq(actual, source);
        assertEq(proven, filled);
        available[source] += refund;
        settledBold[source] += output;
    }
    function expire(uint8 secondsAfter) external {
        vm.warp(block.timestamp + uint256(secondsAfter) + 1);
    }
    function donate(uint8 rawSource, uint96 rawAmount) external {
        uint256 id = module.activeOrder(rawSource % 4);
        if (id == 0) return;
        bold.mint(module.order(id).escrow, bound(rawAmount, 1, 1 ether));
    }
}

contract CowOrderInvariantTest is StdInvariant, Test {
    CowOrderHandler internal handler;
    SebaCowIntentModule internal module;
    CowTokenMock internal weth;
    CowTokenMock internal reth;
    CowTokenMock internal bold;
    CowSettlementMock internal settlement;
    function setUp() public {
        vm.warp(1_000_000);
        handler = new CowOrderHandler();
        weth = new CowTokenMock();
        reth = new CowTokenMock();
        bold = new CowTokenMock();
        settlement = new CowSettlementMock();
        module = new SebaCowIntentModule(
            address(handler),
            address(this),
            address(weth),
            address(reth),
            address(bold),
            address(settlement)
        );
        reth.mint(address(handler), 1000 ether);
        vm.deal(address(handler), 1000 ether);
        handler.initialize(module, weth, reth, bold, settlement);
        module.configureLimits(100 ether, 100 ether, 60);
        module.setEnabled(true);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.open.selector;
        selectors[1] = handler.fill.selector;
        selectors[2] = handler.finalize.selector;
        selectors[3] = handler.expire.selector;
        selectors[4] = handler.donate.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }
    function invariant_SourcesConserveInputIndependentlyAndNativeCustody() public view {
        uint256 ethOpen;
        uint256 rethOpen;
        uint256 count;
        for (uint8 source; source < 4; ++source) {
            uint256 id = module.activeOrder(source);
            uint256 unspent;
            if (id != 0) {
                ++count;
                I.Order memory o = module.order(id);
                assertEq(o.source, source);
                assertFalse(o.closed);
                unspent = (source < 2 ? weth : reth).allowance(o.escrow, address(settlement));
                assertTrue(unspent == 0 || unspent == o.sellAmount);
                if (source < 2) ethOpen += unspent;
                else rethOpen += unspent;
            }
            assertEq(handler.available(source) + handler.spent(source) + unspent, 500 ether);
        }
        assertEq(module.activeCount(), count);
        assertLe(count, 4);
        assertEq(address(handler).balance + ethOpen + weth.balanceOf(address(settlement)), 1000 ether);
        assertEq(reth.balanceOf(address(handler)) + rethOpen + reth.balanceOf(address(settlement)), 1000 ether);
        assertEq(
            bold.balanceOf(address(handler)),
            handler.settledBold(0) + handler.settledBold(1) + handler.settledBold(2) + handler.settledBold(3)
        );
    }
    function invariant_ClosedOrdersCannotBeReapprovedOrReplayed() public view {
        for (uint256 id = 1; id < module.nextOrderId(); ++id) {
            I.Order memory o = module.order(id);
            I.Data memory d = module.orderData(id);
            assertEq(d.receiver, o.escrow);
            assertEq(d.sellAmount, o.sellAmount);
            assertEq(d.buyAmount, o.minBold);
            assertFalse(d.partiallyFillable);
            assertEq(d.feeAmount, 0);
            if (o.closed) {
                assertEq((o.source < 2 ? weth : reth).allowance(o.escrow, address(settlement)), 0);
                assertFalse(settlement.signed(module.orderUid(id)));
            }
        }
    }
    function test_HandlerExercisesPendingFillRefundAndDonationInsteadOfOnlyNoOps() public {
        handler.open(0, 1 ether);
        handler.open(1, 2 ether);
        handler.open(2, 3 ether);
        handler.open(3, 4 ether);
        assertEq(module.activeCount(), 4);
        handler.donate(0, 1);
        handler.fill(0, 0);
        handler.finalize(0);
        handler.fill(3, 0);
        handler.finalize(3);
        handler.expire(60);
        handler.finalize(1);
        handler.finalize(2);
        assertEq(module.activeCount(), 0);
        assertGt(handler.spent(0), 0);
        assertGt(handler.spent(3), 0);
        assertEq(handler.available(1), 500 ether);
        assertEq(handler.available(2), 500 ether);
        invariant_SourcesConserveInputIndependentlyAndNativeCustody();
        invariant_ClosedOrdersCannotBeReapprovedOrReplayed();
    }
    function test_NegativeControlDetectsCustodyLeak() public {
        vm.deal(address(handler), 999 ether);
        vm.expectRevert();
        this.invariant_SourcesConserveInputIndependentlyAndNativeCustody();
    }
}
