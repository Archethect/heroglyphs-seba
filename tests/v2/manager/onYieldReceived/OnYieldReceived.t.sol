// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract OnYieldReceivedTest is ManagerTestBase {
    function setUp() public override {
        super.setUp();
        _bind();
    }
    function test_AuthenticatesBothLegsAndEachBucketWhilePaused() public {
        rVault.harvest(0, 1);
        rVault.harvest(1, 2);
        yVault.harvest(0, 3);
        yVault.harvest(1, 4);
        assertEq(manager.harvestInventory(0, 0), 1);
        assertEq(manager.harvestInventory(0, 1), 2);
        assertEq(manager.harvestInventory(1, 0), 3);
        assertEq(manager.harvestInventory(1, 1), 4);
    }
    function test_InvalidCallerBucketZeroAndUnbackedCallback() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.onYieldReceived(0, 1);
        vm.expectRevert(IYieldManagerV2.InvalidBucket.selector);
        rVault.harvest(2, 1);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        rVault.harvest(0, 0);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(address(rVault));
        manager.onYieldReceived(0, 1);
        assertEq(manager.harvestInventory(0, 0), 0);
    }
    function test_FailedSiblingNeverBlocksReceipt() public {
        ysyToken.setBrokenBalance(true);
        rVault.harvest(0, 1);
        assertEq(manager.harvestInventory(0, 0), 1);
        ysyToken.setBrokenBalance(false);
        rethToken.setBrokenBalance(true);
        yVault.harvest(1, 2);
        assertEq(manager.harvestInventory(1, 1), 2);
    }
}
