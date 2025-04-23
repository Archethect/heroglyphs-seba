// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";

contract WithdrawTest is BaseTest {
    function test_RevertWhen_NotTheYieldManager(address caller) external {
        vm.assume(contracts.yieldManager != caller);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDripVault.NotYieldManager.selector));
        apxETHVault.withdraw(contracts.yieldManager, 1 ether);
    }

    function test_WhenTheYieldManager() external {
        vm.deal(contracts.yieldManager, 1 ether);

        resetPrank(contracts.yieldManager);
        apxETHVault.deposit{ value: 1 ether }();

        assertEq(apxETH.balanceOf(users.admin), 0 ether, "admin balance is not 0 ether");
        assertEq(apxETHVault.getTotalDeposit(), 0.99 ether, "total deposit is not correct");

        // 1% fee
        uint256 result = apxETHVault.withdraw(users.admin, 0.99 ether);

        // it should transfer the amount in apxETH shares to the receiver
        assertEq(apxETH.balanceOf(users.admin), 0.99 ether, "admin balance is not 0.99 ether");
        // it should remove the amount from the total deposits
        assertEq(apxETHVault.getTotalDeposit(), 0 ether, "total deposit is not correct");
        // it should return the withdrawn amount in apxETH shares
        assertEq(result, 0.99 ether, "result is not correct");
    }
}
