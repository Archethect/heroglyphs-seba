// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { DeployYBoldYieldVault } from "script/DeployYBoldYieldVault.s.sol";
import { UpgradeYBoldYieldVault } from "script/UpgradeYBoldYieldVault.s.sol";
import { YBoldMigrationPreflight } from "script/YBoldMigrationPreflight.s.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldConfigValidator } from "src/YBoldConfigValidator.sol";
import { YBoldYieldVaultV2Mock } from "tests/mocks/YBoldYieldVaultV2Mock.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { YBoldTreasuryRolloutForkTest } from "tests/fork/YBoldTreasuryRolloutFork.t.sol";
import { YBoldReleaseChecks } from "script/YBoldReleaseChecks.sol";

contract YBoldAuthorityValidationHarness {
    function validate(address admin, address upgrader, address treasury) external view {
        YBoldReleaseChecks.validate(admin, upgrader, treasury);
    }
}

contract YBoldDeploymentValidationHarness is DeployYBoldYieldVault {
    function validate(
        YBoldYieldVault proxy,
        address validator,
        address implementation,
        address admin,
        address treasury
    ) external view {
        _validate(proxy, validator, implementation, admin, treasury, treasury);
    }
}

/** @notice Serialized release guards are exercised on a pinned fork; nothing is broadcast or signed. */
contract YBoldReleaseScriptsTest is Test {
    address private constant ADMIN = 0xf83b11b09EEc073ACE4481b2F4c8357e156714b3;
    address private constant TREASURY = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address private constant MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    YBoldDeploymentValidationHarness private deployer;
    YBoldMigrationPreflight private preflight;
    UpgradeYBoldYieldVault private upgrade;
    YBoldYieldVault private adapter;
    YBoldYieldVault private implementation;
    YBoldConfigValidator private validator;

    function setUp() public {
        vm.clearMockedCalls();
        vm.createSelectFork(vm.envString("MAINNET_RPC"), 26_248_207);
        deployer = new YBoldDeploymentValidationHarness();
        preflight = new YBoldMigrationPreflight();
        upgrade = new UpgradeYBoldYieldVault();
        validator = new YBoldConfigValidator();
        implementation = new YBoldYieldVault(address(validator));
        IYBoldYieldVault.InitializationParams memory params = IYBoldYieldVault.InitializationParams({
            admin: ADMIN,
            yieldManager: MANAGER,
            upgradeAuthority: TREASURY,
            recoveryTreasury: TREASURY,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            bold: 0x6440f144b7e50D6a8439336510312d2F54beB01D,
            router: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            boldUsdcPool: 0xEFc6516323FbD28e80B85A497B65A86243a54B3E,
            yearnBold: 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8,
            stakedYearnBold: 0x23346B04a7f55b8760E5860AA5A77383D63491cD,
            ethUsd: 0xc0053f3FBcCD593758258334Dfce24C2A9A673aD,
            usdcUsd: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
        });
        adapter = YBoldYieldVault(
            payable(
                address(new ERC1967Proxy(address(implementation), abi.encodeCall(YBoldYieldVault.initialize, (params))))
            )
        );
        vm.setEnv("YBOLD_EXPECTED_DEPLOYER", vm.toString(address(0xDEED)));
        vm.setEnv("YBOLD_ADMIN", vm.toString(ADMIN));
        vm.setEnv("YBOLD_MIGRATION_ADMIN", vm.toString(ADMIN));
        vm.setEnv("YBOLD_UPGRADE_AUTHORITY", vm.toString(TREASURY));
        vm.setEnv("YBOLD_RECOVERY_TREASURY", vm.toString(TREASURY));
        vm.setEnv("YBOLD_VERSION_SALT", vm.toString(keccak256("release-script-local-test")));
        vm.setEnv("YBOLD_EXPECTED_SAFE_THRESHOLD", "3");
        vm.setEnv("YBOLD_EXPECTED_SAFE_OWNERS", "7");
        vm.setEnv("YBOLD_VAULT", vm.toString(address(adapter)));
        vm.setEnv("YBOLD_EXPECTED_PROXY", vm.toString(address(adapter)));
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION", vm.toString(address(implementation)));
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH", vm.toString(address(implementation).codehash));
        vm.setEnv("YBOLD_EXPECTED_DEPOSIT_ID", "9");
        vm.setEnv("YBOLD_MAX_DEPOSIT_SCAN", "100");
        vm.setEnv("YBOLD_EXPECTED_OLD_PROTOCOL_VALUE", "3033332133271012792310");
        vm.setEnv("YBOLD_EXPECTED_TREASURY_ETH", "0");
        vm.setEnv("YBOLD_EXPECTED_TREASURY_SHARES", "156014003721394916792917");
        vm.setEnv("YBOLD_MAX_OLD_SHARE_DUST", "121");
        vm.setEnv("YBOLD_MAX_OLD_VALUE_DUST", "150");
    }

    function test_SerializedReleaseGuardsAndFullCreate2Idempotency() external {
        // vm.setEnv mutates the host process. Keep every mutation in one test to prevent parallel-test races.
        new YBoldTreasuryRolloutForkTest().rehearseReleasePreflight();
        setUp();
        _deploymentValidation();
        setUp();
        _deploymentAuthorityDrift();
        setUp();
        _fullCreate2Idempotency();
        setUp();
        _preflightSnapshotDrift();
        setUp();
        _preflightCanonicalDrift();
        setUp();
        _upgradeCalldata();
        setUp();
        _authorityConfigurationDrift();
        setUp();
        _remainingDeploymentGuards();
        setUp();
        _remainingPreflightGuards();
        setUp();
        _remainingUpgradeGuards();
        setUp();
        _postRolloutDrift();
    }

    function _deploymentValidation() private {
        deployer.validate(adapter, address(validator), address(implementation), ADMIN, TREASURY);
        vm.expectRevert("NO_PROXY_CODE");
        deployer.validate(
            YBoldYieldVault(payable(address(0x1))),
            address(validator),
            address(implementation),
            ADMIN,
            TREASURY
        );
        vm.expectRevert("VALIDATOR_CODE");
        deployer.validate(adapter, ADMIN, address(implementation), ADMIN, TREASURY);
        vm.expectRevert("PROXY_IMPLEMENTATION");
        deployer.validate(adapter, address(validator), address(0x1), ADMIN, TREASURY);
        vm.expectRevert("ADMIN_ROLE");
        deployer.validate(adapter, address(validator), address(implementation), TREASURY, TREASURY);
        vm.expectRevert("UPGRADER_ROLE");
        deployer.validate(adapter, address(validator), address(implementation), ADMIN, ADMIN);
        vm.prank(ADMIN);
        adapter.setSwapSlippageBps(51, 50);
        vm.expectRevert("SLIPPAGE");
        deployer.validate(adapter, address(validator), address(implementation), ADMIN, TREASURY);
    }

    function _deploymentAuthorityDrift() private {
        vm.chainId(31337);
        vm.expectRevert("CHAIN_ID");
        deployer.run();
        vm.chainId(1);
        vm.setEnv("YBOLD_EXPECTED_DEPLOYER", vm.toString(address(0)));
        vm.expectRevert("DEPLOYER");
        deployer.run();
        vm.setEnv("YBOLD_EXPECTED_DEPLOYER", vm.toString(address(0xDEED)));
        vm.setEnv("YBOLD_ADMIN", vm.toString(address(0x1)));
        vm.expectRevert("ADMIN_NOT_CONTRACT");
        deployer.run();
        vm.setEnv("YBOLD_ADMIN", vm.toString(ADMIN));
        vm.setEnv("YBOLD_UPGRADE_AUTHORITY", vm.toString(address(0x1)));
        vm.expectRevert("UPGRADER_NOT_CONTRACT");
        deployer.run();
        vm.setEnv("YBOLD_UPGRADE_AUTHORITY", vm.toString(ADMIN));
        vm.expectRevert("UPGRADER_NOT_SEPARATE");
        deployer.run();
        vm.setEnv("YBOLD_UPGRADE_AUTHORITY", vm.toString(TREASURY));
        vm.setEnv("YBOLD_EXPECTED_SAFE_THRESHOLD", "2");
        vm.expectRevert("SAFE_THRESHOLD_CHANGED");
        deployer.run();
        vm.setEnv("YBOLD_EXPECTED_SAFE_THRESHOLD", "3");
        vm.setEnv("YBOLD_EXPECTED_SAFE_OWNERS", "6");
        vm.expectRevert("SAFE_OWNERS_CHANGED");
        deployer.run();
    }

    function _fullCreate2Idempotency() private {
        YBoldYieldVault first = deployer.run();
        YBoldYieldVault second = deployer.run();
        assertEq(address(first), address(second));
        assertEq(first.principalValue(), 0);
        assertEq(first.principalShares(), 0);
        assertTrue(first.hasRole(first.UPGRADER_ROLE(), TREASURY));
        assertFalse(first.hasRole(first.UPGRADER_ROLE(), ADMIN));
    }

    function _preflightSnapshotDrift() private {
        preflight.run();
        vm.setEnv("YBOLD_EXPECTED_DEPOSIT_ID", "8");
        vm.expectRevert("DEPOSIT_ID_CHANGED");
        preflight.run();
        vm.setEnv("YBOLD_EXPECTED_DEPOSIT_ID", "9");
        vm.setEnv("YBOLD_EXPECTED_OLD_PROTOCOL_VALUE", "0");
        vm.expectRevert("OLD_PROTOCOL_CHANGED");
        preflight.run();
        vm.setEnv("YBOLD_EXPECTED_OLD_PROTOCOL_VALUE", "3033332133271012792310");
        vm.setEnv("YBOLD_EXPECTED_TREASURY_ETH", "1");
        vm.expectRevert("TREASURY_ETH_CHANGED");
        preflight.run();
        vm.setEnv("YBOLD_EXPECTED_TREASURY_ETH", "0");
        vm.setEnv("YBOLD_EXPECTED_TREASURY_SHARES", "1");
        vm.expectRevert("TREASURY_SHARES_CHANGED");
        preflight.run();
        vm.setEnv("YBOLD_EXPECTED_TREASURY_SHARES", "156014003721394916792917");
        vm.setEnv("YBOLD_MAX_DEPOSIT_SCAN", "8");
        vm.expectRevert("DEPOSIT_SCAN_LIMIT");
        preflight.run();
    }

    function _preflightCanonicalDrift() private {
        _preflightDrift("WETH()", abi.encode(address(1)), "WETH");
        _preflightDrift("USDC()", abi.encode(address(1)), "USDC");
        _preflightDrift("BOLD()", abi.encode(address(1)), "BOLD");
        _preflightDrift("yBold()", abi.encode(address(1)), "YBOLD");
        _preflightDrift("stYBold()", abi.encode(address(1)), "YSYBOLD");
        _preflightDrift("curvePool()", abi.encode(address(1)), "CURVE");
        _preflightDrift("swapRouter()", abi.encode(address(1)), "ROUTER");
        _preflightDrift("ethUsdFeed()", abi.encode(address(1)), "ETH_FEED");
        _preflightDrift("usdcUsdFeed()", abi.encode(address(1)), "USDC_FEED");
        _preflightDrift("wethUsdcSlippageBps()", abi.encode(uint16(51)), "SLIPPAGE");
        _preflightDrift("boldUsdcSlippageBps()", abi.encode(uint16(51)), "SLIPPAGE");
        _preflightDrift("maxBoldPegDeviationBps()", abi.encode(uint16(101)), "PEG");
        _preflightDrift("normalYearnMaxLossBps()", abi.encode(uint16(1)), "LOSS");
        _preflightDrift("emergencyYearnMaxLossBps()", abi.encode(uint16(101)), "LOSS");
        _preflightDrift("paused()", abi.encode(true), "NOT_OPERATIONAL");
        _preflightDrift("emergencyMode()", abi.encode(true), "NOT_OPERATIONAL");
        _preflightDrift("recoveryState()", abi.encode(uint8(1)), "RECOVERY_STATE");
        _preflightDrift("principalValue()", abi.encode(uint256(1)), "NEW_VAULT_ALREADY_FUNDED");
        _preflightDrift("principalShares()", abi.encode(uint256(1)), "NEW_VAULT_ALREADY_FUNDED");
    }

    function _preflightDrift(string memory signature, bytes memory response, string memory reason) private {
        vm.mockCall(address(adapter), abi.encodePacked(bytes4(keccak256(bytes(signature)))), response);
        vm.expectRevert(bytes(reason));
        preflight.run();
        vm.clearMockedCalls();
    }

    function _upgradeCalldata() private {
        YBoldYieldVaultV2Mock next = new YBoldYieldVaultV2Mock(address(validator));
        vm.setEnv("YBOLD_NEXT_IMPLEMENTATION", vm.toString(address(next)));
        vm.setEnv("YBOLD_NEXT_IMPLEMENTATION_CODEHASH", vm.toString(address(next).codehash));
        bytes memory initialization = abi.encodeCall(YBoldYieldVaultV2Mock.initializeV2, (22));
        vm.setEnv("YBOLD_UPGRADE_CALLDATA", vm.toString(initialization));
        bytes memory data = upgrade.run();
        assertEq(data, abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(next), initialization));
        assertEq(address(uint160(uint256(vm.load(address(adapter), IMPLEMENTATION_SLOT)))), address(implementation));
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION", vm.toString(address(next)));
        vm.expectRevert("CURRENT_IMPLEMENTATION");
        upgrade.run();
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION", vm.toString(address(implementation)));
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH", vm.toString(bytes32(0)));
        vm.expectRevert("CURRENT_CODEHASH");
        upgrade.run();
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH", vm.toString(address(implementation).codehash));
        vm.setEnv("YBOLD_NEXT_IMPLEMENTATION_CODEHASH", vm.toString(bytes32(0)));
        vm.expectRevert("NEXT_CODEHASH");
        upgrade.run();
        vm.setEnv("YBOLD_NEXT_IMPLEMENTATION", vm.toString(address(adapter)));
        vm.expectRevert("UPGRADE_CODE");
        upgrade.run();
    }

    function _authorityConfigurationDrift() private {
        YBoldAuthorityValidationHarness checker = new YBoldAuthorityValidationHarness();
        checker.validate(ADMIN, TREASURY, TREASURY);
        vm.expectRevert("RELEASE_AUTHORITIES");
        checker.validate(TREASURY, TREASURY, TREASURY);
        vm.expectRevert("RELEASE_AUTHORITIES");
        checker.validate(ADMIN, ADMIN, TREASURY);
        vm.expectRevert("RELEASE_AUTHORITIES");
        checker.validate(ADMIN, TREASURY, ADMIN);
        vm.mockCall(TREASURY, abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(2)));
        vm.expectRevert("RELEASE_SAFE_THRESHOLD");
        checker.validate(ADMIN, TREASURY, TREASURY);
        vm.clearMockedCalls();
        address[] memory owners = new address[](7);
        vm.mockCall(TREASURY, abi.encodeWithSignature("getOwners()"), abi.encode(owners));
        vm.expectRevert("RELEASE_SAFE_OWNERS");
        checker.validate(ADMIN, TREASURY, TREASURY);
        vm.clearMockedCalls();
        address[] memory modules = new address[](1);
        modules[0] = address(0xBAD);
        vm.mockCall(
            TREASURY,
            abi.encodeWithSignature("getModulesPaginated(address,uint256)", address(1), 32),
            abi.encode(modules, address(1))
        );
        vm.expectRevert("RELEASE_SAFE_MODULES");
        checker.validate(ADMIN, TREASURY, TREASURY);
        modules = new address[](0);
        vm.mockCall(
            TREASURY,
            abi.encodeWithSignature("getModulesPaginated(address,uint256)", address(1), 32),
            abi.encode(modules, address(2))
        );
        vm.expectRevert("RELEASE_SAFE_MODULES");
        checker.validate(ADMIN, TREASURY, TREASURY);
        vm.clearMockedCalls();
        bytes memory slotCall = abi.encodeWithSignature(
            "getStorageAt(uint256,uint256)",
            uint256(0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8),
            1
        );
        vm.mockCall(TREASURY, slotCall, abi.encode(bytes("")));
        vm.expectRevert("RELEASE_SAFE_GUARD");
        checker.validate(ADMIN, TREASURY, TREASURY);
        vm.mockCall(TREASURY, slotCall, abi.encode(abi.encode(uint256(1))));
        vm.expectRevert("RELEASE_SAFE_GUARD");
        checker.validate(ADMIN, TREASURY, TREASURY);
        vm.clearMockedCalls();
    }

    function _remainingDeploymentGuards() private {
        _deploymentDrift(
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.YIELDMANAGER_ROLE(), ADMIN),
            abi.encode(true),
            "ADMIN_IS_MANAGER"
        );
        _deploymentDrift(
            abi.encodeWithSignature("getRoleAdmin(bytes32)", adapter.YIELDMANAGER_ROLE()),
            abi.encode(bytes32(0)),
            "MANAGER_ROLE_ADMIN"
        );
        vm.setEnv("YBOLD_RECOVERY_TREASURY", vm.toString(address(1)));
        vm.expectRevert("TREASURY_NOT_CONTRACT");
        deployer.run();
        vm.setEnv("YBOLD_RECOVERY_TREASURY", vm.toString(ADMIN));
        vm.expectRevert("APPROVED_TREASURY");
        deployer.run();
        vm.setEnv("YBOLD_RECOVERY_TREASURY", vm.toString(TREASURY));
        vm.mockCall(TREASURY, abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(1)));
        vm.expectRevert("SAFE_THRESHOLD");
        deployer.run();
        vm.clearMockedCalls();
        bytes memory runtime = address(adapter).code;
        vm.etch(address(adapter), hex"00");
        vm.expectRevert("PROXY_CODE");
        deployer.validate(adapter, address(validator), address(implementation), ADMIN, TREASURY);
        vm.etch(address(adapter), runtime);
        vm.mockCall(address(implementation), abi.encodeWithSignature("proxiableUUID()"), abi.encode(bytes32(0)));
        vm.expectRevert("IMPLEMENTATION_NOT_UUPS");
        deployer.validate(adapter, address(validator), address(implementation), ADMIN, TREASURY);
        vm.clearMockedCalls();
        _deploymentDrift(
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.YIELDMANAGER_ROLE(), MANAGER),
            abi.encode(false),
            "MANAGER_ROLE"
        );
        _deploymentDrift(
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.UPGRADER_ROLE(), ADMIN),
            abi.encode(true),
            "ADMIN_IS_UPGRADER"
        );
        _deploymentDrift(
            abi.encodeWithSignature("getRoleAdmin(bytes32)", adapter.UPGRADER_ROLE()),
            abi.encode(bytes32(0)),
            "UPGRADER_ROLE_ADMIN"
        );
        _deploymentDrift(
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.RECOVERY_ROLE(), TREASURY),
            abi.encode(false),
            "RECOVERY_ROLE"
        );
        string[9] memory signatures = [
            "recoveryTreasury()",
            "WETH()",
            "yBold()",
            "curvePool()",
            "swapRouter()",
            "ethUsdFeed()",
            "maxBoldPegDeviationBps()",
            "normalYearnMaxLossBps()",
            "recoveryState()"
        ];
        string[9] memory reasons = [
            "RECOVERY_TREASURY",
            "TOKENS",
            "YEARN",
            "CURVE",
            "ROUTER",
            "FEEDS",
            "PEG",
            "LOSS",
            "RECOVERY_STATE"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            _deploymentDrift(
                abi.encodePacked(bytes4(keccak256(bytes(signatures[i])))),
                abi.encode(uint256(1)),
                reasons[i]
            );
        }
    }

    function _deploymentDrift(bytes memory callData, bytes memory response, string memory reason) private {
        vm.mockCall(address(adapter), callData, response);
        vm.expectRevert(bytes(reason));
        deployer.validate(adapter, address(validator), address(implementation), ADMIN, TREASURY);
        vm.clearMockedCalls();
    }

    function _remainingPreflightGuards() private {
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.YIELDMANAGER_ROLE(), ADMIN),
            abi.encode(true),
            "ROUTINE_ADMIN_MANAGER"
        );
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("getRoleAdmin(bytes32)", adapter.YIELDMANAGER_ROLE()),
            abi.encode(bytes32(0)),
            "MANAGER_ROLE_ADMIN"
        );
        vm.chainId(31337);
        vm.expectRevert("CHAIN_ID");
        preflight.run();
        vm.chainId(1);
        _preflightExternalDrift(
            MANAGER,
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.ADMIN_ROLE(), ADMIN),
            abi.encode(false),
            "MIGRATION_ADMIN_ROLE"
        );
        _preflightExternalDrift(
            MANAGER,
            abi.encodeWithSignature("pendingBoldConversion()"),
            abi.encode(uint256(1)),
            "PENDING_BOLD_CONVERSION"
        );
        _preflightExternalDrift(
            MANAGER,
            abi.encodeWithSignature("activeRouterUid()"),
            abi.encode(bytes32(uint256(1))),
            "ACTIVE_COW_INTENT"
        );
        _preflightExternalDrift(
            MANAGER,
            abi.encodeWithSignature("yieldFlowActive()"),
            abi.encode(false),
            "YIELD_FLOW_INACTIVE"
        );
        _preflightExternalDrift(
            MANAGER,
            abi.encodeWithSignature("yieldVault()"),
            abi.encode(address(1)),
            "UNEXPECTED_ACTIVE_VAULT"
        );
        _preflightExternalDrift(
            MANAGER,
            abi.encodeWithSignature("deposits(uint256)", 1),
            abi.encode(ADMIN, address(0), uint256(0), uint32(0)),
            "PARTIAL_DELETE"
        );
        _preflightExternalDrift(
            MANAGER,
            abi.encodeWithSignature("deposits(uint256)", 1),
            abi.encode(ADMIN, address(0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba), uint256(1), uint32(0)),
            "OLD_USER_DEPOSIT_ACTIVE"
        );
        _preflightExternalDrift(
            MANAGER,
            abi.encodeWithSignature("deposits(uint256)", 1),
            abi.encode(ADMIN, address(1), uint256(1), uint32(0)),
            "UNRECONCILED_OTHER_VAULT"
        );
        vm.setEnv("YBOLD_EXPECTED_PROXY", vm.toString(address(1)));
        vm.expectRevert("RELEASE_PROXY");
        preflight.run();
        vm.setEnv("YBOLD_EXPECTED_PROXY", vm.toString(address(adapter)));
        bytes memory runtime = address(adapter).code;
        vm.etch(address(adapter), bytes(""));
        vm.expectRevert("PROXY_CODE");
        preflight.run();
        vm.etch(address(adapter), hex"00");
        vm.expectRevert("PROXY_RUNTIME");
        preflight.run();
        vm.etch(address(adapter), runtime);
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION", vm.toString(address(1)));
        vm.expectRevert("PROXY_IMPLEMENTATION");
        preflight.run();
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION", vm.toString(address(implementation)));
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH", vm.toString(bytes32(0)));
        vm.expectRevert("IMPLEMENTATION_CODEHASH");
        preflight.run();
        vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH", vm.toString(address(implementation).codehash));
        _preflightExternalDrift(
            address(implementation),
            abi.encodeWithSignature("proxiableUUID()"),
            abi.encode(bytes32(0)),
            "IMPLEMENTATION_NOT_UUPS"
        );
        vm.setEnv("YBOLD_UPGRADE_AUTHORITY", vm.toString(ADMIN));
        vm.expectRevert("APPROVED_AUTHORITIES");
        preflight.run();
        vm.setEnv("YBOLD_UPGRADE_AUTHORITY", vm.toString(TREASURY));
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.ADMIN_ROLE(), ADMIN),
            abi.encode(false),
            "VAULT_ADMIN_ROLE"
        );
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.YIELDMANAGER_ROLE(), MANAGER),
            abi.encode(false),
            "VAULT_MANAGER_ROLE"
        );
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.UPGRADER_ROLE(), TREASURY),
            abi.encode(false),
            "VAULT_UPGRADER_ROLE"
        );
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.UPGRADER_ROLE(), ADMIN),
            abi.encode(true),
            "ROUTINE_ADMIN_UPGRADER"
        );
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("hasRole(bytes32,address)", adapter.RECOVERY_ROLE(), TREASURY),
            abi.encode(false),
            "VAULT_RECOVERY_ROLE"
        );
        _preflightDrift("recoveryTreasury()", abi.encode(address(1)), "RECOVERY_TREASURY");
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("getRoleAdmin(bytes32)", adapter.UPGRADER_ROLE()),
            abi.encode(bytes32(0)),
            "UPGRADER_ROLE_ADMIN"
        );
        _preflightExternalDrift(
            address(adapter),
            abi.encodeWithSignature("getRoleAdmin(bytes32)", adapter.RECOVERY_ROLE()),
            abi.encode(bytes32(0)),
            "RECOVERY_ROLE_ADMIN"
        );
    }

    function _preflightExternalDrift(
        address target,
        bytes memory callData,
        bytes memory response,
        string memory reason
    ) private {
        vm.mockCall(target, callData, response);
        vm.expectRevert(bytes(reason));
        preflight.run();
        vm.clearMockedCalls();
    }

    function _remainingUpgradeGuards() private {
        YBoldYieldVaultV2Mock next = new YBoldYieldVaultV2Mock(address(validator));
        vm.setEnv("YBOLD_NEXT_IMPLEMENTATION", vm.toString(address(next)));
        vm.setEnv("YBOLD_NEXT_IMPLEMENTATION_CODEHASH", vm.toString(address(next).codehash));
        vm.chainId(31337);
        vm.expectRevert("CHAIN_ID");
        upgrade.run();
        vm.chainId(1);
        vm.setEnv("YBOLD_EXPECTED_PROXY", vm.toString(address(1)));
        vm.expectRevert("RELEASE_PROXY");
        upgrade.run();
        vm.setEnv("YBOLD_EXPECTED_PROXY", vm.toString(address(adapter)));
        vm.mockCall(address(next), abi.encodeWithSignature("proxiableUUID()"), abi.encode(bytes32(0)));
        vm.expectRevert("NEXT_NOT_UUPS");
        upgrade.run();
        vm.clearMockedCalls();
        bytes32 role = adapter.UPGRADER_ROLE();
        vm.prank(TREASURY);
        adapter.revokeRole(role, TREASURY);
        vm.expectRevert("SAFE_NOT_UPGRADER");
        upgrade.run();
    }

    function _postRolloutDrift() private {
        adapter = new YBoldTreasuryRolloutForkTest().rehearseReleasePreflight();
        preflight = new YBoldMigrationPreflight();
        _preflightDrift("principalValue()", abi.encode(uint256(1)), "LIABILITY_RECONCILIATION");
        _preflightDrift("principalShares()", abi.encode(type(uint256).max), "SHARE_SHORTFALL");
        vm.setEnv("YBOLD_MAX_OLD_SHARE_DUST", "120");
        vm.expectRevert("OLD_SHARES_DUST");
        preflight.run();
        vm.setEnv("YBOLD_MAX_OLD_SHARE_DUST", "121");
        vm.setEnv("YBOLD_MAX_OLD_VALUE_DUST", "149");
        vm.expectRevert("OLD_VALUE_DUST");
        preflight.run();
    }
}
