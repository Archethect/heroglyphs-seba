// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";
import { IBoostPool } from "src/interfaces/IBoostPool.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract GraduateValidatorTest is BaseTest {
    function test_RevertWhen_NotTheAutomatorRole(address caller) external {
        vm.assume(caller != users.automator);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                boostPool.AUTOMATOR_ROLE()
            )
        );
        resetPrank(caller);
        boostPool.graduateValidator(1, address(0), 1);
    }

    function test_RevertWhen_TheValidatorRegistratonBlockIsZero() external whenTheAutomatorRole {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.ValidatorNotSubscribed.selector, 1));
        resetPrank(users.automator);
        boostPool.graduateValidator(1, address(0), 1);
    }

    function test_RevertWhen_TheValidatorIsAlreadyGraduated()
        external
        whenTheAutomatorRole
        whenTheValidatorRegistrationBlockIsNotZero
    {
        resetPrank(users.admin);
        poap.createPoap(users.validator, "", 175498);
        resetPrank(users.validator);
        boostPool.subscribeValidator(1, 1);

        vm.roll(block.number + boostPool.GRADUATION_DURATION_IN_BLOCKS());

        resetPrank(users.automator);
        boostPool.graduateValidator(1, address(0), 1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.ValidatorAlreadyGraduated.selector, 1));
        boostPool.graduateValidator(1, address(0), 1);
    }

    function test_RevertWhen_TheGraduationDurationIsNotYetReached()
        external
        whenTheAutomatorRole
        whenTheValidatorRegistrationBlockIsNotZero
        whenTheValidatorIsNotYetGraduated
    {
        resetPrank(users.admin);
        poap.createPoap(users.validator, "", 175498);
        resetPrank(users.validator);
        boostPool.subscribeValidator(1, 1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IBoostPool.GraduationPeriodNotOver.selector, 1));
        resetPrank(users.automator);
        boostPool.graduateValidator(1, address(0), 1);
    }

    function test_WhenTheGraduationDurationIsReached(
        address receiverAddress,
        uint256 attestationPoints
    ) external whenTheAutomatorRole whenTheValidatorRegistrationBlockIsNotZero whenTheValidatorIsNotYetGraduated {
        vm.assume(attestationPoints <= type(uint256).max);
        assumeNotZeroAddress(receiverAddress);
        resetPrank(users.admin);
        poap.createPoap(users.validator, "", 175498);
        resetPrank(users.validator);
        boostPool.subscribeValidator(1, 1);
        boostPool.setRewardRecipient(receiverAddress);

        vm.roll(block.number + boostPool.GRADUATION_DURATION_IN_BLOCKS());

        // it should emit ValidatorGraduated
        vm.expectEmit();
        emit IBoostPool.ValidatorGraduated(1, receiverAddress, attestationPoints);
        resetPrank(users.automator);
        boostPool.graduateValidator(1, users.validator, attestationPoints);

        // it should set validatorIsGraduated to true
        assertTrue(boostPool.validatorIsGraduated(1), "BoostPool: validator should be graduated");
        // it should distribute the pybapxETH shares
        assertEq(pybapxEth.balanceOf(receiverAddress), attestationPoints, "pybapxETH: shares should be distributed");
    }
}*/
