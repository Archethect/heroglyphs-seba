// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";

contract ReceiveTest is BaseTest {
    function test_ShouldReceiveETH() external {
        uint256 preBalance = address(yieldManager).balance;
        deal(address(yieldManager), 1 ether);

        // it should receive ETH
        assertEq(address(yieldManager).balance, preBalance + 1 ether, "yieldManager should have the funds");
    }
}
