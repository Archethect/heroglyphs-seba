// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";

contract GetOutputTokenTest is BaseTest {
    function test_ShouldReturnTheApxETHAddress() external {
        // it should return the apxETH address
        assertEq(apxETHVault.getOutputToken(), contracts.apxETH, "output token is not the apxETH address");
    }
}
