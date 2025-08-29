// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { ISebaPool } from "src/interfaces/ISebaPool.sol";

contract SubscribeValidatorsTest is BaseTest {
    function test_RevertWhen_TheValidatorRegistrationBlockIsNotZero() external {
        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        resetPrank(users.validator);
        // We subscribe a first time to set the registration block
        sebaPool.subscribeValidators(validatorIds);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.ValidatorAlreadySubscribed.selector, 1));
        sebaPool.subscribeValidators(validatorIds);
    }

    function test_WhenTheValidatorRegistrationBlockIsZero() external {
        resetPrank(users.validator);

        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        // it should emit SubscribeValidator
        vm.expectEmit();
        emit ISebaPool.SubscribeValidator(users.validator, 1);
        emit ISebaPool.SubscribeValidator(users.validator, 2);
        sebaPool.subscribeValidators(validatorIds);

        // it should set the registration block to the current block
        assertEq(sebaPool.validatorRegistrationBlock(1), block.number, "SebaPool: invalid registration block");
        assertEq(sebaPool.validatorRegistrationBlock(2), block.number, "SebaPool: invalid registration block");
    }
}
