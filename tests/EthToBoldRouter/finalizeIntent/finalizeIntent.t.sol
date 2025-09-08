// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEthToBoldRouter } from "src/interfaces/IEthToBoldRouter.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FinalizeIntentTest is BaseTest {
    function test_RevertWhen_NotTheYieldManager(address invocator) external {
        vm.assume(invocator != users.yieldManager && invocator != contracts.yieldManager);
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                invocator,
                ethToBoldRouter.YIELD_MANAGER_ROLE()
            )
        );
        resetPrank(invocator);
        ethToBoldRouter.finalizeIntent();
    }

    function test_RevertWhen_ThereIsNoActiveOrder() external whenTheYieldManager {
        resetPrank(users.yieldManager);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.NoActiveOrder.selector));
        ethToBoldRouter.finalizeIntent();
    }

    function test_WhenTheIntentReverted(
        uint256 amount,
        uint16 fee,
        uint16 slippage,
        uint32 validity
    ) external whenTheYieldManager whenThereIsAnActiveOrder {
        resetPrank(users.yieldManager);

        vm.assume(amount > 0);
        vm.assume(amount < type(uint128).max);
        vm.assume(fee >= 0);
        vm.assume(fee < amount * 10 / 100);
        vm.assume(slippage >= 0);
        vm.assume(slippage < 10000);
        vm.assume(validity < 10000);
        vm.deal(users.yieldManager, amount);

        // Mock first order calls
        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(1 ether), uint256(0), uint256(block.timestamp - 500), uint80(0))
        );

        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(uint8(8))
        );

        (uint256 sellAmount, uint256 feeAmount, uint256 minBold) = calculateOrderAmounts(
            amount,
            int256(1 ether),
            fee,
            slippage
        );

        IEthFlow.Data memory expected = IEthFlow.Data({
            buyToken: IERC20(contracts.bold),
            receiver: contracts.ethToBoldRouter,
            sellAmount: sellAmount,
            buyAmount: minBold,
            appData: bytes32(uint256(0x53ba1)),
            feeAmount: feeAmount,
            validTo: uint32(block.timestamp) + validity,
            partiallyFillable: false,
            quoteId: 0
        });

        bytes32 uid = bytes32(abi.encodePacked("newOrder"));

        vm.mockCall(
            contracts.ethFlow,
            amount,
            abi.encodeWithSelector(IEthFlow.createOrder.selector, expected),
            abi.encode(uid)
        );

        ethToBoldRouter.swapExactEthForBold{ value: amount }(fee, slippage, validity);

        // it should call invalidateOrder
        vm.mockCallRevert(
            contracts.ethFlow,
            abi.encodeWithSelector(IEthFlow.invalidateOrder.selector, expected),
            abi.encodeWithSignature("AlreadyInvalidated()")
        );
        vm.expectCall(contracts.ethFlow, abi.encodeWithSelector(IEthFlow.invalidateOrder.selector, expected));
        // Send some WETH to the contract to simulate a WETH refund
        vm.deal(users.yieldManager, amount);
        weth.deposit{ value: amount }();
        weth.transfer(contracts.ethToBoldRouter, amount);
        assertEq(users.yieldManager.balance, 0);

        // it should emit IntentFinalized
        vm.expectEmit();
        emit IEthToBoldRouter.IntentFinalized(users.yieldManager, uid, amount, 0);

        ethToBoldRouter.finalizeIntent();
        // it should return ETH to the sender
        assertEq(users.yieldManager.balance, amount);
        // it should mark the order inactive
        (, , , bool _active, ) = ethToBoldRouter.order();
        assertFalse(_active);
    }

    function test_WhenTheIntentSucceeded(
        uint256 amount,
        uint16 fee,
        uint16 slippage,
        uint32 validity
    ) external whenTheYieldManager whenThereIsAnActiveOrder {
        resetPrank(users.yieldManager);

        vm.assume(amount > 0);
        vm.assume(amount < type(uint128).max);
        vm.assume(fee >= 0);
        vm.assume(fee < amount * 10 / 100);
        vm.assume(slippage >= 0);
        vm.assume(slippage < 10000);
        vm.assume(validity < 10000);
        vm.deal(users.yieldManager, amount);

        // Mock first order calls
        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(1 ether), uint256(0), uint256(block.timestamp - 500), uint80(0))
        );

        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(uint8(8))
        );

        (uint256 sellAmount, uint256 feeAmount, uint256 minBold) = calculateOrderAmounts(
            amount,
            int256(1 ether),
            fee,
            slippage
        );

        IEthFlow.Data memory expected = IEthFlow.Data({
            buyToken: IERC20(contracts.bold),
            receiver: contracts.ethToBoldRouter,
            sellAmount: sellAmount,
            buyAmount: minBold,
            appData: bytes32(uint256(0x53ba1)),
            feeAmount: feeAmount,
            validTo: uint32(block.timestamp) + validity,
            partiallyFillable: false,
            quoteId: 0
        });

        bytes32 uid = bytes32(abi.encodePacked("newOrder"));

        vm.mockCall(
            contracts.ethFlow,
            amount,
            abi.encodeWithSelector(IEthFlow.createOrder.selector, expected),
            abi.encode(uid)
        );

        ethToBoldRouter.swapExactEthForBold{ value: amount }(fee, slippage, validity);

        // it should call invalidateOrder
        vm.mockCall(
            contracts.ethFlow,
            abi.encodeWithSelector(IEthFlow.invalidateOrder.selector, expected),
            abi.encodeWithSignature("Success()")
        );
        vm.expectCall(contracts.ethFlow, abi.encodeWithSelector(IEthFlow.invalidateOrder.selector, expected));
        // Send some BOLD to the contract to simulate a succesful intent swap
        deal(address(bold), contracts.ethToBoldRouter, amount * 10);
        assertEq(bold.balanceOf(users.yieldManager), 0);

        // it should emit IntentFinalized (we also get the initial ETH back in this simulation)
        vm.expectEmit();
        emit IEthToBoldRouter.IntentFinalized(users.yieldManager, uid, amount, amount * 10);

        ethToBoldRouter.finalizeIntent();
        // it should return BOLD to the sender
        assertEq(bold.balanceOf(users.yieldManager), amount * 10);
        // it should mark the order inactive
        (, , , bool _active, ) = ethToBoldRouter.order();
        assertFalse(_active);
    }
}
