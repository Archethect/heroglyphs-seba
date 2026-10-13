// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";

/**
 * @title YBoldMigrationPreflight
 * @notice Read-only inventory, calldata preview, and pre/post invariant validator for the Option A migration.
 * @dev This script contains no broadcast cheatcode and cannot submit migration transactions.
 */
contract YBoldMigrationPreflight is Script {
    address internal constant YIELD_MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address internal constant OLD_BEEFY_VAULT = 0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba;
    address internal constant EXPECTED_DEPOSITOR = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant ST_YBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    uint256 internal constant FIRST_OLD_DEPOSIT_ID = 1;
    uint256 internal constant LAST_OLD_DEPOSIT_ID = 9;
    uint256 internal constant MAX_ACCEPTED_OLD_SHARES_DUST = 120;
    uint256 internal constant MAX_ACCEPTED_OLD_VALUE_DUST = 150;

    /**
     * @notice Validates either pre-migration or post-migration state based on the manager's active adapter.
     */
    function run() external view {
        require(block.chainid == 1, "CHAIN_ID");
        address newVaultAddress = vm.envAddress("YBOLD_VAULT");
        address migrationAdmin = vm.envAddress("YBOLD_MIGRATION_ADMIN");
        require(newVaultAddress.code.length > 0, "NEW_VAULT_CODE");

        IYieldManager manager = IYieldManager(YIELD_MANAGER);
        YBoldYieldVault newVault = YBoldYieldVault(payable(newVaultAddress));
        _validateShared(manager, newVault, migrationAdmin);

        if (address(manager.yieldVault()) == OLD_BEEFY_VAULT) {
            _validateBefore(manager, newVaultAddress);
        } else {
            require(address(manager.yieldVault()) == newVaultAddress, "UNEXPECTED_ACTIVE_VAULT");
            _validateAfter(manager, newVault);
        }
    }

    function _validateShared(IYieldManager manager, YBoldYieldVault newVault, address migrationAdmin) internal view {
        require(IAccessControl(YIELD_MANAGER).hasRole(manager.ADMIN_ROLE(), migrationAdmin), "MIGRATION_ADMIN_ROLE");
        require(newVault.hasRole(newVault.ADMIN_ROLE(), migrationAdmin), "VAULT_ADMIN_ROLE");
        require(newVault.hasRole(newVault.YIELDMANAGER_ROLE(), YIELD_MANAGER), "VAULT_MANAGER_ROLE");
        require(address(newVault.stYBold()) == ST_YBOLD, "ST_YBOLD");
        require(!newVault.emergencyMode() && !newVault.paused(), "NEW_VAULT_NOT_OPERATIONAL");
    }

    function _validateBefore(IYieldManager manager, address newVaultAddress) internal view {
        require(manager.pendingBoldConversion() == 0, "PENDING_BOLD_CONVERSION");
        require(manager.activeRouterUid() == bytes32(0), "ACTIVE_COW_INTENT");
        require(manager.yieldFlowActive(), "YIELD_FLOW_INACTIVE");
        require(manager.depositId() == LAST_OLD_DEPOSIT_ID, "DEPOSIT_ID_CHANGED");
        require(manager.principalValue() > 0, "NO_PROTOCOL_PRINCIPAL");

        uint256 userPrincipal;
        for (uint256 id = FIRST_OLD_DEPOSIT_ID; id <= LAST_OLD_DEPOSIT_ID; ++id) {
            (address depositor, IYieldVault vaultAtDeposit, uint256 amount, uint32 unlockTime) = manager.deposits(id);
            require(depositor == EXPECTED_DEPOSITOR, "UNEXPECTED_DEPOSITOR");
            require(address(vaultAtDeposit) == OLD_BEEFY_VAULT, "UNEXPECTED_DEPOSIT_VAULT");
            require(amount > 0, "MISSING_DEPOSIT");
            require(block.timestamp >= unlockTime, "DEPOSIT_LOCKED");
            userPrincipal += amount;
            console2.log("retrieveFunds deposit ID", id);
            console2.logBytes(abi.encodeCall(IYieldManager.retrieveFunds, (id)));
        }

        console2.log("user principal", userPrincipal);
        console2.log("protocol principal", manager.principalValue());
        console2.log("new yBOLD vault", newVaultAddress);
        console2.log("setYieldVault calldata");
        console2.logBytes(abi.encodeCall(IYieldManager.setYieldVault, (newVaultAddress)));
        console2.log("depositPrincipalIntoYieldVault calldata");
        console2.logBytes(abi.encodeCall(IYieldManager.depositPrincipalIntoYieldVault, ()));
        console2.log("depositFunds calldata (attach each depositor-chosen ETH tranche)");
        console2.logBytes(abi.encodeCall(IYieldManager.depositFunds, ()));
    }

    function _validateAfter(IYieldManager manager, YBoldYieldVault newVault) internal view {
        require(manager.principalValue() > 0, "PROTOCOL_PRINCIPAL_NOT_DEPLOYED");
        IEUSDUSDCBeefyYieldVault oldVault = IEUSDUSDCBeefyYieldVault(OLD_BEEFY_VAULT);
        require(oldVault.principalShares() <= MAX_ACCEPTED_OLD_SHARES_DUST, "OLD_SHARES_DUST");
        require(oldVault.principalValue() <= MAX_ACCEPTED_OLD_VALUE_DUST, "OLD_VALUE_DUST");
        require(
            newVault.principalShares() == IERC20(ST_YBOLD).balanceOf(address(newVault)),
            "NEW_SHARE_RECONCILIATION"
        );
        require(newVault.principalValue() >= manager.principalValue(), "NEW_VALUE_RECONCILIATION");
        console2.log("post-migration manager principal", manager.principalValue());
        console2.log("post-migration adapter principal", newVault.principalValue());
        console2.log("accepted old share dust", oldVault.principalShares());
        console2.log("accepted old value dust", oldVault.principalValue());
    }
}
