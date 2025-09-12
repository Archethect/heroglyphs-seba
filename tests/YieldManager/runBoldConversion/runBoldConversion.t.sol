// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";

contract RunBoldConversionTest is BaseTest {
    function test_WhenThereIsAnOpenRouterIntent() external whenTheConversionTimeoutIsFinished {
        resetPrank(users.automator);

        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        yieldManager.runBoldConversion(0);

        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        assertEq(yieldManager.pendingBoldConversion(), 0.5 ether);
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x55b60a88ba6f2a12bbda09394367a8dece72bffa2e135130b1f5a8d361444dbf)
        );

        vm.warp(block.timestamp + yieldManager.ROUTER_VALIDITY_SECS() + 1);
        yieldManager.runBoldConversion(0);
        // it should finalize the intent and reset the activeRouterId when a new one is instantiated
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x4b7c0e6047404cb902865aa3c39e63e0f016ebcdc3edc167934923c4b849c6c1)
        );
        // it should set the correct pendingBoldConversion
        assertEq(yieldManager.pendingBoldConversion(), 0);
    }

    function test_WhenTheBoldBalanceInTheContractIsBiggerThan0() external whenTheConversionTimeoutIsFinished {
        resetPrank(users.automator);

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

    function test_WhenThePendingPendingBoldConversionIsBiggerThan0() external whenTheConversionTimeoutIsFinished {
        resetPrank(users.automator);

        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        yieldManager.runBoldConversion(0);

        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        assertEq(yieldManager.pendingBoldConversion(), 0.5 ether);
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x55b60a88ba6f2a12bbda09394367a8dece72bffa2e135130b1f5a8d361444dbf)
        );

        vm.warp(block.timestamp + yieldManager.ROUTER_VALIDITY_SECS() + 1);

        // it should emit BoldConversionStarted
        vm.expectEmit();
        emit IYieldManager.BoldConversionStarted(
        0x4b7c0e6047404cb902865aa3c39e63e0f016ebcdc3edc167934923c4b849c6c1,
            1 ether
        );
        yieldManager.runBoldConversion(0);
        // it should set the activeRouterUid
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x4b7c0e6047404cb902865aa3c39e63e0f016ebcdc3edc167934923c4b849c6c1)
        );
        // it should reset the pendingBoldConversion
        assertEq(yieldManager.pendingBoldConversion(), 0);
    }
}
