// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";

import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";

contract ExecutorInvestYsyBoldTest is ExecutorUnitBase {
    function test_yearnDepositFailuresRevertEntireRoute() public {
        _enable();
        yBold.setBehavior(5000, 10000, 0);
        _expect(1, IV2Executor.PartialInput.selector);
        yBold.setBehavior(10000, 10000, 1);
        _expect(1, IV2Executor.UnexpectedTokenDelta.selector);
        yBold.setBehavior(10000, 9999, 0);
        _expect(1, IV2Executor.InsufficientOutput.selector);
        yBold.setBehavior(10000, 10000, 0);
        ysy.setRate(type(uint256).max);
        _expect(1, IV2Executor.InsufficientOutput.selector);
    }
}
