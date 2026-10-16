// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";

/**
 * @title YBoldMigrationPreflight
 * @notice Read-only inventory, calldata preview, and pre/post invariant validator for the Option A migration.
 * @dev This script contains no broadcast cheatcode and cannot submit migration transactions.
 */
contract YBoldMigrationPreflight is Script {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    address internal constant YIELD_MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address internal constant OLD_BEEFY_VAULT = 0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba;
    address internal constant EXPECTED_DEPOSITOR = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant ST_YBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    uint256 internal constant FIRST_OLD_DEPOSIT_ID = 1;
    uint256 internal constant LAST_OLD_DEPOSIT_ID = 9;
    uint256 internal constant MAX_ACCEPTED_OLD_SHARES_DUST = 120;
    uint256 internal constant MAX_ACCEPTED_OLD_VALUE_DUST = 150;

    /**
     * @notice Validates the current stage of a non-atomic migration, including partial unwind and idle ETH.
     */
    function run() external view {
        require(block.chainid == 1, "CHAIN_ID");
        address newVaultAddress = vm.envOr({ name: "YBOLD_VAULT", defaultValue: address(0) });
        address migrationAdmin = vm.envAddress("YBOLD_MIGRATION_ADMIN");

        IYieldManager manager = IYieldManager(YIELD_MANAGER);
        require(IAccessControl(YIELD_MANAGER).hasRole(manager.ADMIN_ROLE(), migrationAdmin), "MIGRATION_ADMIN_ROLE");
        if (newVaultAddress != address(0)) {
            require(newVaultAddress.code.length > 0, "NEW_VAULT_CODE");
            _validateNewVault(
                YBoldYieldVault(payable(newVaultAddress)),
                migrationAdmin,
                vm.envAddress("YBOLD_EXPECTED_IMPLEMENTATION"),
                vm.envAddress("YBOLD_UPGRADE_AUTHORITY"),
                vm.envAddress("YBOLD_RECOVERY_TREASURY")
            );
        }

        if (address(manager.yieldVault()) == OLD_BEEFY_VAULT) {
            _validateBefore(manager, newVaultAddress);
        } else {
            require(newVaultAddress != address(0), "NEW_VAULT_REQUIRED");
            require(address(manager.yieldVault()) == newVaultAddress, "UNEXPECTED_ACTIVE_VAULT");
            _validateAfter(manager, YBoldYieldVault(payable(newVaultAddress)));
        }
    }

    function _validateNewVault(
        YBoldYieldVault newVault,
        address migrationAdmin,
        address expectedImplementation,
        address upgradeAuthority,
        address recoveryTreasury
    ) internal view {
        address implementation = address(uint160(uint256(vm.load(address(newVault), IMPLEMENTATION_SLOT))));
        require(implementation == expectedImplementation && implementation.code.length > 0, "PROXY_IMPLEMENTATION");
        require(newVault.hasRole(newVault.ADMIN_ROLE(), migrationAdmin), "VAULT_ADMIN_ROLE");
        require(newVault.hasRole(newVault.YIELDMANAGER_ROLE(), YIELD_MANAGER), "VAULT_MANAGER_ROLE");
        require(newVault.hasRole(newVault.UPGRADER_ROLE(), upgradeAuthority), "VAULT_UPGRADER_ROLE");
        require(newVault.hasRole(newVault.RECOVERY_ROLE(), recoveryTreasury), "VAULT_RECOVERY_ROLE");
        require(newVault.recoveryTreasury() == recoveryTreasury, "RECOVERY_TREASURY");
        require(newVault.getRoleAdmin(newVault.UPGRADER_ROLE()) == newVault.UPGRADER_ROLE(), "UPGRADER_ROLE_ADMIN");
        require(newVault.getRoleAdmin(newVault.RECOVERY_ROLE()) == newVault.UPGRADER_ROLE(), "RECOVERY_ROLE_ADMIN");
        require(address(newVault.stYBold()) == ST_YBOLD, "ST_YBOLD");
        require(!newVault.emergencyMode() && !newVault.paused(), "NEW_VAULT_NOT_OPERATIONAL");
        require(newVault.recoveryState() == IYBoldYieldVault.RecoveryState.Normal, "RECOVERY_STATE");
        IYBoldYieldVault.RecoveryAccounting memory recovery = newVault.recoveryAccounting();
        require(
            recovery.principalSnapshot == 0 &&
                recovery.sharesTransferred == 0 &&
                recovery.ethFunded == 0 &&
                recovery.settlementEth == 0 &&
                recovery.payoutRateWad == 0 &&
                recovery.principalSettled == 0 &&
                recovery.ethPaid == 0,
            "RECOVERY_ACCOUNTING"
        );
    }

    function _validateBefore(IYieldManager manager, address newVaultAddress) internal view {
        require(manager.pendingBoldConversion() == 0, "PENDING_BOLD_CONVERSION");
        require(manager.activeRouterUid() == bytes32(0), "ACTIVE_COW_INTENT");
        require(manager.yieldFlowActive(), "YIELD_FLOW_INACTIVE");
        require(manager.depositId() == LAST_OLD_DEPOSIT_ID, "DEPOSIT_ID_CHANGED");
        require(manager.principalValue() > 0, "NO_PROTOCOL_PRINCIPAL");

        uint256 userPrincipal;
        uint256 activeOldDeposits;
        for (uint256 id = FIRST_OLD_DEPOSIT_ID; id <= LAST_OLD_DEPOSIT_ID; ++id) {
            (address depositor, IYieldVault vaultAtDeposit, uint256 amount, uint32 unlockTime) = manager.deposits(id);
            if (amount == 0) {
                require(depositor == address(0) && address(vaultAtDeposit) == address(0), "PARTIAL_DEPOSIT_DELETE");
                continue;
            }
            require(depositor == EXPECTED_DEPOSITOR, "UNEXPECTED_DEPOSITOR");
            require(address(vaultAtDeposit) == OLD_BEEFY_VAULT, "UNEXPECTED_DEPOSIT_VAULT");
            require(block.timestamp >= unlockTime, "DEPOSIT_LOCKED");
            userPrincipal += amount;
            ++activeOldDeposits;
            console2.log("retrieveFunds deposit ID", id);
            console2.logBytes(abi.encodeCall(IYieldManager.retrieveFunds, (id)));
        }
        require(activeOldDeposits == vm.envUint("YBOLD_EXPECTED_OLD_ACTIVE"), "OLD_ACTIVE_COUNT_CHANGED");

        console2.log("active old deposits", activeOldDeposits);
        console2.log("user principal", userPrincipal);
        console2.log("protocol principal", manager.principalValue());
        if (newVaultAddress != address(0)) {
            console2.log("new yBOLD vault", newVaultAddress);
            console2.log("setYieldVault calldata");
            console2.logBytes(abi.encodeCall(IYieldManager.setYieldVault, (newVaultAddress)));
        }
        console2.log("depositPrincipalIntoYieldVault calldata");
        console2.logBytes(abi.encodeCall(IYieldManager.depositPrincipalIntoYieldVault, ()));
        console2.log("depositFunds calldata (attach each depositor-chosen ETH tranche)");
        console2.logBytes(abi.encodeCall(IYieldManager.depositFunds, ()));
    }

    function _validateAfter(IYieldManager manager, YBoldYieldVault newVault) internal view {
        require(manager.yieldFlowActive(), "YIELD_FLOW_INACTIVE");
        for (uint256 id = FIRST_OLD_DEPOSIT_ID; id <= LAST_OLD_DEPOSIT_ID; ++id) {
            (, , uint256 amount, ) = manager.deposits(id);
            require(amount == 0, "OLD_DEPOSIT_STILL_ACTIVE");
        }
        require(manager.principalValue() > 0 || YIELD_MANAGER.balance > 0, "PROTOCOL_FUNDS_MISSING");
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
