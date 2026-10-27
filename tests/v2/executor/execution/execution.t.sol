// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { ExecutorToken } from "../ExecutorMocks.sol";

import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";

contract ExecutorExecutionTest is ExecutorUnitBase {
    function test_allRoutesRejectUnauthorizedAndDisabled() public {
        for (uint8 i; i < 5; ++i) _expect(i, IV2Executor.ExecutionDisabled.selector);
        _enable();
        vm.deal(address(this), 1e18);
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        executor.investReth{ value: 1 }(1, block.timestamp);
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        executor.investYsyBold{ value: 1 }(1, block.timestamp);
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        executor.convertEthToBold{ value: 1 }(1, block.timestamp);
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        executor.convertRethToBold(1, 1, block.timestamp);
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        executor.convertYsyToBold(1, 1, block.timestamp);
    }

    function test_allRoutesRejectInvalidExecution() public {
        _enable();
        vm.deal(address(managerActor), 2e30);
        for (uint8 i; i < 5; ++i) {
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _execute(i, 0, 1, block.timestamp);
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _execute(i, 1e18, 0, block.timestamp);
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _execute(i, 1e18, 1, block.timestamp - 1);
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _execute(i, 1e18, 1, block.timestamp + 901);
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _execute(i, 1e30 + 1, 1, block.timestamp);
        }
    }

    function test_allTypedRoutesConserveInputsAndLeaveDustAndNoApprovals() public {
        _enable();
        address[6] memory tokens = [
            address(reth),
            address(weth),
            address(usdc),
            address(bold),
            address(yBold),
            address(ysy)
        ];
        for (uint256 i; i < 6; ++i) ExecutorToken(tokens[i]).mint(address(executor), 123);
        for (uint8 i; i < 5; ++i) {
            assertGt(_execute(i, 1e18, 1, block.timestamp + 60), 0);
            for (uint256 j; j < 6; ++j) {
                assertEq(IERC20(tokens[j]).balanceOf(address(executor)), 123);
                assertEq(IERC20(tokens[j]).allowance(address(executor), address(router)), 0);
                assertEq(IERC20(tokens[j]).allowance(address(executor), address(curve)), 0);
                assertEq(IERC20(tokens[j]).allowance(address(executor), address(yBold)), 0);
                assertEq(IERC20(tokens[j]).allowance(address(executor), address(ysy)), 0);
            }
        }
        assertEq(router.lastDeadline(), block.timestamp + 60);
        assertEq(address(executor).balance, 0);
    }

    function test_transferDeltaAndReentrancyDefenses() public {
        _enable();
        reth.setFees(1, 0);
        _expect(3, IV2Executor.UnexpectedTokenDelta.selector);
        reth.setFees(0, 0);
        bold.setFees(0, 1);
        _expect(2, IV2Executor.UnexpectedTokenDelta.selector);
        bold.setFees(0, 0);
        weth.setMintBps(9999);
        _expect(2, IV2Executor.UnexpectedTokenDelta.selector);
        weth.setMintBps(10000);
        router.setCallback(address(executor), abi.encodeCall(executor.convertEthToBold, (1, block.timestamp)));
        _expect(2, ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    }
}
