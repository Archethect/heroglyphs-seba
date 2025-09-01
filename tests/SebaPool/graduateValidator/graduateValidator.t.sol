// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { ISebaPool } from "src/interfaces/ISebaPool.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract GraduateValidatorTest is BaseTest {
    function test_RevertWhen_NotTheAutomatorRole(address caller) external {
        vm.assume(caller != users.automator);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                sebaPool.AUTOMATOR_ROLE()
            )
        );
        resetPrank(caller);
        sebaPool.graduateValidator(1, address(0), 1);
    }

    function test_RevertWhen_TheValidatorRegistrationBlockIsZero() external whenTheAutomatorRole {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.ValidatorNotSubscribed.selector, 1));
        resetPrank(users.automator);
        sebaPool.graduateValidator(1, address(0), 1);
    }

    function test_RevertWhen_TheValidatorIsAlreadyGraduated()
        external
        whenTheAutomatorRole
        whenTheValidatorRegistrationBlockIsNotZero
    {
        resetPrank(users.validator);
        sebaPool.subscribeValidator(1);

        vm.roll(block.number + sebaPool.GRADUATION_DURATION_IN_BLOCKS());

        resetPrank(users.automator);
        sebaPool.graduateValidator(1, address(0), 1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.ValidatorAlreadyGraduated.selector, 1));
        sebaPool.graduateValidator(1, address(0), 1);
    }

    function test_RevertWhen_TheGraduationDurationIsNotYetReached()
        external
        whenTheAutomatorRole
        whenTheValidatorRegistrationBlockIsNotZero
        whenTheValidatorIsNotYetGraduated
    {
        resetPrank(users.validator);
        sebaPool.subscribeValidator(1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.GraduationPeriodNotOver.selector, 1));
        resetPrank(users.automator);
        sebaPool.graduateValidator(1, address(0), 1);
    }

    function test_WhenTheGraduationDurationIsReachedAndTheRewardRecipientIsSet(
        address receiverAddress,
        uint256 attestationPoints
    ) external whenTheAutomatorRole whenTheValidatorRegistrationBlockIsNotZero whenTheValidatorIsNotYetGraduated {
        vm.assume(attestationPoints <= type(uint256).max);
        assumeNotZeroAddress(receiverAddress);
        resetPrank(users.validator);
        sebaPool.subscribeValidator(1);
        sebaPool.setRewardRecipient(receiverAddress);

        vm.roll(block.number + sebaPool.GRADUATION_DURATION_IN_BLOCKS());

        // it should emit ValidatorGraduated
        vm.expectEmit();
        emit ISebaPool.ValidatorGraduated(1, receiverAddress, attestationPoints);
        resetPrank(users.automator);
        sebaPool.graduateValidator(1, users.validator, attestationPoints);

        // it should set validatorIsGraduated to true
        assertTrue(sebaPool.validatorIsGraduated(1), "BoostPool: validator should be graduated");
        // it should distribute the pybapxETH shares to the recipient address
        assertEq(pybSeba.balanceOf(receiverAddress), attestationPoints, "pybapxETH: shares should be distributed");
    }

    function test_WhenTheGraduationDurationIsReachedAndTheRewardRecipientIsNotSet(
        uint256 attestationPoints,
        address withdrawalAddress
    ) external whenTheAutomatorRole whenTheValidatorRegistrationBlockIsNotZero whenTheValidatorIsNotYetGraduated {
        vm.assume(attestationPoints <= type(uint256).max);
        assumeNotZeroAddress(withdrawalAddress);
        resetPrank(users.validator);
        sebaPool.subscribeValidator(1);

        vm.roll(block.number + sebaPool.GRADUATION_DURATION_IN_BLOCKS());

        // it should emit ValidatorGraduated
        vm.expectEmit();
        emit ISebaPool.ValidatorGraduated(1, withdrawalAddress, attestationPoints);
        resetPrank(users.automator);
        sebaPool.graduateValidator(1, withdrawalAddress, attestationPoints);

        // it should set validatorIsGraduated to true
        assertTrue(sebaPool.validatorIsGraduated(1), "BoostPool: validator should be graduated");
        // it should distribute the pybapxETH shares to the withdrawal address
        assertEq(pybSeba.balanceOf(withdrawalAddress), attestationPoints, "pybapxETH: shares should be distributed");
    }
}
