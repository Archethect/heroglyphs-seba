// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ExecutorUnitBase } from "../../../executor/ExecutorUnitBase.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";

contract CowDirectExecutorTestInvestRethTest is CowDirectExecutorTestBase {
    function test_RocketRegistryReportsFeesCapacityAndFloorFailClosed() public {
        _enableDirect();
        registry.set("rocketNetworkBalances", address(safe));
        _fail(0, IV2Executor.RegistryChanged.selector);
        registry.set("rocketNetworkBalances", address(reports));
        registry.set("rocketDepositPool", address(safe));
        _fail(0, IV2Executor.RegistryChanged.selector);
        registry.set("rocketDepositPool", address(pool));
        registry.set("rocketDAOProtocolSettingsDeposit", address(safe));
        _fail(0, IV2Executor.RegistryChanged.selector);
        registry.set("rocketDAOProtocolSettingsDeposit", address(settings));
        reports.set(0, block.number);
        _fail(0, IV2Executor.InvalidOracle.selector);
        reports.set(block.timestamp + 1, block.number);
        _fail(0, IV2Executor.InvalidOracle.selector);
        reports.set(block.timestamp, 0);
        _fail(0, IV2Executor.InvalidOracle.selector);
        reports.set(block.timestamp, block.number + 1);
        _fail(0, IV2Executor.InvalidOracle.selector);
        reports.set(block.timestamp - 90001, block.number);
        _fail(0, IV2Executor.StaleOracle.selector);
        reports.set(block.timestamp, block.number - 8001);
        _fail(0, IV2Executor.StaleOracle.selector);
        reports.set(block.timestamp - 90000, block.number - 8000);
        settings.set(1e16 + 1);
        _fail(0, IV2Executor.MintFeeExceeded.selector);
        settings.set(5e14);
        pool.set(1, 10000);
        _fail(0, IV2Executor.InvalidExecution.selector);
        pool.set(type(uint256).max, 9999);
        _fail(0, IV2Executor.InsufficientOutput.selector);
        pool.set(type(uint256).max, 10000);
        vm.expectRevert(IV2Executor.InsufficientOutput.selector);
        _run(0, 1 ether, 1 ether, block.timestamp);
        assertGt(_run(0, 1 ether, 1, block.timestamp), 0);
    }

    function test_AllDirectRoutesRejectInvalidBoundsThenConserveDustAndClearApprovals() public {
        for (uint8 r; r < 3; ++r) _fail(r, IV2Executor.ExecutionDisabled.selector);
        _enableDirect();
        vm.deal(address(this), 1 ether);
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        direct.investReth{ value: 1 }(1, block.timestamp);
        vm.deal(address(managerActor), 2e30);
        for (uint8 r; r < 3; ++r) {
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _run(r, 0, 1, block.timestamp);
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _run(r, 1 ether, 0, block.timestamp);
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _run(r, 1 ether, 1, block.timestamp - 1);
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _run(r, 1 ether, 1, block.timestamp + 901);
            vm.expectRevert(IV2Executor.InvalidExecution.selector);
            _run(r, 1e30 + 1, 1, block.timestamp);
            bold.mint(address(direct), 123);
            yBold.mint(address(direct), 123);
            ysy.mint(address(direct), 123);
            assertGt(_run(r, 1 ether, 1, block.timestamp), 0);
            assertEq(bold.balanceOf(address(direct)), 123 * (uint256(r) + 1));
            assertEq(yBold.balanceOf(address(direct)), 123 * (uint256(r) + 1));
            assertEq(ysy.balanceOf(address(direct)), 123 * (uint256(r) + 1));
            assertEq(bold.allowance(address(direct), address(yBold)), 0);
            assertEq(yBold.allowance(address(direct), address(ysy)), 0);
        }
    }
}
