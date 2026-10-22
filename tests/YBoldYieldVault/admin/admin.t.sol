// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";
import { MockToken } from "tests/mocks/MockYBoldIntegrations.sol";

contract YBoldAdminTest is YBoldYieldVaultTestBase {
    function test_RevertWhenNonAdminCallsConfigurationMethods() external {
        bytes memory expected = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            address(this),
            vault.ADMIN_ROLE()
        );
        vm.expectRevert(expected);
        vault.setSwapSlippageBps(1, 1);
        vm.expectRevert(expected);
        vault.setMaxBoldPegDeviationBps(1);
        vm.expectRevert(expected);
        vault.setYearnMaxLossBps(0, 1);
        vm.expectRevert(expected);
        vault.setEmergencyMode(true);
        vm.expectRevert(expected);
        vault.pause();
        vm.expectRevert(expected);
        vault.unpause();
        vm.expectRevert(expected);
        vault.rescueToken(address(bold), address(this), 1);
    }

    function testFuzz_SetsSwapSlippageWithinHardCap(uint16 wethBps, uint16 boldBps) external {
        wethBps = uint16(bound(wethBps, 0, vault.MAX_SWAP_SLIPPAGE_BPS()));
        boldBps = uint16(bound(boldBps, 0, vault.MAX_SWAP_SLIPPAGE_BPS()));
        vm.prank(admin);
        vault.setSwapSlippageBps(wethBps, boldBps);
        assertEq(vault.wethUsdcSlippageBps(), wethBps);
        assertEq(vault.boldUsdcSlippageBps(), boldBps);
    }

    function test_RevertWhenEitherSwapSlippageExceedsHardCap() external {
        uint16 invalid = vault.MAX_SWAP_SLIPPAGE_BPS() + 1;
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.SlippageTooHigh.selector, invalid));
        vault.setSwapSlippageBps(invalid, 0);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.SlippageTooHigh.selector, invalid));
        vault.setSwapSlippageBps(0, invalid);
        vm.stopPrank();
    }

    function test_SetsPegDeviationWithinCapAndRejectsAboveCap() external {
        vm.startPrank(admin);
        vault.setMaxBoldPegDeviationBps(250);
        assertEq(vault.maxBoldPegDeviationBps(), 250);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.PegDeviationTooHigh.selector, 501));
        vault.setMaxBoldPegDeviationBps(501);
        vm.stopPrank();
    }

    function test_SetsOrderedYearnLossLimitsAndRejectsInvalidConfiguration() external {
        vm.startPrank(admin);
        vault.setYearnMaxLossBps(25, 200);
        assertEq(vault.normalYearnMaxLossBps(), 25);
        assertEq(vault.emergencyYearnMaxLossBps(), 200);
        assertEq(vault.currentYearnMaxLossBps(), 25);

        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.InvalidYearnLossConfiguration.selector, 201, 200));
        vault.setYearnMaxLossBps(201, 200);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.InvalidYearnLossConfiguration.selector, 0, 1001));
        vault.setYearnMaxLossBps(0, 1001);
        vm.stopPrank();
    }

    function test_EmergencyModeChangesActiveLossAndBlocksUnpause() external {
        vm.startPrank(admin);
        vault.pause();
        vault.setEmergencyMode(true);
        assertEq(vault.currentYearnMaxLossBps(), 100);
        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        vault.unpause();
        vault.setEmergencyMode(false);
        vault.unpause();
        assertFalse(vault.paused());
        assertEq(vault.currentYearnMaxLossBps(), 0);
        vm.stopPrank();
    }

    function test_PauseStateMachineRejectsDuplicateTransitions() external {
        vm.startPrank(admin);
        vault.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.pause();
        vault.unpause();
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vault.unpause();
        vm.stopPrank();
    }

    function test_RescuesOnlyNonCoreToken() external {
        MockToken accidental = new MockToken("Accidental", "ACC", 18);
        accidental.mint(address(vault), 10e18);
        vm.prank(admin);
        vault.rescueToken(address(accidental), stranger, 10e18);
        assertEq(accidental.balanceOf(stranger), 10e18);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.CoreAsset.selector, address(bold)));
        vault.rescueToken(address(bold), stranger, 1);
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        vault.rescueToken(address(accidental), address(0), 1);
        vm.expectRevert(IYBoldYieldVault.ZeroOutput.selector);
        vault.rescueToken(address(accidental), stranger, 0);
        vm.stopPrank();
    }

    function test_UpgradeAuthorityCanRotateYieldManagerRole() external {
        address replacement = makeAddr("replacement");
        vm.startPrank(upgrader);
        vault.grantRole(vault.YIELDMANAGER_ROLE(), replacement);
        vault.revokeRole(vault.YIELDMANAGER_ROLE(), address(manager));
        vm.stopPrank();
        assertTrue(vault.hasRole(vault.YIELDMANAGER_ROLE(), replacement));
        assertFalse(vault.hasRole(vault.YIELDMANAGER_ROLE(), address(manager)));
    }

    function test_RoutineAdminCannotGrantOrRevokeYieldManagerRole() external {
        bytes32 role = vault.YIELDMANAGER_ROLE();
        bytes memory unauthorized = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            admin,
            vault.UPGRADER_ROLE()
        );
        vm.startPrank(admin);
        vm.expectRevert(unauthorized);
        vault.grantRole(role, admin);
        vm.expectRevert(unauthorized);
        vault.revokeRole(role, address(manager));
        vm.stopPrank();
        assertFalse(vault.hasRole(role, admin));
        assertTrue(vault.hasRole(role, address(manager)));
    }
}
