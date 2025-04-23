// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IApxETHVault } from "src/interfaces/IApxETHVault.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";

contract ActivateYieldFlowTest is BaseTest {
    function test_RevertWhen_NotTheYieldManager(address caller) external {
        vm.assume(contracts.yieldManager != caller);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDripVault.NotYieldManager.selector));
        vm.prank(caller);
        apxETHVault.activateYieldFlow();
    }

    function test_RevertWhen_YieldFlowIsActive() external whenTheYieldManager {
        apxETHVault.activateYieldFlow();

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDripVault.YieldFlowAlreadyActivated.selector));
        apxETHVault.activateYieldFlow();
    }

    function test_WhenYieldFlowIsNotActive() external whenTheYieldManager {
        vm.deal(contracts.yieldManager, 1 ether);
        apxETHVault.deposit{ value: 1 ether }();
        // 1 share = 1.2 ETH
        apxETH.setPricePerShare(1.2e18);
        uint256 expectedDeposit = (apxETHVault.getTotalDeposit() * apxETH.pricePerShare()) / 1e18;

        // it should emit YieldFlowActivated
        vm.expectEmit();
        emit IApxETHVault.YieldFlowActivated();
        uint256 result = apxETHVault.activateYieldFlow();

        // it should add the total interest to the total deposited amount
        assertEq(apxETHVault.getTotalDeposit(), expectedDeposit, "total deposit is not correct");
        // it should set yieldFlowActive to true
        assertEq(apxETHVault.yieldFlowActive(), true, "yield flow is not active");
        // it should return the interest
        assertEq(result, 0.198e18, "interest is not correct");
    }
}
