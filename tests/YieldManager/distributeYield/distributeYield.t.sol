// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { MockSimpleYieldVault } from "src/mocks/MockSimpleYieldVault.sol";
import { IBeefyVault } from "src/vendor/beefy/IBeefyVault.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DistributeYieldTest is BaseTest {
    /// forge-config: default.allow_internal_expect_revert = true
    function test_RevertWhen_NotTheAutomatorRole(address caller) external {
        vm.assume(caller != users.automator);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                yieldManager.AUTOMATOR_ROLE()
            )
        );
        resetPrank(caller);
        yieldManager.distributeYield();
    }

    function test_WhenThereIsNoYieldClaimed() external whenTheAutomatorRole {
        resetPrank(users.automator);

        // it should emit YieldDistributed
        vm.expectEmit();
        emit IYieldManager.YieldDistributed(0, true);
        yieldManager.distributeYield();
    }

    function test_WhenTheYieldFlowIsNotActive() external whenTheAutomatorRole whenThereIsYieldClaimed {
        resetPrank(users.admin);
        MockSimpleYieldVault localYieldVault = new MockSimpleYieldVault();
        vm.deal(address(localYieldVault), 1 ether);
        yieldManager.setYieldVault(address(localYieldVault));

        resetPrank(users.automator);

        // it should emit YieldDistributed
        vm.expectEmit();
        emit IYieldManager.YieldDistributed(1 ether, false);
        yieldManager.distributeYield();

        // it should deposit the yield back into the yield vault
        assertEq(yieldManager.principalValue(), 1 ether);
    }

    function test_WhenTheYieldFlowIsActive() external whenTheAutomatorRole whenThereIsYieldClaimed {
        resetPrank(users.admin);
        vm.deal(address(contracts.yieldManager), 1 ether);
        yieldManager.depositPrincipalIntoYieldVault();

        resetPrank(users.automator);
        yieldManager.activateYieldFlow();
        uint256 ppsNow = beefy.getPricePerFullShare();
        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(ppsNow * 2)
        );

        // it should emit YieldDistributed
        vm.expectEmit();
        emit IYieldManager.YieldDistributed(499306920170780746, true);
        yieldManager.distributeYield();

        // it should increase the pendingBoldConversion
        assertEq(yieldManager.pendingBoldConversion(), 499306920170780746);
    }
}
