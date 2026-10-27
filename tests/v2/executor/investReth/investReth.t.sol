// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";

import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";

contract ExecutorInvestRethTest is ExecutorUnitBase {
    function test_registryChangesFailClosed() public {
        _enable();
        registry.set("rocketNetworkBalances", address(safe));
        _expect(0, IV2Executor.RegistryChanged.selector);
        _expect(3, IV2Executor.RegistryChanged.selector);
        registry.set("rocketNetworkBalances", address(reports));
        registry.set("rocketDepositPool", address(safe));
        _expect(0, IV2Executor.RegistryChanged.selector);
        registry.set("rocketDepositPool", address(pool));
        registry.set("rocketDAOProtocolSettingsDeposit", address(safe));
        _expect(0, IV2Executor.RegistryChanged.selector);
    }

    function test_reportValidityAndFreshness() public {
        _enable();
        reports.set(0, block.number);
        _expect(0, IV2Executor.InvalidOracle.selector);
        reports.set(block.timestamp + 1, block.number);
        _expect(0, IV2Executor.InvalidOracle.selector);
        reports.set(block.timestamp, 0);
        _expect(0, IV2Executor.InvalidOracle.selector);
        reports.set(block.timestamp, block.number + 1);
        _expect(0, IV2Executor.InvalidOracle.selector);
        reports.set(block.timestamp - 90001, block.number);
        _expect(0, IV2Executor.StaleOracle.selector);
        reports.set(block.timestamp, block.number - 8001);
        _expect(3, IV2Executor.StaleOracle.selector);
        reports.set(block.timestamp - 90000, block.number - 8000);
        assertGt(_execute(0, 1e18, 1, block.timestamp), 0);
    }

    function test_rocketFeeCapacityAndIndependentMintMinimum() public {
        _enable();
        settings.set(1e16 + 1);
        _expect(0, IV2Executor.MintFeeExceeded.selector);
        settings.set(5e14);
        pool.set(1, 10000);
        _expect(0, IV2Executor.InvalidExecution.selector);
        pool.set(type(uint256).max, 9999);
        _expect(0, IV2Executor.InsufficientOutput.selector);
        pool.set(type(uint256).max, 10000);
        vm.expectRevert(IV2Executor.InsufficientOutput.selector);
        _execute(0, 1e18, 1e18, block.timestamp);
    }

    function testFuzz_mintFeeWholeApprovedDomain(uint256 maximum, uint256 fee, uint256 amount) public {
        IV2Executor.Limits memory l = _limits();
        l.maxMintFeeWad = bound(maximum, 0, 1e18 - 1);
        fee = bound(fee, 0, l.maxMintFeeWad);
        amount = bound(amount, 1e18, 1e24);
        settings.set(fee);
        vm.startPrank(address(safe));
        executor.configureLimits(l);
        executor.setEnabled(true);
        vm.stopPrank();
        uint256 expected = reth.getRethValue(amount - (amount * fee) / 1e18);
        if (expected == 0) {
            vm.expectRevert(IV2Executor.InsufficientOutput.selector);
            _execute(0, amount, 1, block.timestamp);
        } else assertEq(_execute(0, amount, 1, block.timestamp), expected);
    }
}
