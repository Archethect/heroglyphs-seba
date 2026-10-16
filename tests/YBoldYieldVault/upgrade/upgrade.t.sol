// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";
import { YBoldYieldVaultV2Mock } from "tests/mocks/YBoldYieldVaultV2Mock.sol";

contract YBoldUpgradeTest is YBoldYieldVaultTestBase {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_OnlyUpgradeAuthorityCanUpgradeAndStorageIsPreserved() external {
        uint256 depositedValue = _deposit(1 ether);
        uint256 depositedShares = vault.principalShares();
        address wethBefore = vault.WETH();
        address treasuryBefore = vault.recoveryTreasury();
        YBoldYieldVaultV2Mock implementationV2 = new YBoldYieldVaultV2Mock(address(configValidator));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                vault.UPGRADER_ROLE()
            )
        );
        vault.upgradeToAndCall(address(implementationV2), abi.encodeCall(YBoldYieldVaultV2Mock.initializeV2, (42)));

        vm.prank(upgrader);
        vault.upgradeToAndCall(address(implementationV2), abi.encodeCall(YBoldYieldVaultV2Mock.initializeV2, (42)));

        YBoldYieldVaultV2Mock upgraded = YBoldYieldVaultV2Mock(payable(address(vault)));
        assertEq(upgraded.upgradeMarker(), 42);
        assertEq(upgraded.WETH(), wethBefore);
        assertEq(upgraded.recoveryTreasury(), treasuryBefore);
        assertEq(upgraded.principalValue(), depositedValue);
        assertEq(upgraded.principalShares(), depositedShares);
        assertEq(address(uint160(uint256(vm.load(address(vault), IMPLEMENTATION_SLOT)))), address(implementationV2));
    }

    function test_RevertWhenUpgradeTargetsAddressWithoutCode() external {
        vm.prank(upgrader);
        vm.expectRevert();
        vault.upgradeToAndCall(stranger, bytes(""));

        vm.prank(upgrader);
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        vault.upgradeToAndCall(address(0), bytes(""));
    }

    function test_RevertWhenV2InitializerIsReplayed() external {
        YBoldYieldVaultV2Mock implementationV2 = new YBoldYieldVaultV2Mock(address(configValidator));
        vm.prank(upgrader);
        vault.upgradeToAndCall(address(implementationV2), abi.encodeCall(YBoldYieldVaultV2Mock.initializeV2, (1)));

        vm.prank(upgrader);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        YBoldYieldVaultV2Mock(payable(address(vault))).initializeV2(2);
    }

    function test_RecoveryStorageAndFundingArePreservedAcrossUpgrade() external {
        uint256 value = _deposit(1 ether);
        uint256 shares = vault.principalShares();
        vm.prank(recoveryTreasury);
        vault.initiateRecovery();
        vm.deal(recoveryTreasury, 0.5 ether);
        vm.prank(recoveryTreasury);
        vault.fundRecovery{ value: 0.5 ether }();
        IYBoldYieldVault.RecoveryAccounting memory beforeAccounting = vault.recoveryAccounting();

        YBoldYieldVaultV2Mock implementationV2 = new YBoldYieldVaultV2Mock(address(configValidator));
        vm.prank(upgrader);
        vault.upgradeToAndCall(address(implementationV2), abi.encodeCall(YBoldYieldVaultV2Mock.initializeV2, (7)));

        YBoldYieldVaultV2Mock upgraded = YBoldYieldVaultV2Mock(payable(address(vault)));
        IYBoldYieldVault.RecoveryAccounting memory afterAccounting = upgraded.recoveryAccounting();
        assertEq(upgraded.upgradeMarker(), 7);
        assertEq(uint256(upgraded.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.SharesTransferred));
        assertEq(afterAccounting.principalSnapshot, beforeAccounting.principalSnapshot);
        assertEq(afterAccounting.sharesTransferred, beforeAccounting.sharesTransferred);
        assertEq(afterAccounting.ethFunded, beforeAccounting.ethFunded);
        assertEq(address(upgraded).balance, 0.5 ether);
        assertEq(stYBold.balanceOf(recoveryTreasury), shares);

        vm.prank(recoveryTreasury);
        upgraded.activateRecoverySettlement(0.5 ether);
        manager.retrieve(address(upgraded), value);
        assertEq(uint256(upgraded.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.Settled));
    }

    function test_RevertWhenUpgradeFunctionIsCalledOnImplementation() external {
        YBoldYieldVault implementation = new YBoldYieldVault(address(configValidator));
        YBoldYieldVaultV2Mock implementationV2 = new YBoldYieldVaultV2Mock(address(configValidator));

        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        implementation.upgradeToAndCall(address(implementationV2), bytes(""));
    }
}
