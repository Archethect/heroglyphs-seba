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
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { YBoldReleaseChecks } from "script/YBoldReleaseChecks.sol";

/**
 * @title YBoldMigrationPreflight
 * @notice Read-only release gate starting from treasury custody after the old user withdrawals.
 * @dev Protocol-owned old principal is inventoried separately: setYieldVault must still exit it.
 */
contract YBoldMigrationPreflight is Script {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    address internal constant YIELD_MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address internal constant OLD_BEEFY_VAULT = 0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba;
    address internal constant TREASURY = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant ST_YBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;

    /// @notice Reconciles manager IDs, custody, roles, implementation and release-specific expectations.
    function run() external view {
        require(block.chainid == 1, "CHAIN_ID");
        IYieldManager manager = IYieldManager(YIELD_MANAGER);
        address admin = vm.envAddress("YBOLD_MIGRATION_ADMIN");
        YBoldReleaseChecks.validate(admin, TREASURY, TREASURY);
        require(IAccessControl(YIELD_MANAGER).hasRole(manager.ADMIN_ROLE(), admin), "MIGRATION_ADMIN_ROLE");
        require(manager.pendingBoldConversion() == 0, "PENDING_BOLD_CONVERSION");
        require(manager.activeRouterUid() == bytes32(0), "ACTIVE_COW_INTENT");
        require(manager.yieldFlowActive(), "YIELD_FLOW_INACTIVE");
        require(manager.depositId() == vm.envUint("YBOLD_EXPECTED_DEPOSIT_ID"), "DEPOSIT_ID_CHANGED");
        address proxy = vm.envOr("YBOLD_VAULT", address(0));
        address active = address(manager.yieldVault());
        require(active == OLD_BEEFY_VAULT || (proxy != address(0) && active == proxy), "UNEXPECTED_ACTIVE_VAULT");
        uint256 userLiability = _userLiabilities(manager, proxy);
        console2.log("block", block.number);
        console2.log("treasury ETH", TREASURY.balance);
        console2.log("treasury ysyBOLD shares", IERC20(ST_YBOLD).balanceOf(TREASURY));
        console2.log("manager idle ETH", YIELD_MANAGER.balance);
        console2.log("manager protocol principal in active-vault native units", manager.principalValue());
        if (active == OLD_BEEFY_VAULT) {
            require(
                manager.principalValue() == vm.envUint("YBOLD_EXPECTED_OLD_PROTOCOL_VALUE"),
                "OLD_PROTOCOL_CHANGED"
            );
            require(TREASURY.balance == vm.envUint("YBOLD_EXPECTED_TREASURY_ETH"), "TREASURY_ETH_CHANGED");
            require(
                IERC20(ST_YBOLD).balanceOf(TREASURY) == vm.envUint("YBOLD_EXPECTED_TREASURY_SHARES"),
                "TREASURY_SHARES_CHANGED"
            );
            console2.log("setYieldVault still exits residual protocol principal; simulate that exit at this block");
        }
        if (proxy != address(0)) {
            YBoldYieldVault vault = YBoldYieldVault(payable(proxy));
            _validateNewVault(vault, admin);
            if (active == proxy) {
                require(vault.principalValue() == userLiability + manager.principalValue(), "LIABILITY_RECONCILIATION");
                require(vault.principalShares() <= IERC20(ST_YBOLD).balanceOf(proxy), "SHARE_SHORTFALL");
                IEUSDUSDCBeefyYieldVault oldVault = IEUSDUSDCBeefyYieldVault(OLD_BEEFY_VAULT);
                require(oldVault.principalShares() <= vm.envUint("YBOLD_MAX_OLD_SHARE_DUST"), "OLD_SHARES_DUST");
                require(oldVault.principalValue() <= vm.envUint("YBOLD_MAX_OLD_VALUE_DUST"), "OLD_VALUE_DUST");
            } else {
                require(vault.principalValue() == 0 && vault.principalShares() == 0, "NEW_VAULT_ALREADY_FUNDED");
                console2.log("setYieldVault calldata");
                console2.logBytes(abi.encodeCall(IYieldManager.setYieldVault, (proxy)));
            }
        }
        console2.log("depositPrincipalIntoYieldVault calldata; check actual manager idle ETH first");
        console2.logBytes(abi.encodeCall(IYieldManager.depositPrincipalIntoYieldVault, ()));
        console2.log("depositFunds calldata; attached ETH creates a new locked user deposit");
        console2.logBytes(abi.encodeCall(IYieldManager.depositFunds, ()));
    }

    function _userLiabilities(IYieldManager manager, address proxy) internal view returns (uint256 userLiability) {
        uint256 count = manager.depositId();
        require(count <= vm.envUint("YBOLD_MAX_DEPOSIT_SCAN"), "DEPOSIT_SCAN_LIMIT");
        for (uint256 id = 1; id <= count; ++id) {
            (address depositor, IYieldVault atDeposit, uint256 amount, uint32 unlockTime) = manager.deposits(id);
            if (amount == 0) {
                require(
                    depositor == address(0) && address(atDeposit) == address(0) && unlockTime == 0,
                    "PARTIAL_DELETE"
                );
                continue;
            }
            require(address(atDeposit) != OLD_BEEFY_VAULT, "OLD_USER_DEPOSIT_ACTIVE");
            require(proxy != address(0) && address(atDeposit) == proxy, "UNRECONCILED_OTHER_VAULT");
            userLiability += amount;
        }
    }

    function _validateNewVault(YBoldYieldVault vault, address admin) internal view {
        require(address(vault) == vm.envAddress("YBOLD_EXPECTED_PROXY"), "RELEASE_PROXY");
        require(address(vault).code.length != 0, "PROXY_CODE");
        require(address(vault).codehash == keccak256(type(ERC1967Proxy).runtimeCode), "PROXY_RUNTIME");
        address implementation = address(uint160(uint256(vm.load(address(vault), IMPLEMENTATION_SLOT))));
        require(
            implementation == vm.envAddress("YBOLD_EXPECTED_IMPLEMENTATION") && implementation.code.length != 0,
            "PROXY_IMPLEMENTATION"
        );
        require(
            implementation.codehash == vm.envBytes32("YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH"),
            "IMPLEMENTATION_CODEHASH"
        );
        require(
            YBoldYieldVault(payable(implementation)).proxiableUUID() == IMPLEMENTATION_SLOT,
            "IMPLEMENTATION_NOT_UUPS"
        );
        address upgrader = vm.envAddress("YBOLD_UPGRADE_AUTHORITY");
        address recoveryTreasury = vm.envAddress("YBOLD_RECOVERY_TREASURY");
        require(upgrader == TREASURY && recoveryTreasury == TREASURY && admin != upgrader, "APPROVED_AUTHORITIES");
        require(vault.hasRole(vault.ADMIN_ROLE(), admin), "VAULT_ADMIN_ROLE");
        require(vault.hasRole(vault.YIELDMANAGER_ROLE(), YIELD_MANAGER), "VAULT_MANAGER_ROLE");
        require(!vault.hasRole(vault.YIELDMANAGER_ROLE(), admin), "ROUTINE_ADMIN_MANAGER");
        require(vault.getRoleAdmin(vault.YIELDMANAGER_ROLE()) == vault.UPGRADER_ROLE(), "MANAGER_ROLE_ADMIN");
        require(vault.hasRole(vault.UPGRADER_ROLE(), upgrader), "VAULT_UPGRADER_ROLE");
        require(!vault.hasRole(vault.UPGRADER_ROLE(), admin), "ROUTINE_ADMIN_UPGRADER");
        require(vault.hasRole(vault.RECOVERY_ROLE(), recoveryTreasury), "VAULT_RECOVERY_ROLE");
        require(vault.recoveryTreasury() == recoveryTreasury, "RECOVERY_TREASURY");
        require(vault.getRoleAdmin(vault.UPGRADER_ROLE()) == vault.UPGRADER_ROLE(), "UPGRADER_ROLE_ADMIN");
        require(vault.getRoleAdmin(vault.RECOVERY_ROLE()) == vault.UPGRADER_ROLE(), "RECOVERY_ROLE_ADMIN");
        require(address(vault.stYBold()) == ST_YBOLD, "YSYBOLD");
        require(vault.WETH() == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "WETH");
        require(vault.USDC() == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, "USDC");
        require(vault.BOLD() == 0x6440f144b7e50D6a8439336510312d2F54beB01D, "BOLD");
        require(address(vault.yBold()) == 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8, "YBOLD");
        require(address(vault.curvePool()) == 0xEFc6516323FbD28e80B85A497B65A86243a54B3E, "CURVE");
        require(address(vault.swapRouter()) == 0xE592427A0AEce92De3Edee1F18E0157C05861564, "ROUTER");
        require(address(vault.ethUsdFeed()) == 0xc0053f3FBcCD593758258334Dfce24C2A9A673aD, "ETH_FEED");
        require(address(vault.usdcUsdFeed()) == 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, "USDC_FEED");
        require(vault.wethUsdcSlippageBps() == 50 && vault.boldUsdcSlippageBps() == 50, "SLIPPAGE");
        require(vault.maxBoldPegDeviationBps() == 100, "PEG");
        require(vault.normalYearnMaxLossBps() == 0 && vault.emergencyYearnMaxLossBps() == 100, "LOSS");
        require(!vault.emergencyMode() && !vault.paused(), "NOT_OPERATIONAL");
        require(vault.recoveryState() == IYBoldYieldVault.RecoveryState.Normal, "RECOVERY_STATE");
    }
}
