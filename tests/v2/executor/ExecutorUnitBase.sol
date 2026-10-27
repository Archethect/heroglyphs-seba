// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { SebaV2Executor } from "src/v2/SebaV2Executor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import {
    ExecutorActor,
    ExecutorToken,
    ExecutorWeth,
    ExecutorReth,
    ExecutorYearn,
    ExecutorFeed,
    ExecutorRouter,
    ExecutorCurve,
    ExecutorRocketRegistry,
    ExecutorRocketBalances,
    ExecutorRocketSettings,
    ExecutorRocketPool
} from "./ExecutorMocks.sol";

abstract contract ExecutorUnitBase is Test {
    SebaV2Executor internal executor;
    ExecutorActor internal managerActor;
    ExecutorActor internal safe;
    ExecutorReth internal reth;
    ExecutorWeth internal weth;
    ExecutorToken internal usdc;
    ExecutorToken internal bold;
    ExecutorYearn internal yBold;
    ExecutorYearn internal ysy;
    ExecutorFeed internal ethFeed;
    ExecutorFeed internal usdcFeed;
    ExecutorRouter internal router;
    ExecutorCurve internal curve;
    ExecutorRocketRegistry internal registry;
    ExecutorRocketBalances internal reports;
    ExecutorRocketSettings internal settings;
    ExecutorRocketPool internal pool;

    function setUp() public {
        vm.warp(100_000);
        vm.roll(10_000);
        managerActor = new ExecutorActor();
        safe = new ExecutorActor();
        reth = new ExecutorReth();
        weth = new ExecutorWeth();
        usdc = new ExecutorToken(6);
        bold = new ExecutorToken(18);
        yBold = new ExecutorYearn(address(bold));
        ysy = new ExecutorYearn(address(yBold));
        ethFeed = new ExecutorFeed(3000e8);
        usdcFeed = new ExecutorFeed(1e8);
        router = new ExecutorRouter();
        curve = new ExecutorCurve(address(bold), address(usdc));
        registry = new ExecutorRocketRegistry();
        reports = new ExecutorRocketBalances();
        settings = new ExecutorRocketSettings();
        pool = new ExecutorRocketPool(reth, settings);
        registry.set("rocketNetworkBalances", address(reports));
        registry.set("rocketDepositPool", address(pool));
        registry.set("rocketDAOProtocolSettingsDeposit", address(settings));
        router.setRate(address(weth), address(usdc), 3000e6);
        router.setRate(address(reth), address(weth), 1.2e18);
        executor = new SebaV2Executor(_config());
        vm.deal(address(managerActor), 1e30);
        reth.mint(address(managerActor), 1e30);
        ysy.mint(address(managerActor), 1e30);
        vm.startPrank(address(managerActor));
        reth.approve(address(executor), type(uint256).max);
        ysy.approve(address(executor), type(uint256).max);
        vm.stopPrank();
    }

    function _config() internal view returns (IV2Executor.Config memory c) {
        c = IV2Executor.Config(
            address(managerActor),
            address(safe),
            address(reth),
            address(weth),
            address(usdc),
            address(bold),
            address(yBold),
            address(ysy),
            address(router),
            address(curve),
            address(ethFeed),
            address(usdcFeed),
            address(registry)
        );
    }
    function _limits() internal view returns (IV2Executor.Limits memory l) {
        l = IV2Executor.Limits(
            1e30,
            1e30,
            1e30,
            1e16,
            3600,
            82800,
            90000,
            8000,
            900,
            50,
            100,
            500,
            100,
            address(pool),
            address(reports),
            address(settings)
        );
    }
    function _enable() internal {
        vm.startPrank(address(safe));
        executor.configureLimits(_limits());
        executor.setEnabled(true);
        vm.stopPrank();
    }
    function _execute(uint8 route, uint256 amount, uint256 minimum, uint256 deadline) internal returns (uint256) {
        vm.prank(address(managerActor));
        if (route == 0) return executor.investReth{ value: amount }(minimum, deadline);
        if (route == 1) return executor.investYsyBold{ value: amount }(minimum, deadline);
        if (route == 2) return executor.convertEthToBold{ value: amount }(minimum, deadline);
        if (route == 3) return executor.convertRethToBold(amount, minimum, deadline);
        return executor.convertYsyToBold(amount, minimum, deadline);
    }
    function _expect(uint8 route, bytes4 reason) internal {
        vm.expectRevert(reason);
        _execute(route, 1e18, 1, block.timestamp + 60);
    }
}
