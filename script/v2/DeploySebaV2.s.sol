// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { YieldManagerV2 } from "../../src/v2/YieldManagerV2.sol";
import { RethSupporterVault } from "../../src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "../../src/v2/YsyBoldSupporterVault.sol";
import { SebaV2Executor } from "../../src/v2/SebaV2Executor.sol";
import { IYieldManagerV2 } from "../../src/interfaces/v2/IYieldManagerV2.sol";
import { IV2Executor } from "../../src/interfaces/v2/IV2Executor.sol";

/// @title Deployment-only Safe identity views
/// @author Seba
/// @notice Prove the reviewed treasury role; no Safe transaction is submitted here.
interface IDeploymentSafe {
    /// @notice Read the ordered Safe signer list.
    /// @return owners Current signer addresses.
    function getOwners() external view returns (address[] memory owners);
    /// @notice Read the signature threshold.
    /// @return threshold Number of approvals required for execution.
    function getThreshold() external view returns (uint256 threshold);
    /// @notice Enumerate enabled Safe modules from the sentinel.
    /// @param start Sentinel or previous module address.
    /// @param pageSize Maximum number of module addresses returned.
    /// @return modules Enabled module addresses.
    /// @return next Next pagination address, or sentinel when complete.
    function getModulesPaginated(
        address start,
        uint256 pageSize
    ) external view returns (address[] memory modules, address next);
    /// @notice Read raw Safe storage, including the v1.3 guard slot.
    /// @param offset First storage slot.
    /// @param length Number of complete storage words.
    /// @return data Concatenated storage words.
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory data);
}

/// @title Deployment-only legacy identity views
/// @author Seba
/// @notice Resolve the existing reward graph instead of hardcoding its wrapper addresses.
interface IDeploymentLegacy {
    /// @notice Return the fixed legacy protocol pool.
    /// @return pool Existing SebaPool address.
    function sebaPool() external view returns (address pool);
    /// @notice Return the legacy BOLD integration.
    /// @return token Existing BOLD token.
    function BOLD() external view returns (address token);
    /// @notice Return the deployed sBOLD wrapper.
    /// @return token Existing sBOLD share token.
    function sBOLD() external view returns (address token);
    /// @notice Return the deployed perpetual reward vault.
    /// @return vault Existing pybSeba contract.
    function sebaVault() external view returns (address vault);
}

/// @title Deployment-only pool identity views
/// @author Seba
/// @notice Reject stale release assumptions before creating a candidate deployment.
interface IDeploymentPool {
    /// @notice Return the currently selected reward manager.
    /// @return manager Existing manager address.
    function yieldManager() external view returns (address manager);
    /// @notice Return the fixed perpetual reward vault.
    /// @return vault Existing pybSeba contract.
    function sebaVault() external view returns (address vault);
}

