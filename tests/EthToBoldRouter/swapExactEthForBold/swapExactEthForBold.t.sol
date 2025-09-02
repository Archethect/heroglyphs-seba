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

    function test_RevertWhen_TheFeeIsBiggerOrEqualToTheBpsDenominator(
        uint16 fee
    ) external whenTheCallerIsTheYieldManager whenTheValueIsNotZero {
        resetPrank(users.yieldManager);

        vm.assume(fee >= 10000);
        vm.assume(fee < type(uint16).max);
        vm.deal(users.yieldManager, 1 ether);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.InvalidFee.selector, fee, 10000));
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(fee, 0, 0);
    }

    function test_RevertWhen_TheSlippageIsBiggerOrEqualToTheBpsDenominator(
        uint16 fee,
        uint16 slippage
    ) external whenTheCallerIsTheYieldManager whenTheValueIsNotZero whenTheFeeIsSmallerThanTheBpsDenominator {
        resetPrank(users.yieldManager);

        vm.assume(fee >= 0);
        vm.assume(fee < 10000);
        vm.assume(slippage >= 10000);
        vm.assume(slippage < type(uint16).max);
        vm.deal(users.yieldManager, 1 ether);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.InvalidSlippage.selector, slippage, 10000));
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(fee, slippage, 0);
    }

    function test_RevertWhen_ThereIsAlreadyAnOpenOrder(
        uint16 fee,
        uint16 slippage,
        uint32 validity
    )
        external
        whenTheCallerIsTheYieldManager
        whenTheValueIsNotZero
        whenTheFeeIsSmallerThanTheBpsDenominator
        whenTheSlippageIsSmallerThanTheBpsDenominator
    {
        resetPrank(users.yieldManager);

        vm.assume(fee >= 0);
        vm.assume(fee < 10000);
        vm.assume(slippage >= 0);
        vm.assume(slippage < 10000);
        vm.assume(validity > 10000);
        vm.assume(validity < 50000);
        vm.deal(users.yieldManager, 2 ether);

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
            1 ether,
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

        mockAndExpectCall(
            contracts.ethFlow,
            1 ether,
            abi.encodeWithSelector(IEthFlow.createOrder.selector, expected),
            abi.encode(uid)
        );

        // open first order
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(fee, slippage, validity);

        // it should revert on second order
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.OrderAlreadyOpen.selector));
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(fee, slippage, validity);
    }

    function test_RevertWhen_TheOraclePriceIsEqualOrSmallerThanZero(
        uint16 fee,
        uint16 slippage,
        uint32 validity
    )
        external
        whenTheCallerIsTheYieldManager
        whenTheValueIsNotZero
        whenTheFeeIsSmallerThanTheBpsDenominator
        whenTheSlippageIsSmallerThanTheBpsDenominator
        whenThereIsNoOpenOrderYet
    {
        resetPrank(users.yieldManager);

        vm.assume(fee >= 0);
        vm.assume(fee < 10000);
        vm.assume(slippage >= 0);
        vm.assume(slippage < 10000);
        vm.assume(validity < 10000);
        vm.deal(users.yieldManager, 1 ether);

        // Mock first order calls
        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(0), uint256(0), uint256(block.timestamp - 500), uint80(0))
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.OraclePriceInvalid.selector, 0));
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(fee, slippage, validity);

        // Mock first order calls
        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(-1), uint256(0), uint256(block.timestamp - 500), uint80(0))
        );

        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.OraclePriceInvalid.selector, -1));
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(fee, slippage, validity);
    }

    function test_RevertWhen_ThePriceDataIsOlderThan1hour(
        uint16 fee,
        uint16 slippage,
        uint32 validity
    )
        external
        whenTheCallerIsTheYieldManager
        whenTheValueIsNotZero
        whenTheFeeIsSmallerThanTheBpsDenominator
        whenTheSlippageIsSmallerThanTheBpsDenominator
        whenThereIsNoOpenOrderYet
        whenTheOraclePriceIsBiggerThanZero
    {
        resetPrank(users.yieldManager);

        vm.assume(fee >= 0);
        vm.assume(fee < 10000);
        vm.assume(slippage >= 0);
        vm.assume(slippage < 10000);
        vm.assume(validity < 10000);
        vm.deal(users.yieldManager, 1 ether);

        // Mock first order calls
        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(1 ether), uint256(0), uint256(block.timestamp - 3601), uint80(0))
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.StaleOracle.selector));
        ethToBoldRouter.swapExactEthForBold{ value: 1 ether }(fee, slippage, validity);
    }

    function test_WhenThePrice1hourOrLessOld(
        uint256 amount,
        uint16 fee,
        uint16 slippage,
        uint32 validity
    )
        external
        whenTheCallerIsTheYieldManager
        whenTheValueIsNotZero
        whenTheFeeIsSmallerThanTheBpsDenominator
        whenTheSlippageIsSmallerThanTheBpsDenominator
        whenThereIsNoOpenOrderYet
        whenTheOraclePriceIsBiggerThanZero
    {
        resetPrank(users.yieldManager);

        vm.assume(amount > 0);
        vm.assume(amount < type(uint128).max);
        vm.assume(fee >= 0);
        vm.assume(fee < 10000);
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

        ethToBoldRouter.swapExactEthForBold{ value: amount }(fee, slippage, validity);

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
