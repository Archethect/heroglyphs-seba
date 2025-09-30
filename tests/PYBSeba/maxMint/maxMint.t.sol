// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MaxMintTest is BaseTest {
    function test_ReturnsZero(address user) external {
        assertEq(pybSeba.maxMint(user), 0, "maxMint should be 0");
    }
}
