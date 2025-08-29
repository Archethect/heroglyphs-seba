// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { ISebaPool } from "src/interfaces/ISebaPool.sol";

contract SubscribeValidatorTest is BaseTest {
    function test_RevertWhen_TheValidatorRegistrationBlockIsNotZero() external {
        resetPrank(users.validator);
        // We subscribe a first time to set the registration block
        sebaPool.subscribeValidator(1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.ValidatorAlreadySubscribed.selector, 1));
        sebaPool.subscribeValidator(1);
    }

    function test_WhenTheValidatorRegistrationBlockIsZero() external {
        resetPrank(users.validator);

        // it should emit SubscribeValidator
        vm.expectEmit();
        emit ISebaPool.SubscribeValidator(users.validator, 1);
        sebaPool.subscribeValidator(1);

        // it should set the registration block to the current block
        assertEq(sebaPool.validatorRegistrationBlock(1), block.number, "SebaPool: invalid registration block");
    }
}
