// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";

contract DepositFundsTest is BaseTest {
    function test_GivenTheDepositorIsTheBoostpool() external {
        resetPrank(contracts.boostPool);
        vm.deal(contracts.boostPool, 1 ether);

        // it should emit FundsDeposited
        vm.expectEmit();
        emit IYieldManager.FundsDeposited(0, contracts.yieldManager, 0.99 ether);
        yieldManager.depositFunds{ value: 1 ether }();

        // it should correctly add the amount to the yieldmanager deposit object
        (uint32 lockedUntil, uint128 amount, address depositor) = yieldManager.deposits(0);
        assertEq(amount, 0.99 ether, "amount is not correct");
        assertEq(lockedUntil, 0, "lockedUntil is not correct");
        assertEq(depositor, contracts.yieldManager, "depositor is not correct");
        // it should deposit the amount to the apxEthVault
        assertEq(apxETHVault.getTotalDeposit(), 0.99 ether, "total deposit is not correct");
        assertEq(contracts.pirexETH.balance, 1 ether, "pirexETH balance is not correct");
    }

    function test_GivenTheDepositorIsNotTheBoostpool() external {
        resetPrank(users.admin);
        vm.deal(users.admin, 1 ether);

        // it should emit FundsDeposited
        vm.expectEmit();
        emit IYieldManager.FundsDeposited(1, users.admin, 0.99 ether);
        yieldManager.depositFunds{ value: 1 ether }();

        // it should create a new deposit object
        (uint32 lockedUntil, uint128 amount, address depositor) = yieldManager.deposits(1);
        assertEq(amount, 0.99 ether, "amount is not correct");
        assertEq(lockedUntil, block.timestamp + yieldManager.DEPOSIT_LOCK_DURATION(), "lockedUntil is not correct");
        assertEq(depositor, users.admin, "depositor is not correct");
        // it should increase the depositId
        assertEq(yieldManager.depositId(), 1, "depositId is not correct");
        // it should deposit the amount to the apxEthVault
        assertEq(apxETHVault.getTotalDeposit(), 0.99 ether, "total deposit is not correct");
        assertEq(contracts.pirexETH.balance, 1 ether, "pirexETH balance is not correct");
    }
}
