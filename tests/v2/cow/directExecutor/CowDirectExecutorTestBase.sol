// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ExecutorUnitBase } from "../../executor/ExecutorUnitBase.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
abstract contract CowDirectExecutorTestBase is ExecutorUnitBase {
    SebaV2DirectExecutor internal direct;
    function setUp() public override {
        super.setUp();
        direct = new SebaV2DirectExecutor(_directConfig());
        bold.mint(address(managerActor), 1e30);
        vm.startPrank(address(managerActor));
        bold.approve(address(direct), type(uint256).max);
        ysy.approve(address(direct), type(uint256).max);
        vm.stopPrank();
    }
    function _directConfig() internal view returns (IV2Executor.Config memory c) {
        c = _config();
        c.usdc = address(0);
        c.swapRouter = address(0);
        c.curvePool = address(0);
        c.ethUsdFeed = address(0);
        c.usdcUsdFeed = address(0);
    }
    function _directLimits() internal view returns (IV2Executor.Limits memory l) {
        l = _limits();
        l.ethMaxAge = 0;
        l.usdcMaxAge = 0;
        l.slippageBps = 0;
        l.pegBps = 0;
        l.wethUsdcFee = 0;
        l.rethWethFee = 0;
    }
    function _enableDirect() internal {
        vm.startPrank(address(safe));
        direct.configureLimits(_directLimits());
        direct.configureBoldLimit(1e30);
        direct.setEnabled(true);
        vm.stopPrank();
    }
    function _run(uint8 route, uint256 amount, uint256 minimum, uint256 deadline) internal returns (uint256) {
        vm.prank(address(managerActor));
        if (route == 0) return direct.investReth{ value: amount }(minimum, deadline);
        if (route == 1) return direct.investBold(amount, minimum, deadline);
        return direct.convertYsyToBold(amount, minimum, deadline);
    }
    function _fail(uint8 route, bytes4 reason) internal {
        vm.expectRevert(reason);
        _run(route, 1 ether, 1, block.timestamp);
    }
}
