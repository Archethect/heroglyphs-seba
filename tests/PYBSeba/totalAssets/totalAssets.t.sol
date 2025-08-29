// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TotalAssetsTest is BaseTest {
    function test_ShouldReturnTheTotalAmountOfAssets(uint256 amount) external {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint128).max);

        resetPrank(users.validator);

        deal(address(bold), users.validator,amount);
        bold.approve(contracts.sBOLD, amount);
        sBOLD.deposit(amount, users.validator);
        uint256 sBoldBalance = IERC20(address(sBOLD)).balanceOf(contracts.sebaPool);
        IERC20(address(sBOLD)).approve(contracts.pybSeba, sBoldBalance);
        pybSeba.topup(sBoldBalance);

        // it should return the total amount of assets
        assertEq(pybSeba.totalAssets(), sBoldBalance, "totalAssets should be equal to the amount of assets");
    }
}
