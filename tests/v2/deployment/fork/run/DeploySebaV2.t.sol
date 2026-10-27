// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { DeploySebaV2, IDeploymentSafe } from "../../../../../script/v2/DeploySebaV2.s.sol";
import { YieldManagerV2 } from "../../../../../src/v2/YieldManagerV2.sol";
import { RethSupporterVault } from "../../../../../src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "../../../../../src/v2/YsyBoldSupporterVault.sol";
import { SebaV2Executor } from "../../../../../src/v2/SebaV2Executor.sol";
import { IYieldManagerV2 } from "../../../../../src/interfaces/v2/IYieldManagerV2.sol";
import { IV2Executor } from "../../../../../src/interfaces/v2/IV2Executor.sol";

/// @notice Only disposable local fork deployment: no RPC transaction is sent by these tests.
contract DeploySebaV2ForkTest is Test {
    address internal constant SAFE = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant POOL = 0xe3B17b4533b339d3CBC26F57199d3fb937129894;
    address internal constant OLD = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    bytes32 internal constant INITIALIZABLE_SLOT = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    DeploySebaV2 internal script;
    bytes32 internal approvedOwnersHash;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), vm.envOr("SEBA_V2_FORK_BLOCK", uint256(26_255_670)));
        script = DeploySebaV2(deployCode("DeploySebaV2.s.sol:DeploySebaV2"));
        approvedOwnersHash = keccak256(abi.encode(IDeploymentSafe(SAFE).getOwners()));
    }

    function testFork_DeploysDisabledProxiesWithoutEOAAuthorityAndEmitsSafeBindingPayload() external {
        DeploySebaV2.Deployment memory d = script.run(approvedOwnersHash);
        YieldManagerV2 manager = YieldManagerV2(payable(d.manager));
        RethSupporterVault reth = RethSupporterVault(d.rethVault);
        YsyBoldSupporterVault ysy = YsyBoldSupporterVault(d.ysyBoldVault);
        assertEq(manager.treasury(), SAFE);
        assertEq(manager.sebaPool(), POOL);
        assertEq(manager.vaults(0), address(0));
        assertEq(manager.vaults(1), address(0));
        assertEq(address(manager.executor()), address(0));
        assertFalse(manager.intakeEnabled());
        assertFalse(manager.executionEnabled());
        assertFalse(manager.operators(address(this)));
        assertEq(manager.maximumEth(), 0);
        assertEq(manager.maximumYieldTokens(0), 0);
        assertEq(manager.maximumYieldTokens(1), 0);
        assertEq(manager.rethBps(), 5000);
        assertEq(manager.ysyBoldBps(), 5000);
        assertEq(reth.treasury(), SAFE);
        assertEq(ysy.treasury(), SAFE);
        assertEq(reth.manager(), d.manager);
        assertEq(ysy.manager(), d.manager);
        assertFalse(reth.entriesEnabled());
        assertFalse(reth.harvestEnabled());
        assertFalse(ysy.entriesEnabled());
        assertFalse(ysy.harvestEnabled());
        assertEq(reth.minimumBasis(), 0);
        assertEq(ysy.minimumBasis(), 0);
        assertEq(reth.maximumHarvest(), 0);
        assertEq(ysy.maximumHarvest(), 0);
        assertEq(reth.maximumReportAge(), 0);
        assertEq(reth.maximumReportBlockLag(), 0);
        assertFalse(SebaV2Executor(d.executor).enabled());
        IV2Executor.Limits memory empty;
        assertEq(abi.encode(SebaV2Executor(d.executor).limits()), abi.encode(empty));
        assertEq(SebaV2Executor(d.executor).manager(), d.manager);
        assertEq(SebaV2Executor(d.executor).treasury(), SAFE);
        _checkProxy(d.manager, d.managerImplementation);
        _checkProxy(d.rethVault, d.rethImplementation);
        _checkProxy(d.ysyBoldVault, d.ysyBoldImplementation);
        assertEq(d.safeOwnersHash, approvedOwnersHash);
        assertEq(d.bootstrapBindTo, d.manager);
        assertEq(d.bootstrapBindData, abi.encodeCall(manager.bindVaults, (d.rethVault, d.ysyBoldVault)));
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.bindVaults(d.rethVault, d.ysyBoldVault);
        // Test-only Safe impersonation demonstrates that the separate reviewed payload is usable.
        vm.prank(SAFE);
        (bool ok, ) = d.bootstrapBindTo.call(d.bootstrapBindData);
        assertTrue(ok);
        assertEq(manager.vaults(0), d.rethVault);
        assertEq(manager.vaults(1), d.ysyBoldVault);
    }

    function testFork_RejectsWrongChain() external {
        vm.chainId(2);
        _reject();
    }

    function testFork_RejectsMissingSafeCode() external {
        vm.etch(SAFE, "");
        _reject();
    }

    function testFork_RejectsOwnerDriftAndZeroApproval() external {
        vm.expectRevert(DeploySebaV2.PreflightFailed.selector);
        script.run(bytes32(0));
        address[] memory changed = IDeploymentSafe(SAFE).getOwners();
        changed[0] = makeAddr("changed owner");
        vm.mockCall(SAFE, abi.encodeCall(IDeploymentSafe.getOwners, ()), abi.encode(changed));
        _reject();
    }

    function testFork_RejectsWrongOwnerCount() external {
        address[] memory owners = new address[](1);
        owners[0] = address(this);
        vm.mockCall(SAFE, abi.encodeCall(IDeploymentSafe.getOwners, ()), abi.encode(owners));
        _reject();
    }

    function testFork_RejectsWrongThreshold() external {
        vm.mockCall(SAFE, abi.encodeCall(IDeploymentSafe.getThreshold, ()), abi.encode(uint256(1)));
        _reject();
    }

    function testFork_RejectsEnabledModule() external {
        address[] memory modules = new address[](1);
        modules[0] = address(this);
        vm.mockCall(
            SAFE,
            abi.encodeCall(IDeploymentSafe.getModulesPaginated, (address(1), 1)),
            abi.encode(modules, address(1))
        );
        _reject();
    }

    function testFork_RejectsUnexpectedModulePagination() external {
        address[] memory modules = new address[](0);
        vm.mockCall(
            SAFE,
            abi.encodeCall(IDeploymentSafe.getModulesPaginated, (address(1), 1)),
            abi.encode(modules, address(2))
        );
        _reject();
    }

    function testFork_RejectsGuardAndMalformedGuardResponse() external {
        bytes memory query = abi.encodeCall(
            IDeploymentSafe.getStorageAt,
            (uint256(0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8), 1)
        );
        vm.mockCall(SAFE, query, abi.encode(abi.encode(address(this))));
        _reject();
        vm.mockCall(SAFE, query, abi.encode(hex"00"));
        _reject();
    }

    function testFork_RejectsChangedPoolOrLegacyGraph() external {
        vm.mockCall(POOL, abi.encodeWithSignature("yieldManager()"), abi.encode(address(this)));
        _reject();
        vm.clearMockedCalls();
        vm.mockCall(OLD, abi.encodeWithSignature("sebaPool()"), abi.encode(address(this)));
        _reject();
        vm.clearMockedCalls();
        vm.mockCall(OLD, abi.encodeWithSignature("BOLD()"), abi.encode(address(this)));
        _reject();
    }

    function testFork_RejectsMissingWrappersAndDifferentPoolRewardVault() external {
        vm.mockCall(OLD, abi.encodeWithSignature("sBOLD()"), abi.encode(address(1)));
        _reject();
        vm.clearMockedCalls();
        vm.mockCall(OLD, abi.encodeWithSignature("sebaVault()"), abi.encode(address(1)));
        _reject();
        vm.clearMockedCalls();
        vm.mockCall(POOL, abi.encodeWithSignature("sebaVault()"), abi.encode(address(this)));
        _reject();
    }

    function _reject() private {
        uint64 nonce = vm.getNonce(address(this));
        vm.expectRevert(DeploySebaV2.PreflightFailed.selector);
        script.run(approvedOwnersHash);
        assertEq(vm.getNonce(address(this)), nonce, "preflight must precede contract creation");
    }

    function _checkProxy(address proxy, address implementation) private view {
        assertGt(proxy.code.length, 0);
        assertGt(implementation.code.length, 0);
        assertEq(address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT)))), implementation);
        assertEq(uint64(uint256(vm.load(implementation, INITIALIZABLE_SLOT))), type(uint64).max);
        assertEq(uint64(uint256(vm.load(proxy, INITIALIZABLE_SLOT))), 1);
    }
}
