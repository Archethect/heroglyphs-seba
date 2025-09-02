// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";
import { Noop } from "../../../src/mocks/Noop.sol";

contract RetrieveFundsTest is BaseTest {
    function test_RevertWhen_TheDepositAmountIs0() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.NonExistingDeposit.selector, 0));
        yieldManager.retrieveFunds(0);
    }

    function test_RevertWhen_TheDepositorIsNotTheSender() external whenTheDepositAmountIsNotZero {
        vm.deal(users.admin, 1 ether);

        resetPrank(users.admin);
        yieldManager.depositFunds{ value: 1 ether }();

        resetPrank(users.nonValidator);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidDepositor.selector, users.nonValidator));
        yieldManager.retrieveFunds(1);
    }

    function test_RevertWhen_TheUnlockTimeHasNotBeenReached()
        external
        whenTheDepositAmountIsNotZero
        whenTheDepositorIsTheSender
    {
        vm.deal(users.admin, 1 ether);

        resetPrank(users.admin);
        yieldManager.depositFunds{ value: 1 ether }();

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldManager.DepositStillLocked.selector,
                block.timestamp,
                block.timestamp + yieldManager.USER_LOCK_SECS()
            )
        );
        yieldManager.retrieveFunds(1);
    }

    function test_RevertWhen_TheTransferOfTheFundsToTheReceiverFails()
        external
        whenTheDepositAmountIsNotZero
        whenTheDepositorIsTheSender
        whenTheUnlockTimeHasBeenReached
    {
        Noop noop = new Noop();
        vm.deal(address(noop), 1 ether);

        resetPrank(address(noop));
        yieldManager.depositFunds{ value: 1 ether }();
        vm.warp(block.timestamp + yieldManager.USER_LOCK_SECS());

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.TransferFailed.selector));
        yieldManager.retrieveFunds(1);
    }

    function test_WhenTheTransferOfTheFundsToTheReceiverSucceeds()
        external
        whenTheDepositAmountIsNotZero
        whenTheDepositorIsTheSender
        whenTheUnlockTimeHasBeenReached
    {
        vm.deal(users.admin, 1 ether);

        resetPrank(users.admin);
        yieldManager.depositFunds{ value: 1 ether }();
        vm.warp(block.timestamp + yieldManager.USER_LOCK_SECS());

        // it should emit FundsRetrieved
        vm.expectEmit();
        emit IYieldManager.FundsRetrieved(1, users.admin, 998597841013762580);
        yieldManager.retrieveFunds(1);

        // it should delete the deposits object
        (address _depositor, IYieldVault _vaultAtDeposit, uint256 _amount, uint32 _unlockTime) = yieldManager.deposits(
            1
        );
        assertEq(_depositor, address(0));
        assertEq(address(_vaultAtDeposit), address(0));
        assertEq(_amount, 0);
        assertEq(_unlockTime, 0);
        // it should sent the funds back to the receiver
        assertEq(users.admin.balance, 998597841013762580);
    }
}
