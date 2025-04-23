// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";

contract GetTotalDepositTest is BaseTest {
    function test_ShouldReturnTheTotalAmountOfDeposits() external {
        resetPrank(contracts.yieldManager);

        vm.deal(contracts.yieldManager, 5 ether);
        apxETHVault.deposit{ value: 2 ether }();
        apxETHVault.deposit{ value: 3 ether }();

        uint256 expectedTotalDeposit = 5 ether - ((5 ether * 0.01e18) / 1e18); // 1% fee

        // it should return the total amount of deposits
        assertEq(apxETHVault.getTotalDeposit(), expectedTotalDeposit, "total deposit is not correct");
    }
}
