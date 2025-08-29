// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import {IPYBSeba} from "src/interfaces/IPYBSeba.sol";
import { ERC4626 } from "solmate/src/tokens/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DepositTest is BaseTest {
    function test_RevertWhen_TheAmountOfSharesForTheAssetsIsZero() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPYBSeba.ZeroShares.selector));
        resetPrank(users.validator);
        pybSeba.deposit(0, users.validator);
    }

    function test_RevertWhen_AddingTheSharesWouldExceedTheSupplycap()
        external
        whenTheAmountOfSharesForTheAssetsIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPYBSeba.SupplyCapExceeded.selector));
        resetPrank(users.validator);
        pybSeba.deposit(1, users.validator);
    }

    function test_WhenAddingTheSharesWouldNotExceedTheSupplycap() external whenTheAmountOfSharesForTheAssetsIsNotZero {
        resetPrank(contracts.sebaPool);

        deal(address(bold), contracts.sebaPool, 1 ether);
        bold.approve(contracts.sBOLD, 1 ether);
        sBOLD.deposit(1 ether, contracts.sebaPool);
        uint256 sBOLDBalance = IERC20(address(sBOLD)).balanceOf(contracts.sebaPool);
        IERC20(address(sBOLD)).approve(contracts.pybSeba, sBOLDBalance);

        pybSeba.topup(sBOLDBalance);
        pybSeba.distributeShares(users.validator, 1 ether);
        resetPrank(users.validator);
        pybSeba.withdraw(0.5 ether, users.validator, users.validator);

        assertEq(IERC20(address(sBOLD)).balanceOf(users.validator), 0.5 ether, "sBOLD balance of the sender should be 0.5");
        assertEq(IERC20(address(sBOLD)).balanceOf(contracts.pybSeba), sBOLDBalance - 0.5 ether, "sBOLD balance of the vault should be the remainder");
        assertEq(pybSeba.balanceOf(users.validator), pybSeba.convertToShares(sBOLDBalance - 0.5 ether), "shares balance of the receiver should be equal to the remainder converted in shares");
        assertEq(pybSeba.assetTotal(),sBOLDBalance - 0.5 ether, "assetTotal should be equal to the remainder");

        IERC20(address(sBOLD)).approve(contracts.pybSeba, 0.5 ether);

        // it should emit Deposit
        vm.expectEmit();
        emit ERC4626.Deposit(users.validator, users.validator, 0.5 ether, pybSeba.convertToShares(0.5 ether));
        pybSeba.deposit(0.5 ether, users.validator);

        // it should transfer the assets from the sender to the vault
        assertEq(IERC20(address(sBOLD)).balanceOf(users.validator), 0, "sBOLD balance of the sender should be 0");
        assertEq(IERC20(address(sBOLD)).balanceOf(contracts.pybSeba), sBOLDBalance, "sBOLD balance of the vault should be the initial sBoldBalance");
        // it should mint new shares to the receiver
        assertEq(pybSeba.balanceOf(users.validator), pybSeba.totalSupply(), "shares balance of the receiver should be the total supply");
        // it should increase the assetTotal with the provided amount of assets
        assertEq(pybSeba.assetTotal(), sBOLDBalance, "assetTotal should be the initial sBoldBalance");
    }
}
