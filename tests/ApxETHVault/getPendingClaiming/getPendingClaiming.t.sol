// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";

contract GetPendingClaimingTest is BaseTest {
    function test_WhenTheMaxRedeemableApxETHInETHIsNotBiggerThenTheTotalAmountOfDeposits() external {
        resetPrank(contracts.yieldManager);

        apxETHVault.activateYieldFlow();
        vm.deal(contracts.yieldManager, 2 ether);
        apxETHVault.deposit{ value: 2 ether }();
        apxETH.setPricePerShare(1.2e18);
        apxETHVault.claim();

        // it should return 0
        uint256 pendingClaiming = apxETHVault.getPendingClaiming();
        assertEq(pendingClaiming, 0, "pending claiming is not correct");
    }

    function test_WhenTheMaxRedeemableApxETHInETHIsBiggerThenTheTotalAmountOfDeposits() external {
        resetPrank(contracts.yieldManager);

        vm.deal(contracts.yieldManager, 2 ether);
        apxETHVault.deposit{ value: 2 ether }();
        apxETH.setPricePerShare(1.2e18);

        // it should return the pending claimable amount
        uint256 pendingClaiming = apxETHVault.getPendingClaiming();
        assertEq(pendingClaiming, 0.33e18, "pending claiming is not correct");
    }
}
