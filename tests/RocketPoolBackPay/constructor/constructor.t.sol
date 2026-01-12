// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IRocketPoolBackPay } from "src/interfaces/IRocketPoolBackPay.sol";
import { RocketPoolBackPay } from "src/RocketPoolBackPay.sol";

contract ConstructorTest is BaseTest {
    function test_RevertWhen_SebaPoolIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IRocketPoolBackPay.InvalidAddress.selector));
        new RocketPoolBackPay(address(0));
    }

    function test_WhenSebaPoolIsNotZero(address _sebaPool) external {
        assumeNotZeroAddress(_sebaPool);

        RocketPoolBackPay localRocketPoolBackPay = new RocketPoolBackPay(_sebaPool);

        // it should set the correct seba pool address
        assertEq(
            localRocketPoolBackPay.sebaPool(), _sebaPool, "RocketPoolBackPay: It should be the correct sebapool address"
        );
    }
}
