// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";

contract DepositFundsTest is BaseTest {
    function test_RevertWhen_TheValueIs0() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.EmptyDeposit.selector));
        yieldManager.depositFunds();
    }

    function test_WhenTheSenderIsTheSebapool() external whenTheValueIsNotZero {
        vm.deal(contracts.sebaPool, 1 ether);

        // it should emit DepositReceived
        vm.expectEmit();
        emit IYieldManager.DepositReceived(contracts.sebaPool, 2172639421829858815529);
        sebaPool.sweepRewards();

        // it should set the correct pendingBoldConversion
        assertEq(yieldManager.pendingBoldConversion(), 0.5 ether);
        // it should set the correct principalValue
        assertEq(yieldManager.principalValue(), 2172639421829858815529);
        // it should deposit half of the value in the yieldvault
        assertEq(contracts.yieldManager.balance, 0.5 ether);
    }

    function test_WhenTheSenderIsNotTheSebapool() external whenTheValueIsNotZero {
        vm.deal(users.admin, 1 ether);

        vm.expectEmit();
        // it should emit DepositReceived
        emit IYieldManager.DepositReceived(users.admin, 4345209159833734480265);
        // it should emit FundsDeposited
        emit IYieldManager.FundsDeposited(1, users.admin, 1 ether);
        resetPrank(users.admin);
        yieldManager.depositFunds{ value: 1 ether }();

        // it should deposit the complete value in the yieldvault
        assertEq(contracts.yieldManager.balance, 0);
        // it should increase the depositId
        assertEq(yieldManager.depositId(), 1);
        // it should add a new deposit object
        (address _depositor, IYieldVault _vaultAtDeposit, uint256 _amount, uint32 _unlockTime) = yieldManager.deposits(
            1
        );
        assertEq(_depositor, users.admin);
        assertEq(address(_vaultAtDeposit), contracts.eUsdUsdcBeefyYieldVault);
        assertEq(_amount, 4345209159833734480265);
        assertEq(_unlockTime, block.timestamp + yieldManager.USER_LOCK_SECS());
    }
}
