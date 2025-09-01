// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MaxMintTest is BaseTest {
    function test_GivenTheUserCanConvertMoreAssetsToSharesThenCanBeMinted() external {
        resetPrank(contracts.sebaPool);
        deal(address(bold), contracts.sebaPool, 1 ether);
        bold.approve(contracts.sBOLD, 1 ether);
        sBOLD.deposit(1 ether, contracts.sebaPool);
        uint256 sBoldBalanceSeba = IERC20(address(sBOLD)).balanceOf(contracts.sebaPool);
        IERC20(address(sBOLD)).approve(contracts.pybSeba, sBoldBalanceSeba);
        pybSeba.topup(sBoldBalanceSeba);
        pybSeba.distributeShares(users.validator, 1 ether);
        resetPrank(users.validator);
        uint256 shares = pybSeba.withdraw(0.5 ether, users.validator, users.validator);

        resetPrank(users.nonValidator);
        deal(address(bold), users.nonValidator, 1.2 ether);
        bold.approve(contracts.sBOLD, 1.2 ether);
        sBOLD.deposit(1.2 ether, users.nonValidator);
        // it should return the maximum shares that can be minted looking at the supplycap
        assertEq(pybSeba.maxMint(users.nonValidator), shares, "maxMint should take the supplycap into account");
    }

    function test_GivenTheUserCanNotConvertMoreAssetsToSharesThenCanBeMinted() external {
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
        uint256 sBoldBalanceNonValidator = IERC20(address(sBOLD)).balanceOf(users.nonValidator);
        // it should return the total amount of shares the user can minted based on his assets
        assertEq(
            pybSeba.maxMint(users.nonValidator),
            pybSeba.convertToShares(sBoldBalanceNonValidator),
            "maxMint should be the total amount of shares the user can minted based on his assets"
        );
    }
}
