// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ConvertHarvestTest is ManagerTestBase {
    function setUp() public override {
        super.setUp();
        _enable();
        rVault.harvest(0, 10 ether);
        rVault.harvest(1, 20 ether);
        yVault.harvest(0, 30 ether);
        yVault.harvest(1, 40 ether);
    }
    function test_EachLegAndBucketConvertsOnlyCarry() public {
        for (uint8 leg; leg < 2; ++leg)
            for (uint8 bucket; bucket < 2; ++bucket) {
                uint256 amount = manager.harvestInventory(leg, bucket);
                vm.prank(operator);
                manager.convertHarvest(leg, bucket, amount, amount, block.timestamp);
                assertEq(manager.harvestInventory(leg, bucket), 0);
            }
        assertEq(manager.pendingBold(), 100 ether);
        assertEq(rethToken.allowance(address(manager), address(execution)), 0);
        assertEq(ysyToken.allowance(address(manager), address(execution)), 0);
    }
    function test_FaultsPartialConsumptionAndSlippageAreAtomic() public {
        for (uint8 mode = 1; mode <= 4; ++mode) {
            if (mode == 3) continue;
            execution.setMode(mode);
            vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
            vm.prank(operator);
            manager.convertHarvest(0, 0, 1 ether, 1, block.timestamp);
            assertEq(manager.harvestInventory(0, 0), 10 ether);
            assertEq(manager.pendingBold(), 0);
        }
        execution.setMode(0);
        vm.expectRevert(IYieldManagerV2.InsufficientOutput.selector);
        vm.prank(operator);
        manager.convertHarvest(0, 0, 1 ether, 2 ether, block.timestamp);
    }
    function test_InvalidLegBucketZeroInventoryAndCap() public {
        vm.expectRevert(IYieldManagerV2.InvalidLeg.selector);
        vm.prank(operator);
        manager.convertHarvest(2, 0, 1, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidBucket.selector);
        vm.prank(operator);
        manager.convertHarvest(0, 2, 1, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertHarvest(0, 0, 0, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertHarvest(0, 0, 11 ether, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertHarvest(0, 0, 100_001 ether, 1, block.timestamp);
    }
    function test_SiblingTokenOutageDoesNotBlockOtherLeg() public {
        ysyToken.setBrokenBalance(true);
        vm.prank(operator);
        manager.convertHarvest(0, 0, 1 ether, 1, block.timestamp);
        assertEq(manager.harvestInventory(0, 0), 9 ether);
        ysyToken.setBrokenBalance(false);
        rethToken.setBrokenBalance(true);
        vm.prank(operator);
        manager.convertHarvest(1, 0, 1 ether, 1, block.timestamp);
        assertEq(manager.harvestInventory(1, 0), 29 ether);
    }
    function test_DeficientNativeCustodyRejects() public {
        rethToken.burn(address(manager), 1);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(operator);
        manager.convertHarvest(0, 0, 1, 1, block.timestamp);
    }
}
