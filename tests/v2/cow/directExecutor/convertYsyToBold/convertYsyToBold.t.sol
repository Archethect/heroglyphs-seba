// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ExecutorUnitBase } from "../../../executor/ExecutorUnitBase.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";

contract CowDirectExecutorTestConvertYsyToBoldTest is CowDirectExecutorTestBase {
    function test_YearnDepositAndRedeemCheckActualNotReportedAndNeverWidenLoss() public {
        _enableDirect();
        for (uint8 r = 1; r < 3; ++r) {
            ysy.setBehavior(5000, 10000, 0);
            _fail(r, IV2Executor.PartialInput.selector);
            ysy.setBehavior(10000, 10000, 1);
            _fail(r, IV2Executor.UnexpectedTokenDelta.selector);
            ysy.setBehavior(10000, 9999, 0);
            _fail(r, IV2Executor.InsufficientOutput.selector);
            ysy.setBehavior(10000, 10000, 0);
            vm.expectRevert(IV2Executor.InsufficientOutput.selector);
            _run(r, 1 ether, 1 ether + 1, block.timestamp);
        }
        ysy.setRedeemLimit(0);
        _fail(2, IV2Executor.InvalidExecution.selector);
        ysy.setRedeemLimit(type(uint256).max);
        ysy.setRate(0);
        _fail(2, IV2Executor.InsufficientOutput.selector);
        ysy.setRate(1e18);
        ysy.setRate(type(uint256).max);
        _fail(1, IV2Executor.InsufficientOutput.selector);
        ysy.setRate(1e18);
        bold.setFees(1, 0);
        _fail(1, IV2Executor.UnexpectedTokenDelta.selector);
        bold.setFees(0, 0);
        bold.setFees(0, 1);
        _fail(2, IV2Executor.UnexpectedTokenDelta.selector);
        bold.setFees(0, 0);
        assertEq(_run(2, 1 ether, 1, block.timestamp), 1 ether);
        assertEq(ysy.lastMaxLoss(), 0);
        assertEq(yBold.lastMaxLoss(), 0);
    }
}
