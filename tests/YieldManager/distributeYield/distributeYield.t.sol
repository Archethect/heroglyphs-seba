// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";

contract DistributeYieldTest is BaseTest {
    function test_GivenTheApxETHBalanceIsBiggerThanZero() external {
        resetPrank(contracts.yieldManager);

        apxETHVault.activateYieldFlow();
        vm.deal(contracts.yieldManager, 2 ether);
        apxETHVault.deposit{ value: 2 ether }();
        apxETH.setPricePerShare(1.2e18);

        // it should emit YieldDistributed
        vm.expectEmit();
        emit IYieldManager.YieldDistributed(contracts.yieldManager, contracts.pybapxETH, 0.33 ether);
        yieldManager.distributeYield();

        // it should send the full apxETH balance to pybapxETH vault
        assertEq(apxETH.balanceOf(contracts.pybapxETH), 0.33 ether, "pybapxETH balance is not correct");
    }
}*/
