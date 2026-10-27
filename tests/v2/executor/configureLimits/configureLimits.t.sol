// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";

import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";

contract ExecutorConfigureLimitsTest is ExecutorUnitBase {
    function test_configurationAndActivationAreSafeOnlyAndSeparate() public {
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        executor.configureLimits(_limits());
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        executor.setEnabled(true);
        vm.prank(address(safe));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        executor.setEnabled(true);
        vm.prank(address(safe));
        executor.setEnabled(false);
        _enable();
        vm.prank(address(safe));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        executor.configureLimits(_limits());
        vm.prank(address(safe));
        executor.setEnabled(false);
        vm.prank(address(safe));
        executor.configureLimits(_limits());
        _expect(2, IV2Executor.ExecutionDisabled.selector);
        assertEq(executor.configuration().manager, address(managerActor));
        assertEq(executor.manager(), address(managerActor));
        assertEq(executor.treasury(), address(safe));
        assertEq(executor.limits().maxEth, 1e30);
    }

    function test_invalidLimitsFailClosed() public {
        for (uint256 i; i < 16; ++i) {
            IV2Executor.Limits memory l = _limits();
            if (i == 0) l.maxEth = 0;
            else if (i == 1) l.maxReth = 0;
            else if (i == 2) l.maxYsy = 0;
            else if (i == 3) l.maxMintFeeWad = 1e18;
            else if (i == 4) l.ethMaxAge = 0;
            else if (i == 5) l.usdcMaxAge = 0;
            else if (i == 6) l.reportMaxAge = 0;
            else if (i == 7) l.reportMaxBlockLag = 0;
            else if (i == 8) l.maxDeadline = 0;
            else if (i == 9) l.slippageBps = 10_000;
            else if (i == 10) l.pegBps = 10_000;
            else if (i == 11) l.wethUsdcFee = 0;
            else if (i == 12) l.rethWethFee = 0;
            else if (i == 13) l.depositPool = address(1);
            else if (i == 14) l.networkBalances = address(1);
            else l.depositSettings = address(1);
            vm.prank(address(safe));
            vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
            executor.configureLimits(l);
        }
    }
}
