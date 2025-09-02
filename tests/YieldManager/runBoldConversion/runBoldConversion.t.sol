// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RunBoldConversionTest is BaseTest {
    function test_WhenThereIsAnOpenRouterIntent() external whenTheConversionTimeoutIsFinished {
        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        yieldManager.runBoldConversion();

        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        assertEq(yieldManager.pendingBoldConversion(), 0.5 ether);
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x1538d385667fd0072062559ec501a9a0c414f978a608fc953357e1f2db61a371)
        );

        vm.warp(block.timestamp + yieldManager.ROUTER_VALIDITY_SECS() + 1);
        yieldManager.runBoldConversion();
        // it should finalize the intent and reset the activeRouterId when a new one is instantiated
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x8f65826a4a10c2d12a2318fef21684798fd72217c35439601f219433605c7915)
        );
        // it should set the correct pendingBoldConversion
        assertEq(yieldManager.pendingBoldConversion(), 0);
    }

    function test_WhenTheBoldBalanceInTheContractIsBiggerThan0() external whenTheConversionTimeoutIsFinished {
        deal(address(bold), contracts.yieldManager, 1 ether);

        // it should emit BoldConversionFinalised
        vm.expectEmit();
        emit IYieldManager.BoldConversionFinalised(1 ether, 986249800864924383);
        yieldManager.runBoldConversion();

        // it should convert the bold to sBOLD and topup the sebaVault
        assertEq(bold.balanceOf(contracts.yieldManager), 0);
        assertEq(bold.balanceOf(contracts.pybSeba), 0);
        assertEq(IERC20(contracts.sBOLD).balanceOf(contracts.yieldManager), 0);
        assertEq(IERC20(contracts.sBOLD).balanceOf(contracts.pybSeba), 986249800864924383);
    }

    function test_WhenThePendingPendingBoldConversionIsBiggerThan0() external whenTheConversionTimeoutIsFinished {
        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        yieldManager.runBoldConversion();

        vm.deal(contracts.sebaPool, 1 ether);
        sebaPool.sweepRewards();

        assertEq(yieldManager.pendingBoldConversion(), 0.5 ether);
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x1538d385667fd0072062559ec501a9a0c414f978a608fc953357e1f2db61a371)
        );

        vm.warp(block.timestamp + yieldManager.ROUTER_VALIDITY_SECS() + 1);
        // it should emit BoldConversionStarted
        vm.expectEmit();
        emit IYieldManager.BoldConversionStarted(
            0x8f65826a4a10c2d12a2318fef21684798fd72217c35439601f219433605c7915,
            1 ether
        );
        yieldManager.runBoldConversion();
        // it should set the activeRouterUid
        assertEq(
            yieldManager.activeRouterUid(),
            bytes32(0x8f65826a4a10c2d12a2318fef21684798fd72217c35439601f219433605c7915)
        );
        // it should reset the pendingBoldConversion
        assertEq(yieldManager.pendingBoldConversion(), 0);
    }
}