/// @title Disabled mainnet Seba V2 candidate deployment
/// @author Seba
/// @notice Runbook approval is required. This script never configures, enables, binds or migrates capital.
/// @dev The deployer never holds administration. The fixed Safe is authority from first initialization.
contract DeploySebaV2 is Script {
    address private constant SAFE = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address private constant POOL = 0xe3B17b4533b339d3CBC26F57199d3fb937129894;
    address private constant OLD = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address private constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address private constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address private constant YSY = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address private constant REGISTRY = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    uint256 private constant GUARD_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    /// @notice Public candidate addresses and separately reviewed Safe bootstrap payload.
    struct Deployment {
        address manager;
        address managerImplementation;
        address rethVault;
        address rethImplementation;
        address ysyBoldVault;
        address ysyBoldImplementation;
        address executor;
        bytes32 safeOwnersHash;
        address bootstrapBindTo;
        bytes bootstrapBindData;
    }

    /// @notice Target chain, reviewed Safe or legacy identity graph changed; no candidate should be deployed.
    error PreflightFailed();

    /// @notice Deploy disabled standard proxies and an unconfigured executor, emitting a public JSON manifest.
    /// @param approvedSafeOwnersHash Approved keccak256(abi.encode(Safe.getOwners())), preserving onchain order.
    /// @return d Candidate deployment and the Safe-only bindVaults payload; this function never executes that payload.
    function run(bytes32 approvedSafeOwnersHash) external returns (Deployment memory d) {
        (address sBold, address pybSeba) = _preflight(approvedSafeOwnersHash);
        vm.startBroadcast(msg.sender);
        d.managerImplementation = address(new YieldManagerV2());
        d.manager = address(
            new ERC1967Proxy(
                d.managerImplementation,
                abi.encodeCall(
                    YieldManagerV2.initialize,
                    (IYieldManagerV2.Initialization(SAFE, address(0), POOL, BOLD, sBold, pybSeba, RETH, YSY))
                )
            )
        );
        d.rethImplementation = address(new RethSupporterVault());
        d.rethVault = address(
            new ERC1967Proxy(
                d.rethImplementation,
                abi.encodeCall(RethSupporterVault.initialize, (SAFE, d.manager, RETH, REGISTRY))
            )
        );
        d.ysyBoldImplementation = address(new YsyBoldSupporterVault());
        d.ysyBoldVault = address(
            new ERC1967Proxy(
                d.ysyBoldImplementation,
                abi.encodeCall(YsyBoldSupporterVault.initialize, (SAFE, d.manager, YSY, YBOLD))
            )
        );
        d.executor = address(
            new SebaV2Executor(
                IV2Executor.Config(
                    d.manager,
                    SAFE,
                    RETH,
                    WETH,
                    USDC,
                    BOLD,
                    YBOLD,
                    YSY,
                    0xE592427A0AEce92De3Edee1F18E0157C05861564,
                    0xEFc6516323FbD28e80B85A497B65A86243a54B3E,
                    0xc0053f3FBcCD593758258334Dfce24C2A9A673aD,
                    0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
                    REGISTRY
                )
            )
        );
        vm.stopBroadcast();
        d.safeOwnersHash = approvedSafeOwnersHash;
        d.bootstrapBindTo = d.manager;
        d.bootstrapBindData = abi.encodeCall(YieldManagerV2.bindVaults, (d.rethVault, d.ysyBoldVault));
        _printManifest(d);
    }

    function _preflight(bytes32 approvedHash) private view returns (address sBold, address pybSeba) {
        if (block.chainid != 1 || approvedHash == bytes32(0) || SAFE.code.length == 0) revert PreflightFailed();
        IDeploymentSafe safe = IDeploymentSafe(SAFE);
        address[] memory owners = safe.getOwners();
        if (owners.length != 7 || safe.getThreshold() != 3 || keccak256(abi.encode(owners)) != approvedHash) {
            revert PreflightFailed();
        }
        (address[] memory modules, address next) = safe.getModulesPaginated(address(1), 1);
        if (modules.length != 0 || next != address(1)) revert PreflightFailed();
        bytes memory guard = safe.getStorageAt(GUARD_SLOT, 1);
        if (guard.length != 32 || abi.decode(guard, (uint256)) != 0) revert PreflightFailed();
        IDeploymentLegacy old = IDeploymentLegacy(OLD);
        if (IDeploymentPool(POOL).yieldManager() != OLD || old.sebaPool() != POOL || old.BOLD() != BOLD) {
            revert PreflightFailed();
        }
        sBold = old.sBOLD();
        pybSeba = old.sebaVault();
        if (sBold.code.length == 0 || pybSeba.code.length == 0 || IDeploymentPool(POOL).sebaVault() != pybSeba) {
            revert PreflightFailed();
        }
    }

    function _printManifest(Deployment memory d) private {
        string memory key = "seba-v2-candidate";
        vm.serializeString(key, "schema", "seba-v2-deployment-v1");
        vm.serializeUint(key, "chainId", 1);
        vm.serializeString(key, "phase", "unbound");
        vm.serializeAddress(key, "treasury", SAFE);
        vm.serializeAddress(key, "pool", POOL);
        vm.serializeAddress(key, "oldManager", OLD);
        vm.serializeAddress(key, "deployer", msg.sender);
        vm.serializeAddress(key, "initialOperator", address(0));
        vm.serializeAddress(key, "manager", d.manager);
        vm.serializeAddress(key, "managerImplementation", d.managerImplementation);
        vm.serializeAddress(key, "rethVault", d.rethVault);
        vm.serializeAddress(key, "rethImplementation", d.rethImplementation);
        vm.serializeAddress(key, "ysyBoldVault", d.ysyBoldVault);
        vm.serializeAddress(key, "ysyBoldImplementation", d.ysyBoldImplementation);
        vm.serializeAddress(key, "executor", d.executor);
        vm.serializeBytes32(key, "safeOwnersHash", d.safeOwnersHash);
        vm.serializeAddress(key, "bootstrapBindTo", d.bootstrapBindTo);
        console2.log(vm.serializeBytes(key, "bootstrapBindData", d.bootstrapBindData));
    }
}
