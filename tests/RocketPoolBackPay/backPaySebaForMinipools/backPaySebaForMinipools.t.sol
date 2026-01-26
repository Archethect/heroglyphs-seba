// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IRocketPoolBackPay } from "src/interfaces/IRocketPoolBackPay.sol";
import { RocketPoolBackPay } from "src/RocketPoolBackPay.sol";
import { Noop } from "src/mocks/Noop.sol";

contract BackPaySebaForMinipoolsTest is BaseTest {
    function test_RevertWhen_NotTheCorrectArrayLength() external {
        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        uint256[] memory payments = new uint256[](1);
        payments[0] = 1;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IRocketPoolBackPay.InvalidArrayLength.selector));
        rocketPoolBackPay.backPaySebaForMinipools(validatorIds,payments);
    }

    function test_RevertWhen_TheCorrectAmountIsNotPaid() external whenTheCorrectArrayLength {
        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        uint256[] memory payments = new uint256[](2);
        payments[0] = 1 ether;
        payments[1] = 1 ether;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IRocketPoolBackPay.InvalidTotalBackPay.selector, 2 ether, 1.9 ether));
        rocketPoolBackPay.backPaySebaForMinipools{value: 1.9 ether}(validatorIds,payments);
    }

    function test_RevertWhen_TransferingThePaymentToTheSebaPoolFails()
        external
        whenTheCorrectArrayLength
        whenTheCorrectAmountIsPaid
    {
        Noop noop = new Noop();
        RocketPoolBackPay localRocketPoolBackPay = new RocketPoolBackPay(address(noop));

        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        uint256[] memory payments = new uint256[](2);
        payments[0] = 1 ether;
        payments[1] = 1 ether;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IRocketPoolBackPay.TransferFailed.selector));
        localRocketPoolBackPay.backPaySebaForMinipools{value: 2 ether}(validatorIds,payments);
    }

    function test_WhenTransferingThePaymentToTheSebapoolSucceeds()
        external
        whenTheCorrectArrayLength
        whenTheCorrectAmountIsPaid
    {
        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        uint256[] memory payments = new uint256[](2);
        payments[0] = 1 ether;
        payments[1] = 2 ether;

        assertEq(contracts.sebaPool.balance, 0);

        // it should emit BackPayMinipool
        vm.expectEmit();
        emit IRocketPoolBackPay.BackPayMinipool(address(this), 1, 1 ether, block.number);
        emit IRocketPoolBackPay.BackPayMinipool(address(this), 2, 2 ether, block.number);
        rocketPoolBackPay.backPaySebaForMinipools{value: 3 ether}(validatorIds,payments);

        // it should set the correct back paid amount per minipool
        assertEq(rocketPoolBackPay.backPayPerMiniPool(1), 1 ether);
        assertEq(rocketPoolBackPay.backPayPerMiniPool(2), 2 ether);
        // it should send the correct payment amount to the seba pool
        assertEq(contracts.sebaPool.balance, 3 ether, "RocketPoolBackPay: It should send the correct amount to the SebaPool");
    }
}
