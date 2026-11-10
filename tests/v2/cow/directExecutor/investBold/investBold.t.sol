// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ExecutorUnitBase } from "../../../executor/ExecutorUnitBase.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";

contract CowDirectExecutorTestInvestBoldTest is CowDirectExecutorTestBase {
    function test_BoldPrincipalUsesOnlyDirectYearnAndRespectsSeparateCap() public {
        IV2Executor.Config memory c = _config();
        c.usdc = address(0);
        c.swapRouter = address(0);
        c.curvePool = address(0);
        c.ethUsdFeed = address(0);
        c.usdcUsdFeed = address(0);
        direct = new SebaV2DirectExecutor(c);
        IV2Executor.Limits memory l = _limits();
        l.ethMaxAge = 0;
        l.usdcMaxAge = 0;
        l.slippageBps = 0;
        l.pegBps = 0;
        l.wethUsdcFee = 0;
        l.rethWethFee = 0;
        vm.startPrank(address(safe));
        direct.configureLimits(l);
        direct.configureBoldLimit(10 ether);
        direct.setEnabled(true);
        vm.stopPrank();
        uint256 initial = bold.balanceOf(address(managerActor));
        vm.startPrank(address(managerActor));
        bold.approve(address(direct), 20 ether);
        uint256 out = direct.investBold(10 ether, 1, block.timestamp);
        assertEq(ysy.balanceOf(address(managerActor)), 1e30 + out);
        assertEq(bold.balanceOf(address(managerActor)), initial - 10 ether);
        vm.expectRevert();
        direct.investBold(11 ether, 1, block.timestamp);
        vm.expectRevert();
        direct.convertEthToBold{ value: 1 ether }(1, block.timestamp);
        vm.expectRevert();
        direct.investYsyBold{ value: 1 ether }(1, block.timestamp);
        vm.expectRevert();
        direct.convertRethToBold(1, 1, block.timestamp);
        vm.stopPrank();
    }
}
