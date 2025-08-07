// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IBoostPool } from "src/interfaces/IBoostPool.sol";

contract SubscribeValidatorsTest is BaseTest {
    function test_RevertWhen_SenderIsNotPoapOwner() external {
        vm.prank(users.admin);
        // Poap receiver != validator
        poap.createPoap(users.nonValidator, "", 175498);
        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.NonEligibleStaker.selector, users.validator, 1));
        vm.prank(users.validator);
        boostPool.subscribeValidators(validatorIds);
    }

    function test_RevertWhen_PoapIsNotFromStakersUnion() external whenSenderIsPoapOwner {
        vm.prank(users.admin);
        // Poap eventId != Stakers Union
        poap.createPoap(users.validator, "", 1);
        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.NonEligibleStaker.selector, users.validator, 1));
        vm.prank(users.validator);
        boostPool.subscribeValidators(validatorIds);
    }

    function test_RevertWhen_TheValidatorRegistrationBlockIsNotZero()
        external
        whenSenderIsPoapOwner
        whenPoapIsFromStakersUnion
    {
        vm.prank(users.admin);
        poap.createPoap(users.validator, "", 175498);
        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        resetPrank(users.validator);
        // We subscribe a first time to set the registration block
        boostPool.subscribeValidators(validatorIds);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.ValidatorAlreadySubscribed.selector, 1));
        boostPool.subscribeValidators(validatorIds);
    }

    function test_WhenTheValidatorRegistrationBlockIsZero() external whenSenderIsPoapOwner whenPoapIsFromStakersUnion {
        vm.prank(users.admin);
        poap.createPoap(users.validator, "", 175498);
        resetPrank(users.validator);

        uint64[] memory validatorIds = new uint64[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        // it should emit SubscribeValidator
        vm.expectEmit();
        emit IBoostPool.SubscribeValidator(users.validator, 1);
        emit IBoostPool.SubscribeValidator(users.validator, 2);
        boostPool.subscribeValidators(validatorIds);

        // it should set the registration block to the current block
        assertEq(boostPool.validatorRegistrationBlock(1), block.number, "BoostPool: invalid registration block");
        assertEq(boostPool.validatorRegistrationBlock(2), block.number, "BoostPool: invalid registration block");
    }
}
