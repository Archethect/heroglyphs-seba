// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { HandoffUnitBase } from "../HandoffUnitBase.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";

contract HandoffStageATest is HandoffUnitBase {
    function test_exitedEthWaitsInOldManagerNotStopperAcrossTheApprovalGap() public {
        assertEq(address(old.yieldVault()), address(stopper));
        assertEq(old.principalValue(), 0);
        assertEq(address(old).balance, ETH_BUDGET);
        assertEq(address(stopper).balance, 0);
        assertEq(adapter.principalValue(), 150);
        assertEq(adapter.principalShares(), 121);
        vm.warp(block.timestamp + 1 hours);
        _pre();
        assertEq(address(old).balance, ETH_BUDGET);
        assertEq(address(stopper).balance, 0);
        assertFalse(handoff.used());
    }

    function test_normalUserPoolAndAdminDepositsStayBlockedBeforeStageB() public {
        address[2] memory callers = [address(0x9876), address(pool)];
        for (uint256 i; i < callers.length; ++i) {
            vm.deal(callers[i], 1 ether);
            vm.prank(callers[i]);
            vm.expectRevert(LegacyIntakeStopper.IntakeStopped.selector);
            old.depositFunds{ value: 1 ether }();
        }
        vm.prank(address(safe));
        vm.expectRevert(LegacyIntakeStopper.IntakeStopped.selector);
        old.depositPrincipalIntoYieldVault();
        assertEq(address(old).balance, ETH_BUDGET);
        assertEq(old.principalValue(), 0);
        assertEq(old.depositId(), 1);
        assertEq(address(stopper).balance, 0);
    }

    function test_unexpectedEthOrPointerDriftAbortsWithoutUndoingThePriorExit() public {
        vm.deal(address(old), ETH_BUDGET + 1);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        assertEq(old.principalValue(), 0);
        assertEq(address(old.yieldVault()), address(stopper));
        assertEq(address(old).balance, ETH_BUDGET + 1);
        assertEq(adapter.principalValue(), 150);
        assertFalse(handoff.used());
        assertFalse(destination.legacyImported());
    }
}
