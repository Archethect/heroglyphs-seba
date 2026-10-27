// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";

import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";

contract ExecutorConvertYsyToBoldTest is ExecutorUnitBase {
    function test_directYsyRedemptionHasNoUsdCurveOrRocketDependency() public {
        _enable();
        ethFeed.set(0, 0, 0, 0, 0, 30);
        usdcFeed.set(0, 0, 0, 0, 0, 30);
        curve.setPeg(0);
        reports.set(0, 0);
        assertEq(_execute(4, 1e18, 1, block.timestamp), 1e18);
        assertEq(yBold.lastMaxLoss(), 0);
        assertEq(ysy.lastMaxLoss(), 0);
    }

    function test_yearnRedemptionFailuresAndNoLossWidening() public {
        _enable();
        ysy.setRedeemLimit(0);
        _expect(4, IV2Executor.InvalidExecution.selector);
        ysy.setRedeemLimit(type(uint256).max);
        ysy.setBehavior(5000, 10000, 0);
        _expect(4, IV2Executor.PartialInput.selector);
        ysy.setBehavior(10000, 10000, 1);
        _expect(4, IV2Executor.UnexpectedTokenDelta.selector);
        ysy.setBehavior(10000, 9999, 0);
        _expect(4, IV2Executor.InsufficientOutput.selector);
        ysy.setBehavior(10000, 10000, 0);
        ysy.setRate(0);
        _expect(4, IV2Executor.InsufficientOutput.selector);
    }

    function test_callerMinimumDoesNotSpendFundsOnFailure() public {
        _enable();
        uint256 beforeBalance = ysy.balanceOf(address(managerActor));
        vm.expectRevert(IV2Executor.InsufficientOutput.selector);
        _execute(4, 1e18, 1e18 + 1, block.timestamp);
        assertEq(ysy.balanceOf(address(managerActor)), beforeBalance);
    }
}
