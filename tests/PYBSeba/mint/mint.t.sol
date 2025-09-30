// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IPYBSeba } from "src/interfaces/IPYBSeba.sol";
import { ERC4626 } from "solmate/src/tokens/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { StdStorage, stdStorage } from "forge-std/src/StdStorage.sol";

contract MintTest is BaseTest {
    using stdStorage for StdStorage;
    StdStorage private stdstore;

    function test_Revert() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPYBSeba.MintNotAllowed.selector));
        resetPrank(users.validator);
        pybSeba.mint(1, users.validator);
    }
}
