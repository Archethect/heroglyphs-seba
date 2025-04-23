// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";

contract GetInputTokenTest is BaseTest {
    function test_ShouldRetrunTheZeroAddress() external {
        // it should retrun the zero address
        assertEq(apxETHVault.getInputToken(), address(0), "input token is not the zero address");
    }
}
