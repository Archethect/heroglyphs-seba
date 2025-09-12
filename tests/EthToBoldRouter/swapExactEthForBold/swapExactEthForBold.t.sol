// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEthToBoldRouter } from "src/interfaces/IEthToBoldRouter.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapExactEthForBoldTest is BaseTest {
    function test_RevertWhen_TheCallerIsNotTheYieldManager(address invocator) external {
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
        ethToBoldRouter.swapExactEthForBold(0, 0, 0);
    }

    function test_RevertWhen_TheValueIsZero() external whenTheCallerIsTheYieldManager {
        resetPrank(users.yieldManager);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.NoEthSent.selector));
        ethToBoldRouter.swapExactEthForBold(0, 0, 0);
    }

    function test_RevertWhen_TheSlippageIsBiggerOrEqualToTheBpsDenominator(
        uint256 minBoldBeforeSlippage,
        uint16 slippage
    ) external whenTheCallerIsTheYieldManager whenTheValueIsNotZero {
        resetPrank(users.yieldManager);

        vm.assume(minBoldBeforeSlippage >= 0);
        vm.assume(minBoldBeforeSlippage < 10000);
        vm.assume(slippage >= 10000);
        vm.assume(slippage < type(uint16).max);
        vm.deal(users.yieldManager, 1 ether);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.InvalidSlippage.selector, slippage, 10000));
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(minBoldBeforeSlippage, slippage, 0);
    }

    function test_RevertWhen_ThereIsAlreadyAnOpenOrder(
        uint256 minBoldBeforeSlippage,
        uint16 slippage,
        uint32 validity
    )
        external
        whenTheCallerIsTheYieldManager
        whenTheValueIsNotZero
        whenTheSlippageIsSmallerThanTheBpsDenominator
    {
        resetPrank(users.yieldManager);

        vm.assume(minBoldBeforeSlippage >= 0);
        vm.assume(minBoldBeforeSlippage < 10000);
        vm.assume(slippage >= 0);
        vm.assume(slippage < 10000);
        vm.assume(validity > 10000);
        vm.assume(validity < 50000);
        vm.deal(users.yieldManager, 2 ether);

        (uint256 minBold) = calculateOrderAmounts(
            minBoldBeforeSlippage,
            slippage
        );

        IEthFlow.Data memory expected = IEthFlow.Data({
            buyToken: IERC20(contracts.bold),
            receiver: contracts.ethToBoldRouter,
            sellAmount: 1 ether,
            buyAmount: minBold,
            appData: bytes32(uint256(0x53ba1)),
            feeAmount: 0,
            validTo: uint32(block.timestamp) + validity,
            partiallyFillable: false,
            quoteId: 0
        });

        bytes32 uid = bytes32(abi.encodePacked("newOrder"));

        mockAndExpectCall(
            contracts.ethFlow,
            1 ether,
            abi.encodeWithSelector(IEthFlow.createOrder.selector, expected),
            abi.encode(uid)
        );

        // open first order
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(minBoldBeforeSlippage, slippage, validity);

        // it should revert on second order
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.OrderAlreadyOpen.selector));
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(minBoldBeforeSlippage, slippage, validity);
    }

    function test_WhenThereIsNoOpenOrderYet(
        uint256 amount,
        uint16 minBoldBeforeSlippage,
        uint16 slippage,
        uint32 validity
    )
        external
        whenTheCallerIsTheYieldManager
        whenTheValueIsNotZero
        whenTheSlippageIsSmallerThanTheBpsDenominator
        whenThereIsNoOpenOrderYet
    {
        resetPrank(users.yieldManager);

        vm.assume(amount > 0);
        vm.assume(amount < type(uint128).max);
        vm.assume(minBoldBeforeSlippage >= 0);
        vm.assume(minBoldBeforeSlippage < amount * 10 / 100);
        vm.assume(slippage >= 0);
        vm.assume(slippage < 10000);
        vm.assume(validity < 10000);
        vm.deal(users.yieldManager, amount);


        (uint256 minBold) = calculateOrderAmounts(
            minBoldBeforeSlippage,
            slippage
        );

        IEthFlow.Data memory expected = IEthFlow.Data({
            buyToken: IERC20(contracts.bold),
            receiver: contracts.ethToBoldRouter,
            sellAmount: amount,
            buyAmount: minBold,
            appData: bytes32(uint256(0x53ba1)),
            feeAmount: 0,
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

        // it should emit IntentCreated
        vm.expectEmit();
        emit IEthToBoldRouter.IntentCreated(
            users.yieldManager,
            amount,
            minBold,
            uid,
            uint32(block.timestamp) + validity
        );

        // it should call createOrder with the correct order data and value
        vm.expectCall(contracts.ethFlow, amount, abi.encodeWithSelector(IEthFlow.createOrder.selector, expected));

        ethToBoldRouter.swapExactEthForBold{ value: amount }(minBoldBeforeSlippage, slippage, validity);

        // it should register the pending order in the contract
        (
            address _initiator,
            uint256 _ethAmount,
            bytes32 _uid,
            bool _active,
            IEthFlow.Data memory _data
        ) = ethToBoldRouter.order();
        assertEq(_initiator, users.yieldManager);
        assertEq(_ethAmount, amount);
        assertEq(_uid, uid);
        assertEq(_active, true);
        assertEq(address(_data.buyToken), address(expected.buyToken));
        assertEq(_data.receiver, expected.receiver);
        assertEq(_data.sellAmount, expected.sellAmount);
        assertEq(_data.buyAmount, expected.buyAmount);
        assertEq(_data.appData, expected.appData);
        assertEq(_data.feeAmount, expected.feeAmount);
        assertEq(_data.validTo, expected.validTo);
        assertEq(_data.partiallyFillable, expected.partiallyFillable);
        assertEq(_data.quoteId, expected.quoteId);
    }
}
