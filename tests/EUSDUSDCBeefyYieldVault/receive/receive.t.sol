// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";

contract ReceiveTest is BaseTest {
    function test_ShouldReceiveETH() external {
        uint256 preBalance = address(ethToBoldRouter).balance;
        deal(address(ethToBoldRouter), 1 ether);

        // it should receive ETH
        assertEq(address(ethToBoldRouter).balance, preBalance + 1 ether, "ethToBoldRouter should have the funds");
    }
}
