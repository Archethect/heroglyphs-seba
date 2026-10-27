// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract RecoverBuffersTest is ManagerTestBase {
    function setUp() public override {
        super.setUp();
        _enable();
    }
    function _inventory() internal {
        _fund(40 ether);
        vm.startPrank(operator);
        manager.convertEthRewards(10 ether, 1, block.timestamp);
        manager.convertBoldToSBold(5 ether, 1, block.timestamp);
        vm.stopPrank();
        rVault.harvest(0, 1 ether);
        rVault.harvest(1, 2 ether);
        yVault.harvest(0, 3 ether);
        yVault.harvest(1, 4 ether);
    }
    function test_ExactExportExcludesUnassignedAndLeavesVaultsAlone() public {
        _inventory();
        vm.deal(address(manager), address(manager).balance + 7);
        uint256 beforeSafe = address(safe).balance;
        vm.prank(address(safe));
        manager.recoverBuffers(keccak256("public reconciliation"));
        assertEq(address(safe).balance - beforeSafe, 30 ether);
        assertEq(address(manager).balance, 7);
        assertEq(boldToken.balanceOf(address(safe)), 5 ether);
        assertEq(sBoldToken.balanceOf(address(safe)), 5 ether);
        assertEq(rethToken.balanceOf(address(safe)), 3 ether);
        assertEq(ysyToken.balanceOf(address(safe)), 7 ether);
        assertTrue(manager.buffersRecovered());
        assertFalse(manager.intakeEnabled());
        assertFalse(manager.executionEnabled());
        for (uint8 p; p < 3; ++p) assertEq(manager.pendingEth(p), 0);
        for (uint8 leg; leg < 2; ++leg) for (uint8 b; b < 2; ++b) assertEq(manager.harvestInventory(leg, b), 0);
        assertEq(manager.pendingBold(), 0);
        assertEq(manager.pendingSBold(), 0);
        assertEq(rVault.protocolBasis(), 0);
        assertEq(yVault.protocolBasis(), 0);
        vm.expectRevert(IYieldManagerV2.BuffersAlreadyRecovered.selector);
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
    }
    function test_EmptyFirstRecoveryAndNewTerminalCarryCanBeExportedOnce() public {
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
        rVault.harvest(0, 9);
        yVault.harvest(1, 7);
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(2)));
        assertEq(rethToken.balanceOf(address(safe)), 9);
        assertEq(ysyToken.balanceOf(address(safe)), 7);
        vm.expectRevert(IYieldManagerV2.BuffersAlreadyRecovered.selector);
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(3)));
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setIntakeEnabled(true);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setExecutionEnabled(true);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(address(safe));
        manager.recognizeEthSurplus(0, 1);
    }
    function test_FailedTreasuryTransferRollsBackAllBuffersAndFreeze() public {
        _inventory();
        safe.setRejectEth(true);
        vm.expectRevert(IYieldManagerV2.TransferFailed.selector);
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
        assertFalse(manager.buffersRecovered());
        assertTrue(manager.executionEnabled());
        assertTrue(manager.intakeEnabled());
        assertEq(manager.pendingBold(), 5 ether);
        assertEq(manager.pendingSBold(), 5 ether);
        assertEq(manager.harvestInventory(0, 0), 1 ether);
        assertEq(boldToken.balanceOf(address(safe)), 0);
    }
    function test_AuthManifestAndBackingChecks() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.recoverBuffers(bytes32(uint256(1)));
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(0));
        _inventory();
        sBoldToken.burn(address(manager), 1);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
    }
}
