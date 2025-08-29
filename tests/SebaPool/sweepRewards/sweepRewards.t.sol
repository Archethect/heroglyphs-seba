// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import {ISebaPool} from "src/interfaces/ISebaPool.sol";

contract SweepRewardsTest is BaseTest {
    function test_GivenFundsAreHigherThan0() external {
        vm.deal(contracts.sebaPool, 1 ether);

        resetPrank(users.admin);
        sebaPool.setYieldManager(contracts.mockSimpleYieldManager);
        uint256 preSweep = contracts.mockSimpleYieldManager.balance;

        // it should emit RewardsSwept
        vm.expectEmit();
        emit ISebaPool.RewardsSwept(1 ether, contracts.mockSimpleYieldManager);
        sebaPool.sweepRewards();

        // it should deposit the funds through the yield manager
        // YieldManager should hold the funds
        assertEq(contracts.mockSimpleYieldManager.balance - preSweep, 1 ether, "mockSimpleYieldManager should hold funds");
        assertEq(contracts.sebaPool.balance, 0, "sebaPool should not hold funds");
    }
}
