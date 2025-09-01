// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { ISebaPool } from "src/interfaces/ISebaPool.sol";

contract FallbackTest is BaseTest {
    function test_WhenValueIsZero() external {
        // it should emit EtherReceived with zero
        vm.expectEmit();
        emit ISebaPool.EtherReceived(address(this), 0);
        (bool success, ) = address(sebaPool).call{ value: 0 }("");
        assertTrue(success);
    }

    function test_WhenValueIsNotZero(uint256 amount) external {
        vm.assume(amount < type(uint256).max);
        vm.deal(address(this), amount);

        // it should emit EtherReceived with the value
        vm.expectEmit();
        emit ISebaPool.EtherReceived(address(this), amount);
        (bool success, ) = address(sebaPool).call{ value: amount }("");
        assertTrue(success);
    }
}
