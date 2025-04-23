// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";

contract DepositTest is BaseTest {
    function test_RevertWhen_NotTheYieldManager(address caller) external {
        vm.assume(contracts.yieldManager != caller);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDripVault.NotYieldManager.selector));
        hoax(caller, 1 ether);
        apxETHVault.deposit{ value: 1 ether }();
    }

    function test_RevertWhen_TheValueIsZero() external whenTheYieldManager {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDripVault.InvalidAmount.selector));
        apxETHVault.deposit();
    }

    function test_WhenTheValueIsNotZero() external whenTheYieldManager {
        vm.deal(contracts.yieldManager, 1 ether);
        uint256 result = apxETHVault.deposit{ value: 1 ether }();
        // fee = 1%
        uint256 fee = 1 ether / 100;

        // it should add the value to total deposit and subtract the pirex fee
        assertEq(apxETHVault.getTotalDeposit(), 1 ether - fee, "total deposit is not correct");
        // it should deposit the value to pirexETH
        assertEq(contracts.yieldManager.balance, 0, "yield manager balance is not 0");
        assertEq(contracts.pirexETH.balance, 1 ether, "pirexETH balance is not 1 ether");
        // it should return the deposited amount subtracted with the fee
        assertEq(result, 1 ether - fee, "result is not correct");
    }
}
