// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";

contract RunBoldConversionTest is BaseTest {
    function test_WhenThereIsAnOpenRouterIntent() external whenTheConversionTimeoutIsFinished {
        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        yieldManager.runBoldConversion(0);

        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        assertEq(yieldManager.pendingBoldConversion(), 0.5 ether);
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0xf7b86a67314fdc9a0d22fbc714addf0f0a903707b91730aa4db7aeaa43d7f2b7)
        );

        vm.warp(block.timestamp + yieldManager.ROUTER_VALIDITY_SECS() + 1);
        yieldManager.runBoldConversion(0);
        // it should finalize the intent and reset the activeRouterId when a new one is instantiated
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x429c536f31a76734ac14a3614fc922e5039db97414991bc64103447b431ccd87)
        );
        // it should set the correct pendingBoldConversion
        assertEq(yieldManager.pendingBoldConversion(), 0);
    }

    function test_WhenTheBoldBalanceInTheContractIsBiggerThan0() external whenTheConversionTimeoutIsFinished {
        deal(address(bold), contracts.yieldManager, 1 ether);

        // it should emit BoldConversionFinalised
        vm.expectEmit();
        emit IYieldManager.BoldConversionFinalised(1 ether, 986249800864924383);
        yieldManager.runBoldConversion(0);

        // it should convert the bold to sBOLD and topup the sebaVault
        assertEq(bold.balanceOf(contracts.yieldManager), 0);
        assertEq(bold.balanceOf(contracts.pybSeba), 0);
        assertEq(IERC20(contracts.sBOLD).balanceOf(contracts.yieldManager), 0);
        assertEq(IERC20(contracts.sBOLD).balanceOf(contracts.pybSeba), 986249800864924383);
    }

    function test_WhenThePendingPendingBoldConversionIsBiggerThan0AndTheFeeAmountIsNotBiggerThan10PercentOfTheConversionAmount() external whenTheConversionTimeoutIsFinished {
        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        yieldManager.runBoldConversion(0);

        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        assertEq(yieldManager.pendingBoldConversion(), 0.5 ether);
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0xf7b86a67314fdc9a0d22fbc714addf0f0a903707b91730aa4db7aeaa43d7f2b7)
        );

        vm.warp(block.timestamp + yieldManager.ROUTER_VALIDITY_SECS() + 1);

        // simulate 10% fee (should not create the intent)
        yieldManager.runBoldConversion(0.1 ether);
        assertEq(yieldManager.pendingBoldConversion(), 1 ether);


        vm.warp(block.timestamp + yieldManager.ROUTER_VALIDITY_SECS() + 1);
        mockAndExpectCall(contracts.ethUsdFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(129127208515966878730, 437862922915, 1756800029, 1756800047 + yieldManager.ROUTER_VALIDITY_SECS(), 129127208515966878730));

        // it should emit BoldConversionStarted
        vm.expectEmit();
        emit IYieldManager.BoldConversionStarted(
        0x429c536f31a76734ac14a3614fc922e5039db97414991bc64103447b431ccd87,
            1 ether
        );
        yieldManager.runBoldConversion(0);
        // it should set the activeRouterUid
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x429c536f31a76734ac14a3614fc922e5039db97414991bc64103447b431ccd87)
        );
        // it should reset the pendingBoldConversion
        assertEq(yieldManager.pendingBoldConversion(), 0);
    }
}
