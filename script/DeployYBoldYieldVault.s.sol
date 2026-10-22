// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldConfigValidator } from "src/YBoldConfigValidator.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldReleaseChecks } from "script/YBoldReleaseChecks.sol";

/// @notice Safe configuration getters required by the deployment gate.
interface IYBoldTreasurySafe {
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
}

/**
 * @title DeployYBoldYieldVault
 * @notice Idempotently deploys the reviewed yBOLD implementation and its ERC-1967 UUPS proxy with CREATE2.
 * @dev Dry runs are the default. Source verification and broadcasting remain forbidden until migration Gate 2.
 */
contract DeployYBoldYieldVault is Script {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    struct DeploymentPlan {
        bytes32 validatorSalt;
        bytes32 implementationSalt;
        bytes32 proxySalt;
        address validator;
        address implementation;
        address proxy;
    }

    address internal constant YIELD_MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address internal constant TREASURY_SAFE = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address internal constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant BOLD_USDC_POOL = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address internal constant ST_YBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant ETH_USD_FEED = 0xc0053f3FBcCD593758258334Dfce24C2A9A673aD;
    address internal constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    /**
     * @notice Deploys or validates the implementation and proxy for the configured release.
     * @return deployed Adapter interface at the proxy address.
     */
    function run() external returns (YBoldYieldVault deployed) {
        require(block.chainid == 1, "CHAIN_ID");
        address expectedDeployer = vm.envAddress("YBOLD_EXPECTED_DEPLOYER");
        address admin = vm.envAddress("YBOLD_ADMIN");
        address upgradeAuthority = vm.envAddress("YBOLD_UPGRADE_AUTHORITY");
        address recoveryTreasury = vm.envAddress("YBOLD_RECOVERY_TREASURY");
        bytes32 versionSalt = vm.envBytes32("YBOLD_VERSION_SALT");
        require(expectedDeployer != address(0), "DEPLOYER");
        require(admin.code.length > 0, "ADMIN_NOT_CONTRACT");
        require(upgradeAuthority.code.length > 0, "UPGRADER_NOT_CONTRACT");
        require(recoveryTreasury.code.length > 0, "TREASURY_NOT_CONTRACT");
        require(upgradeAuthority != admin, "UPGRADER_NOT_SEPARATE");
        require(upgradeAuthority == TREASURY_SAFE && recoveryTreasury == TREASURY_SAFE, "APPROVED_TREASURY");
        uint256 threshold = IYBoldTreasurySafe(TREASURY_SAFE).getThreshold();
        address[] memory owners = IYBoldTreasurySafe(TREASURY_SAFE).getOwners();
        require(threshold >= 2 && threshold <= owners.length, "SAFE_THRESHOLD");
        require(threshold == vm.envUint("YBOLD_EXPECTED_SAFE_THRESHOLD"), "SAFE_THRESHOLD_CHANGED");
        require(owners.length == vm.envUint("YBOLD_EXPECTED_SAFE_OWNERS"), "SAFE_OWNERS_CHANGED");
        YBoldReleaseChecks.validate(admin, upgradeAuthority, recoveryTreasury);

        DeploymentPlan memory plan;
        plan.validatorSalt = keccak256(abi.encode(versionSalt, "YBOLD_CONFIG_VALIDATOR"));
        plan.implementationSalt = keccak256(abi.encode(versionSalt, "YBOLD_IMPLEMENTATION"));
        plan.proxySalt = keccak256(abi.encode(versionSalt, "YBOLD_PROXY"));
        plan.validator = vm.computeCreate2Address(
            plan.validatorSalt,
            keccak256(type(YBoldConfigValidator).creationCode),
            CREATE2_FACTORY
        );
        bytes memory implementationInitCode = abi.encodePacked(
            type(YBoldYieldVault).creationCode,
            abi.encode(plan.validator)
        );
        plan.implementation = vm.computeCreate2Address(
            plan.implementationSalt,
            keccak256(implementationInitCode),
            CREATE2_FACTORY
        );

        IYBoldYieldVault.InitializationParams memory params = IYBoldYieldVault.InitializationParams({
            admin: admin,
            yieldManager: YIELD_MANAGER,
            upgradeAuthority: upgradeAuthority,
            recoveryTreasury: recoveryTreasury,
            weth: WETH,
            usdc: USDC,
            bold: BOLD,
            router: SWAP_ROUTER,
            boldUsdcPool: BOLD_USDC_POOL,
            yearnBold: YBOLD,
            stakedYearnBold: ST_YBOLD,
            ethUsd: ETH_USD_FEED,
            usdcUsd: USDC_USD_FEED
        });
        bytes memory initialization = abi.encodeCall(YBoldYieldVault.initialize, (params));
        bytes memory proxyInitCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(plan.implementation, initialization)
        );
        plan.proxy = vm.computeCreate2Address(plan.proxySalt, keccak256(proxyInitCode), CREATE2_FACTORY);

        vm.startBroadcast(expectedDeployer);
        if (plan.validator.code.length == 0) {
            YBoldConfigValidator validator = new YBoldConfigValidator{ salt: plan.validatorSalt }();
            require(address(validator) == plan.validator, "VALIDATOR_ADDRESS");
        }
        if (plan.implementation.code.length == 0) {
            YBoldYieldVault implementation = new YBoldYieldVault{ salt: plan.implementationSalt }(plan.validator);
            require(address(implementation) == plan.implementation, "IMPLEMENTATION_ADDRESS");
        }
        if (plan.proxy.code.length == 0) {
            ERC1967Proxy proxy = new ERC1967Proxy{ salt: plan.proxySalt }(plan.implementation, initialization);
            require(address(proxy) == plan.proxy, "PROXY_ADDRESS");
        }
        vm.stopBroadcast();

        deployed = YBoldYieldVault(payable(plan.proxy));
        _validate(deployed, plan.validator, plan.implementation, admin, upgradeAuthority, recoveryTreasury);

        console2.log("YBoldConfigValidator", plan.validator);
        console2.log("YBoldYieldVault implementation", plan.implementation);
        console2.log("YBoldYieldVault proxy", plan.proxy);
        console2.log("Validator CREATE2 salt");
        console2.logBytes32(plan.validatorSalt);
        console2.log("Implementation CREATE2 salt");
        console2.logBytes32(plan.implementationSalt);
        console2.log("Proxy CREATE2 salt");
        console2.logBytes32(plan.proxySalt);
    }

    function _validate(
        YBoldYieldVault deployed,
        address expectedValidator,
        address expectedImplementation,
        address admin,
        address upgradeAuthority,
        address recoveryTreasury
    ) internal view {
        require(address(deployed).code.length > 0, "NO_PROXY_CODE");
        require(expectedValidator.codehash == keccak256(type(YBoldConfigValidator).runtimeCode), "VALIDATOR_CODE");
        require(address(deployed).codehash == keccak256(type(ERC1967Proxy).runtimeCode), "PROXY_CODE");
        address implementation = address(uint160(uint256(vm.load(address(deployed), IMPLEMENTATION_SLOT))));
        require(implementation == expectedImplementation && implementation.code.length > 0, "PROXY_IMPLEMENTATION");
        require(
            YBoldYieldVault(payable(implementation)).proxiableUUID() == IMPLEMENTATION_SLOT,
            "IMPLEMENTATION_NOT_UUPS"
        );
        require(deployed.hasRole(deployed.ADMIN_ROLE(), admin), "ADMIN_ROLE");
        require(deployed.hasRole(deployed.YIELDMANAGER_ROLE(), YIELD_MANAGER), "MANAGER_ROLE");
        require(!deployed.hasRole(deployed.YIELDMANAGER_ROLE(), admin), "ADMIN_IS_MANAGER");
        require(deployed.getRoleAdmin(deployed.YIELDMANAGER_ROLE()) == deployed.UPGRADER_ROLE(), "MANAGER_ROLE_ADMIN");
        require(deployed.hasRole(deployed.UPGRADER_ROLE(), upgradeAuthority), "UPGRADER_ROLE");
        require(!deployed.hasRole(deployed.UPGRADER_ROLE(), admin), "ADMIN_IS_UPGRADER");
        require(deployed.getRoleAdmin(deployed.UPGRADER_ROLE()) == deployed.UPGRADER_ROLE(), "UPGRADER_ROLE_ADMIN");
        require(deployed.hasRole(deployed.RECOVERY_ROLE(), recoveryTreasury), "RECOVERY_ROLE");
        require(deployed.recoveryTreasury() == recoveryTreasury, "RECOVERY_TREASURY");
        require(deployed.WETH() == WETH && deployed.USDC() == USDC && deployed.BOLD() == BOLD, "TOKENS");
        require(address(deployed.yBold()) == YBOLD && address(deployed.stYBold()) == ST_YBOLD, "YEARN");
        require(address(deployed.curvePool()) == BOLD_USDC_POOL, "CURVE");
        require(address(deployed.swapRouter()) == SWAP_ROUTER, "ROUTER");
        require(
            address(deployed.ethUsdFeed()) == ETH_USD_FEED && address(deployed.usdcUsdFeed()) == USDC_USD_FEED,
            "FEEDS"
        );
        require(deployed.wethUsdcSlippageBps() == 50 && deployed.boldUsdcSlippageBps() == 50, "SLIPPAGE");
        require(deployed.maxBoldPegDeviationBps() == 100, "PEG");
        require(deployed.normalYearnMaxLossBps() == 0 && deployed.emergencyYearnMaxLossBps() == 100, "LOSS");
        require(deployed.recoveryState() == IYBoldYieldVault.RecoveryState.Normal, "RECOVERY_STATE");
    }
}
