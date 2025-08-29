// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";

contract ReceiveTest is BaseTest {
    function test_ShouldReceiveETH() external {
        uint256 preBalance = address(eUsdUsdcBeefyYieldVault).balance;
        deal(address(eUsdUsdcBeefyYieldVault), 1 ether);

        // it should receive ETH
        assertEq(
            address(eUsdUsdcBeefyYieldVault).balance,
            preBalance + 1 ether,
            "eUsdUsdcBeefyYieldVault should have the funds"
        );
    }
}
