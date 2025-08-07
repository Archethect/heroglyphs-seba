// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";
import {ISebaYieldVault} from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";
import { ERC4626 } from "solmate/src/tokens/ERC4626.sol";

contract MintTest is BaseTest {
    function test_RevertWhen_AddingTheSharesWouldExceedTheSupplycap() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaYieldVault.SupplyCapExceeded.selector));
        resetPrank(users.validator);
        pybapxEth.mint(1, users.validator);
    }

    function test_WhenAddingTheSharesWouldNotExceedTheSupplycap() external {
        resetPrank(contracts.boostPool);

        apxETH.mint(contracts.boostPool, 1 ether);
        apxETH.approve(contracts.pybapxETH, 1 ether);
        pybapxEth.topup(1 ether);
        pybapxEth.distributeShares(users.validator, 1 ether);
        resetPrank(users.validator);
        pybapxEth.withdraw(0.5 ether, users.validator, users.validator);

        apxETH.approve(contracts.pybapxETH, 0.5 ether);

        assertEq(apxETH.balanceOf(users.validator), 0.5 ether, "apxETH balance of the sender should be 0.5");
        assertEq(apxETH.balanceOf(contracts.pybapxETH), 0.5 ether, "apxETH balance of the vault should be 0.5");
        assertEq(pybapxEth.balanceOf(users.validator), 0.5 ether, "shares balance of the receiver should be 0.5");
        assertEq(pybapxEth.assetTotal(), 0.5 ether, "assetTotal should be 0.5");

        // it should emit Deposit
        vm.expectEmit();
        emit ERC4626.Deposit(users.validator, users.validator, 0.5 ether, 0.5 ether);
        pybapxEth.mint(0.5 ether, users.validator);

        // it should transfer the assets from the sender to the vault
        assertEq(apxETH.balanceOf(users.validator), 0, "apxETH balance of the sender should be 0");
        assertEq(apxETH.balanceOf(contracts.pybapxETH), 1 ether, "apxETH balance of the vault should be 1 ether");
        // it should mint new shares to the receiver
        assertEq(pybapxEth.balanceOf(users.validator), 1 ether, "shares balance of the receiver should be 0.5 ether");
        // it should increase the assetTotal with the amount of assets
        assertEq(pybapxEth.assetTotal(), 1 ether, "assetTotal should be 1 ether");
    }
}*/
