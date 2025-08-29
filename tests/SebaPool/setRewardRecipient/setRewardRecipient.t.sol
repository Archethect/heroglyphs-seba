// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { ISebaPool } from "src/interfaces/ISebaPool.sol";

contract SetRewardRecipientTest is BaseTest {
    function test_ShouldEmitSetRewardRecipient(address caller, address recipient) external {
        // it should emit SetRewardRecipient
        vm.expectEmit();
        emit ISebaPool.SetRewardRecipient(caller, recipient);
        vm.prank(caller);
        sebaPool.setRewardRecipient(recipient);
    }

    function test_ShouldSetTheCorrectRewardRecipientForTheSender(address caller, address recipient) external {
        vm.prank(caller);
        sebaPool.setRewardRecipient(recipient);

        // it should set the correct reward recipient for the sender
        assertEq(sebaPool.rewardRecipient(caller), recipient, "The reward recipient is not set correctly");
    }
}
