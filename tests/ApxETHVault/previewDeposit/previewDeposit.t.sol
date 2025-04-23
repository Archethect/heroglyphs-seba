// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";

contract PreviewDepositTest is BaseTest {
    function test_ReturnsTheAmountThatWillBeDepositedTakingTheFeeIntoAccount(uint256 amount) external {
        vm.assume(amount < (type(uint256).max / 0.01e18));
        uint256 expectedTotalDeposit = amount - ((amount * 0.01e18) / 1e18); // 1% fee

        // it returns the amount that will be deposited, taking the fee into account
        assertEq(apxETHVault.previewDeposit(amount), expectedTotalDeposit, "total deposit is not correct");
    }
}
