// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";
import {ISebaYieldVault} from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";

contract TopupTest is BaseTest {
    function test_GivenATopupIsDone() external {
        apxETH.mint(users.validator, 1.2 ether);
        resetPrank(users.validator);

        apxETH.approve(contracts.pybapxETH, 1.2 ether);

        // it should emit Topup
        vm.expectEmit();
        emit ISebaYieldVault.Topup(users.validator, 1 ether);
        pybapxEth.topup(1 ether);
        pybapxEth.topup(0.2 ether);
        // it should send the assets from the sender to the vault
        assertEq(apxETH.balanceOf(users.validator), 0, "apxETH balance of the sender should be 0");
        assertEq(apxETH.balanceOf(contracts.pybapxETH), 1.2 ether, "apxETH balance of the vault should be 1 ether");
        // it should increase assetTotal
        assertEq(pybapxEth.assetTotal(), 1.2 ether, "assetTotal should be 1 ether");
    }
}*/
