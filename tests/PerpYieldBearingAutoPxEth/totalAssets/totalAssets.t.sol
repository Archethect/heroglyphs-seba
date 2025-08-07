// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";

contract TotalAssetsTest is BaseTest {
    function test_ShouldReturnTheTotalAmountOfAssets(uint256 amount) external {
        vm.assume(amount < type(uint128).max);

        resetPrank(users.validator);

        apxETH.mint(users.validator, amount);
        apxETH.approve(contracts.pybapxETH, amount);
        pybapxEth.topup(amount);

        // it should return the total amount of assets
        assertEq(pybapxEth.totalAssets(), amount, "totalAssets should be equal to the amount of assets");
    }
}*/
