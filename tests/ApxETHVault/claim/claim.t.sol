// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";

contract ClaimTest is BaseTest {
    function test_RevertWhen_NotTheYieldManager(address caller) external {
        vm.assume(contracts.yieldManager != caller);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDripVault.NotYieldManager.selector));
        vm.prank(caller);
        apxETHVault.claim();
    }

    function test_RevertWhen_YieldFlowIsNotActive() external whenTheYieldManager {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDripVault.YieldFlowNotActivated.selector));
        apxETHVault.claim();
    }

    function test_WhenTheYieldFlowIsActive() external whenTheYieldManager {
        apxETHVault.activateYieldFlow();
        vm.deal(contracts.yieldManager, 2 ether);
        apxETHVault.deposit{ value: 2 ether }();
        apxETH.setPricePerShare(1.2e18);

        // it should emit InterestClaimed
        vm.expectEmit();
        emit IDripVault.InterestClaimed(contracts.yieldManager, 0.33e18);
        uint256 result = apxETHVault.claim();

        // it should transfer the interest in apxETH to the sender
        assertEq(apxETH.balanceOf(contracts.yieldManager), 0.33e18, "apxETH balance is not correct");
        // it should return the interest
        assertEq(result, 0.33e18, "interest is not correct");
    }
}
