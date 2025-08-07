// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";

contract RetrieveFundsTest is BaseTest {
    function test_RevertWhen_TheSenderIsNotAnAdmin(address caller) external whenTheDepositorIsTheYieldManager {
        vm.assume(caller != users.admin);
        assumeNotZeroAddress(caller);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidDepositor.selector, caller));
        resetPrank(caller);
        yieldManager.retrieveFunds(0);
    }

    function test_WhenTheSenderIsAnAdmin() external whenTheDepositorIsTheYieldManager {
        resetPrank(contracts.boostPool);
        vm.deal(contracts.boostPool, 1 ether);
        yieldManager.depositFunds{ value: 1 ether }();

        resetPrank(users.admin);

        // it should emit FundsRetrieved
        vm.expectEmit();
        emit IYieldManager.FundsRetrieved(0, users.admin, 0.99 ether);
        yieldManager.retrieveFunds(0);

        // it should delete the deposit object
        (uint32 lockedUntil, uint128 amount, address depositor) = yieldManager.deposits(0);
        assertEq(lockedUntil, 0, "lockedUntil is not correct");
        assertEq(amount, 0, "amount is not correct");
        assertEq(depositor, address(0), "depositor is not correct");
        // it should withdraw the deposited amount to the sender
        assertEq(apxETH.balanceOf(users.admin), 0.99 ether, "admin balance is not correct");
    }

    function test_RevertWhen_TheSenderIsNotTheDepositor() external whenTheDepositorIsNotTheYieldManager {
        resetPrank(users.validator);
        vm.deal(users.validator, 1 ether);
        yieldManager.depositFunds{ value: 1 ether }();

        resetPrank(users.nonValidator);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.InvalidDepositor.selector, users.nonValidator));
        yieldManager.retrieveFunds(1);
    }

    function test_RevertWhen_TheDepositIsNotUnlockableYet()
        external
        whenTheDepositorIsNotTheYieldManager
        whenTheSenderIsTheDepositor
    {
        resetPrank(users.validator);
        vm.deal(users.validator, 1 ether);
        yieldManager.depositFunds{ value: 1 ether }();
        (uint64 lockedUntil, , ) = yieldManager.deposits(1);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IYieldManager.DepositStillLocked.selector, block.timestamp, lockedUntil)
        );
        yieldManager.retrieveFunds(1);
    }

    function test_WhenTheDepositIsUnlockabled()
        external
        whenTheDepositorIsNotTheYieldManager
        whenTheSenderIsTheDepositor
    {
        resetPrank(users.validator);
        vm.deal(users.validator, 1 ether);
        yieldManager.depositFunds{ value: 1 ether }();
        (uint64 lockedUntil, , ) = yieldManager.deposits(1);

        vm.warp(lockedUntil);

        // it should emit FundsRetrieved
        vm.expectEmit();
        emit IYieldManager.FundsRetrieved(1, users.validator, 0.99 ether);
        yieldManager.retrieveFunds(1);

        // it should delete the deposit object
        (uint64 newLockedUntil, uint128 newAmount, address newDepositor) = yieldManager.deposits(1);
        assertEq(newLockedUntil, 0, "lockedUntil is not correct");
        assertEq(newAmount, 0, "amount is not correct");
        assertEq(newDepositor, address(0), "depositor is not correct");
        // it should withdraw the deposited amount to the sender
        assertEq(apxETH.balanceOf(users.validator), 0.99 ether, "validator balance is not correct");
    }
}*/
