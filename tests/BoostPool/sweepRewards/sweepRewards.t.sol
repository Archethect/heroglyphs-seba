// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IBoostPool } from "src/interfaces/IBoostPool.sol";

contract SweepRewardsTest is BaseTest {
    function test_GivenFundsAreHigherThan0() external {
        vm.deal(contracts.boostPool, 1 ether);

        // it should emit RewardsSwept
        vm.expectEmit();
        emit IBoostPool.RewardsSwept(1 ether, contracts.yieldManager);
        boostPool.sweepRewards();

        // it should deposit the funds through the yield manager
        //pirexETH should hold funds
        assertEq(contracts.pirexETH.balance, 1 ether, "pirexETH should hold funds");
        assertEq(contracts.boostPool.balance, 0, "boostPool should not hold funds");
    }
}
