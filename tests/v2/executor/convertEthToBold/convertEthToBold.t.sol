// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";

import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";

contract ExecutorConvertEthToBoldTest is ExecutorUnitBase {
    function test_oracleRoundValidationAndFreshness() public {
        _enable();
        for (uint256 i; i < 9; ++i) {
            uint80 r = 1;
            int256 a = 3000e8;
            uint256 s = block.timestamp;
            uint256 u = s;
            uint80 ar = 1;
            uint8 d = 8;
            if (i == 0) r = 0;
            else if (i == 1) a = 0;
            else if (i == 2) a = -1;
            else if (i == 3) s = 0;
            else if (i == 4) u = s - 1;
            else if (i == 5) u = s + 1;
            else if (i == 6) ar = 0;
            else if (i == 7) d = 19;
            else {
                s -= 3601;
                u = s;
            }
            ethFeed.set(r, a, s, u, ar, d);
            _expect(2, i == 8 ? IV2Executor.StaleOracle.selector : IV2Executor.InvalidOracle.selector);
        }
        ethFeed.set(1, 3000e8, block.timestamp - 3600, block.timestamp - 3600, 1, 8);
        assertGt(_execute(2, 1e18, 1, block.timestamp), 0);
        usdcFeed.set(1, 1e8, 1, 1, 1, 8);
        _expect(2, IV2Executor.StaleOracle.selector);
    }

    function test_pegAndIndependentOutputFloors() public {
        _enable();
        usdcFeed.set(1, 102e6, block.timestamp, block.timestamp, 1, 8);
        _expect(2, IV2Executor.PegExceeded.selector);
        usdcFeed.set(1, 1e8, block.timestamp, block.timestamp, 1, 8);
        curve.setPeg(98e16);
        _expect(2, IV2Executor.PegExceeded.selector);
        curve.setPeg(0);
        _expect(2, IV2Executor.PegExceeded.selector);
        curve.setPeg(1005e15);
        assertGt(_execute(2, 1e18, 1, block.timestamp), 0);
        curve.setPeg(995e15);
        assertGt(_execute(2, 1e18, 1, block.timestamp), 0);
        vm.expectRevert(IV2Executor.InsufficientOutput.selector);
        _execute(2, 1, 1, block.timestamp);
        reth.setRate(0);
        _expect(3, IV2Executor.InsufficientOutput.selector);
    }

    function test_curvePegIsUsdNormalizedAndUsesTheCorrectInverse() public {
        _enable();
        // Curve reports BOLD per USDC. Each leg alone is within 1%, but combined BOLD/USD is above 1.01.
        usdcFeed.set(1, 100_500_000, block.timestamp, block.timestamp, 1, 8);
        curve.setPeg(995e15);
        _expect(2, IV2Executor.PegExceeded.selector);
    }

    function test_swapFailuresRevertEntireRouteAndPreserveManagerFunds() public {
        _enable();
        uint256 beforeEth = address(managerActor).balance;
        router.setBehavior(5000, 10000, 0);
        _expect(2, IV2Executor.PartialInput.selector);
        router.setBehavior(10000, 10000, 1);
        _expect(2, IV2Executor.UnexpectedTokenDelta.selector);
        router.setBehavior(10000, 9000, 0);
        _expect(2, IV2Executor.InsufficientOutput.selector);
        assertEq(address(managerActor).balance, beforeEth);
        assertEq(IERC20(address(weth)).balanceOf(address(executor)), 0);
    }

    function test_curveFailuresRevertEntireRoute() public {
        _enable();
        curve.setBehavior(5000, 10000, 0);
        _expect(2, IV2Executor.PartialInput.selector);
        curve.setBehavior(10000, 10000, 1);
        _expect(2, IV2Executor.UnexpectedTokenDelta.selector);
        curve.setBehavior(10000, 9000, 0);
        _expect(2, IV2Executor.InsufficientOutput.selector);
    }

    function testFuzz_slippagePegAndAmountBounds(uint16 slip, uint16 peg, uint256 amount) public {
        IV2Executor.Limits memory l = _limits();
        l.slippageBps = uint16(bound(slip, 0, 9999));
        l.pegBps = uint16(bound(peg, 0, 9999));
        vm.startPrank(address(safe));
        executor.configureLimits(l);
        executor.setEnabled(true);
        vm.stopPrank();
        amount = bound(amount, 1e10, 1e24);
        uint256 beforeBalance = bold.balanceOf(address(managerActor));
        uint256 independentMinimum = (((amount * 3000e6) / 1e18) * (10_000 - l.slippageBps)) / 10_000;
        if (independentMinimum == 0) {
            vm.expectRevert(IV2Executor.InsufficientOutput.selector);
            _execute(2, amount, 1, block.timestamp + 900);
            assertEq(bold.balanceOf(address(managerActor)), beforeBalance);
            return;
        }
        uint256 out = _execute(2, amount, 1, block.timestamp + 900);
        assertEq(bold.balanceOf(address(managerActor)) - beforeBalance, out);
        assertEq(address(executor).balance, 0);
    }
}
