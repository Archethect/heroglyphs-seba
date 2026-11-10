// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ExecutorUnitBase } from "../../../executor/ExecutorUnitBase.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";

contract CowDirectExecutorTestConfigureLimitsTest is CowDirectExecutorTestBase {
    function test_ConfigurationIsSafeOnlyDisabledAndHasNoOracleOrDexSettings() public {
        IV2Executor.Limits memory l = _directLimits();
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        direct.configureLimits(l);
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        direct.configureBoldLimit(1);
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        direct.setEnabled(true);
        vm.startPrank(address(safe));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        direct.setEnabled(true);
        direct.configureLimits(l);
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        direct.setEnabled(true);
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        direct.configureBoldLimit(0);
        for (uint8 i; i < 16; ++i) {
            l = _directLimits();
            if (i == 0) l.maxEth = 0;
            else if (i == 1) l.maxYsy = 0;
            else if (i == 2) l.maxMintFeeWad = 1e18;
            else if (i == 3) l.reportMaxAge = 0;
            else if (i == 4) l.reportMaxBlockLag = 0;
            else if (i == 5) l.maxDeadline = 0;
            else if (i == 6) l.ethMaxAge = 1;
            else if (i == 7) l.usdcMaxAge = 1;
            else if (i == 8) l.slippageBps = 1;
            else if (i == 9) l.pegBps = 1;
            else if (i == 10) l.wethUsdcFee = 1;
            else if (i == 11) l.rethWethFee = 1;
            else if (i == 12) l.depositPool = address(0);
            else if (i == 13) l.networkBalances = address(0);
            else if (i == 14) l.depositSettings = address(0);
            else {
                direct.configureBoldLimit(1);
                direct.setEnabled(true);
            }
            vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
            direct.configureLimits(l);
        }
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        direct.configureBoldLimit(2);
        direct.setEnabled(false);
        vm.stopPrank();
        assertEq(abi.encode(direct.configuration()), abi.encode(_directConfig()));
        assertEq(abi.encode(direct.limits()), abi.encode(_directLimits()));
        assertEq(direct.manager(), address(managerActor));
        assertEq(direct.treasury(), address(safe));
        assertFalse(direct.enabled());
    }
}
