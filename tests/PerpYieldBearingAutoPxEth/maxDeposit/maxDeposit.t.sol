// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";

contract MaxDepositTest is BaseTest {
    function test_GivenTheUserHasMoreAssetsThenCanBeDeposited() external {
        resetPrank(contracts.boostPool);
        apxETH.mint(contracts.boostPool, 1 ether);
        apxETH.approve(contracts.pybapxETH, 1 ether);
        pybapxEth.topup(1 ether);
        pybapxEth.distributeShares(users.validator, 1 ether);
        resetPrank(users.validator);
        pybapxEth.withdraw(0.5 ether, users.validator, users.validator);

        apxETH.mint(users.nonValidator, 1.2 ether);
        // it should return the maximum potential deposit looking at the supplycap
        assertEq(
            pybapxEth.maxDeposit(users.nonValidator),
            0.5 ether,
            "maxDeposit should take the supplycap into account"
        );
    }

    function test_GivenTheUserHasNotMoreAssetsThenCanBeDeposited() external {
        resetPrank(contracts.boostPool);
        apxETH.mint(contracts.boostPool, 1 ether);
        apxETH.approve(contracts.pybapxETH, 1 ether);
        pybapxEth.topup(1 ether);
        pybapxEth.distributeShares(users.validator, 1 ether);
        resetPrank(users.validator);
        pybapxEth.withdraw(0.5 ether, users.validator, users.validator);

        apxETH.mint(users.nonValidator, 0.4 ether);
        // it should return the total amount of assets the user holds
        assertEq(
            pybapxEth.maxDeposit(users.nonValidator),
            0.4 ether,
            "maxDeposit should be the total amount of assets the user holds"
        );
    }
}*/
