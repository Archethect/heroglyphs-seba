// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MaxDepositTest is BaseTest {
    function test_GivenTheUserHasMoreAssetsThenCanBeDeposited() external {
        resetPrank(contracts.sebaPool);
        deal(address(bold), contracts.sebaPool, 1 ether);
        bold.approve(contracts.sBOLD, 1 ether);
        sBOLD.deposit(1 ether, contracts.sebaPool);
        uint256 sBoldBalanceSeba = IERC20(address(sBOLD)).balanceOf(contracts.sebaPool);
        IERC20(address(sBOLD)).approve(contracts.pybSeba, sBoldBalanceSeba);
        pybSeba.topup(sBoldBalanceSeba);
        pybSeba.distributeShares(users.validator, 1 ether);
        resetPrank(users.validator);

        resetPrank(users.nonValidator);
        deal(address(bold), users.nonValidator, 1.2 ether);
        bold.approve(contracts.sBOLD, 1.2 ether);
        sBOLD.deposit(1.2 ether, users.nonValidator);
        // it should return the maximum potential deposit looking at the supplycap
        assertEq(
            pybSeba.maxDeposit(users.nonValidator),
            0,
            "maxDeposit should take the supplycap into account"
        );
    }

    function test_GivenTheUserHasNotMoreAssetsThenCanBeDeposited() external {
        resetPrank(contracts.sebaPool);
        deal(address(bold), contracts.sebaPool, 1 ether);
        bold.approve(contracts.sBOLD, 1 ether);
        sBOLD.deposit(1 ether, contracts.sebaPool);
        uint256 sBoldBalanceSeba = IERC20(address(sBOLD)).balanceOf(contracts.sebaPool);
        IERC20(address(sBOLD)).approve(contracts.pybSeba, sBoldBalanceSeba);
        pybSeba.topup(sBoldBalanceSeba);
        pybSeba.distributeShares(users.validator, 1 ether);
        resetPrank(users.validator);
        pybSeba.withdraw(0.5 ether, users.validator, users.validator);

        resetPrank(users.nonValidator);
        deal(address(bold), users.nonValidator, 0.4 ether);
        bold.approve(contracts.sBOLD, 0.4 ether);
        sBOLD.deposit(0.4 ether, users.nonValidator);
        // it should return the total amount of assets the user holds
        assertEq(
            pybSeba.maxDeposit(users.nonValidator),
            0,
            "maxDeposit should take the supplycap into account"
        );
    }
}
