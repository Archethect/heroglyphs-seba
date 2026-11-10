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
    function test_DirectYearnConvertsOnlyYsyCarry() public {
        for (uint8 bucket; bucket < 2; ++bucket) {
            uint256 amount = manager.harvestInventory(1, bucket);
            vm.prank(operator);
            manager.convertHarvest(1, bucket, amount, amount, block.timestamp);
            assertEq(manager.harvestInventory(1, bucket), 0);
        }
        assertEq(manager.pendingBold(), 70 ether);
        assertEq(manager.harvestInventory(0, 0), 10 ether);
        assertEq(manager.harvestInventory(0, 1), 20 ether);
        assertEq(ysyToken.allowance(address(manager), address(execution)), 0);
    }
    function test_FaultsPartialConsumptionAndSlippageAreAtomic() public {
        for (uint8 mode = 1; mode <= 4; ++mode) {
            if (mode == 3) continue;
            execution.setMode(mode);
            vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
            vm.prank(operator);
            manager.convertHarvest(1, 0, 1 ether, 1, block.timestamp);
            assertEq(manager.harvestInventory(1, 0), 30 ether);
            assertEq(manager.pendingBold(), 0);
        }
        execution.setMode(0);
        vm.expectRevert(IYieldManagerV2.InsufficientOutput.selector);
        vm.prank(operator);
        manager.convertHarvest(1, 0, 1 ether, 2 ether, block.timestamp);
    }
    function test_InvalidLegBucketZeroInventoryAndCap() public {
        vm.startPrank(operator);
        vm.expectRevert(IYieldManagerV2.AsyncOrderRequired.selector);
        manager.convertHarvest(0, 0, 1, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.AsyncOrderRequired.selector);
        manager.convertHarvest(2, 0, 1, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidBucket.selector);
        manager.convertHarvest(1, 2, 1, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        manager.convertHarvest(1, 0, 0, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        manager.convertHarvest(1, 0, 31 ether, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        manager.convertHarvest(1, 0, 100_001 ether, 1, block.timestamp);
        vm.stopPrank();
    }
    function test_RethOutageDoesNotBlockDirectYearn() public {
        rethToken.setBrokenBalance(true);
        vm.prank(operator);
        manager.convertHarvest(1, 0, 1 ether, 1, block.timestamp);
        assertEq(manager.harvestInventory(1, 0), 29 ether);
    }
    function test_DeficientNativeCustodyRejects() public {
        ysyToken.burn(address(manager), 1);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(operator);
        manager.convertHarvest(1, 0, 1, 1, block.timestamp);
    }
}
