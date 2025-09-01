// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IPYBSeba } from "src/interfaces/IPYBSeba.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TopupTest is BaseTest {
    function test_GivenATopupIsDone() external {
        resetPrank(users.validator);
        deal(address(bold), users.validator, 1.2 ether);
        bold.approve(contracts.sBOLD, 1.2 ether);
        sBOLD.deposit(1.2 ether, users.validator);
        uint256 sBoldBalance = IERC20(address(sBOLD)).balanceOf(users.validator);
        IERC20(address(sBOLD)).approve(contracts.pybSeba, sBoldBalance);

        // it should emit Topup
        vm.expectEmit();
        emit IPYBSeba.Topup(users.validator, sBoldBalance);
        pybSeba.topup(sBoldBalance);
        // it should send the assets from the sender to the vault
        assertEq(IERC20(address(sBOLD)).balanceOf(users.validator), 0, "sBOLD balance of the sender should be 0");
        assertEq(
            IERC20(address(sBOLD)).balanceOf(contracts.pybSeba),
            sBoldBalance,
            "sBOLD balance of the vault should be correct"
        );
        // it should increase assetTotal
        assertEq(pybSeba.assetTotal(), sBoldBalance, "assetTotal should be correct");
    }
}
