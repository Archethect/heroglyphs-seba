// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { VaultBaseTest, VaultMockToken, VaultRethUpgrade } from "../VaultBase.t.sol";
import { RethSupporterVault } from "../../../../src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "../../../../src/v2/YsyBoldSupporterVault.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { NativeSupporterVault } from "../../../../src/v2/NativeSupporterVault.sol";

/// @dev Negative control for the abstract base's adapter-boundary invariant; neither production adapter emits denominator zero.
contract VaultInvalidRateAdapter is NativeSupporterVault {
    function initialize(address safe, address manager, address token) external initializer {
        __NativeSupporterVault_init(safe, manager, token, address(0));
    }
    function _readRate() internal pure override returns (uint256, uint256) {
        return (1, 0);
    }
    function _requireFresh() internal pure override {}
}

contract VaultInitializeTest is VaultBaseTest {
    function test_WhenAdapterViolatesPositiveDenominatorInvariant_ItRejectsUnusableCanonicalMath() external {
        VaultInvalidRateAdapter invalid = VaultInvalidRateAdapter(
            address(
                new ERC1967Proxy(
                    address(new VaultInvalidRateAdapter()),
                    abi.encodeCall(
                        VaultInvalidRateAdapter.initialize,
                        (address(safe), address(coordinator), address(token))
                    )
                )
            )
        );
        _expect(IV2SupporterVault.InvalidRate.selector);
        invalid.rateSnapshot();
    }
    function _newReth(address t, address m, address a, address s) private returns (RethSupporterVault) {
        address implementation = address(
            uint160(uint256(vm.load(address(vault), bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1))))
        );
        return
            RethSupporterVault(
                address(new ERC1967Proxy(implementation, abi.encodeCall(RethSupporterVault.initialize, (t, m, a, s))))
            );
    }
    function _newYearn(address t, address m, address a, address b) private returns (YsyBoldSupporterVault) {
        address implementation = address(
            uint160(uint256(vm.load(address(yvault), bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1))))
        );
        return
            YsyBoldSupporterVault(
                address(
                    new ERC1967Proxy(implementation, abi.encodeCall(YsyBoldSupporterVault.initialize, (t, m, a, b)))
                )
            );
    }
    function test_WhenInitializingProxy_ItStartsClosedUntilExplicitRiskConfiguration() external {
        RethSupporterVault fresh = _newReth(address(safe), address(coordinator), address(token), address(registry));
        assertFalse(fresh.entriesEnabled());
        assertFalse(fresh.harvestEnabled());
        vm.prank(address(safe));
        fresh.configureEntry(1, true);
        token.mint(alice, 1 ether);
        vm.prank(alice);
        token.approve(address(fresh), 1 ether);
        _expect(IV2SupporterVault.StaleReport.selector);
        vm.prank(alice);
        fresh.deposit(1 ether, 0, block.timestamp);
    }
    function test_WhenImplementationOrProxyReinitialized_ItRejectsEveryInitializer() external {
        RethSupporterVault implementation = new RethSupporterVault();
        vm.expectRevert();
        implementation.initialize(address(safe), address(coordinator), address(token), address(registry));
        vm.expectRevert();
        vault.initialize(address(safe), address(coordinator), address(token), address(registry));
        YsyBoldSupporterVault yimplementation = new YsyBoldSupporterVault();
        vm.expectRevert();
        yimplementation.initialize(address(safe), address(coordinator), address(yearn), address(ybold));
        vm.expectRevert();
        yvault.initialize(address(safe), address(coordinator), address(yearn), address(ybold));
    }
    function test_WhenIdentityZeroEOAOrWrongDecimals_ItCannotCreateUnsafeProxy() external {
        vm.expectRevert();
        _newReth(address(0), address(coordinator), address(token), address(registry));
        vm.expectRevert();
        _newReth(alice, address(coordinator), address(token), address(registry));
        vm.expectRevert();
        _newReth(address(safe), alice, address(token), address(registry));
        vm.expectRevert();
        _newReth(address(safe), address(coordinator), alice, address(registry));
        vm.expectRevert();
        _newReth(address(token), address(coordinator), address(token), address(registry));
        vm.expectRevert();
        _newReth(address(safe), address(token), address(token), address(registry));
        vm.expectRevert();
        _newReth(address(safe), address(coordinator), address(token), alice);
        token.setDecimals(6);
        vm.expectRevert();
        _newReth(address(safe), address(coordinator), address(token), address(registry));
        ybold.setDecimals(6);
        vm.expectRevert();
        _newYearn(address(safe), address(coordinator), address(yearn), address(ybold));
        vm.expectRevert();
        _newYearn(address(safe), address(coordinator), address(yearn), alice);
        address implementation = address(
            uint160(uint256(vm.load(address(vault), bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1))))
        );
        RethSupporterVault uninitialized = RethSupporterVault(address(new ERC1967Proxy(implementation, "")));
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        uninitialized.initialize(address(uninitialized), address(coordinator), address(yearn), address(registry));
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        uninitialized.initialize(address(safe), address(uninitialized), address(yearn), address(registry));
    }
    function test_WhenYearnBasisOrVersionWrong_ItRejectsSemanticMismatch() external {
        vm.expectRevert();
        _newYearn(address(safe), address(coordinator), address(yearn), address(0));
        VaultMockToken other = new VaultMockToken();
        vm.expectRevert();
        _newYearn(address(safe), address(coordinator), address(yearn), address(other));
        yearn.setVersion("3.1.0");
        vm.expectRevert();
        _newYearn(address(safe), address(coordinator), address(yearn), address(ybold));
        yearn.setVersion("3.0.4");
        yearn.setAsset(address(other));
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        yvault.rateSnapshot();
    }
    function test_WhenWrongBucketViews_ItRejectsRatherThanAliasingProtocolCapital() external {
        _expect(IV2SupporterVault.InvalidBucket.selector);
        vault.bucket(2);
        _expect(IV2SupporterVault.InvalidBucket.selector);
        vault.recoveryBucket(2);
        _expect(IV2SupporterVault.InvalidBucket.selector);
        vault.accounting(2);
        _expect(IV2SupporterVault.ClosedPosition.selector);
        vault.previewWithdraw(1);
    }
    function test_WhenYearnVersionChangesAfterEntry_ItFailsClosedInsteadOfReinterpretingPrincipal() external {
        _yDeposit(alice, 100 ether);
        yearn.setVersion("3.1.0");
        _expect(IV2SupporterVault.InvalidConfiguration.selector);
        yvault.rateSnapshot();
    }
    function test_GivenOpenPositionsAndRecovery_WhenSafeUpgrades_ItPreservesAllBasisLocksRolesAndBudgets() external {
        (uint256 id, ) = _deposit(alice, 100 ether);
        _protocol(30 ether);
        _recover();
        _fund(0, 100 ether, false);
        _fund(1, 30 ether, false);
        _activate(90 ether, 25 ether, false);
        uint256 unlock = vault.position(id).unlockAt;
        bytes32 instance = vault.recoveryInstance();
        bytes32 oldImplementation = vm.load(
            address(vault),
            bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
        );
        VaultRethUpgrade next = new VaultRethUpgrade();
        _expect(IV2SupporterVault.Unauthorized.selector);
        vault.upgradeToAndCall(address(next), "");
        _expect(IV2SupporterVault.Unauthorized.selector);
        vm.prank(operator);
        vault.upgradeToAndCall(address(next), "");
        vm.prank(address(safe));
        vault.upgradeToAndCall(address(next), "");
        VaultRethUpgrade upgraded = VaultRethUpgrade(address(vault));
        assertEq(upgraded.releaseVersion(), 2);
        assertEq(upgraded.position(id).unlockAt, unlock);
        assertEq(upgraded.position(id).basis, 100 ether);
        assertEq(upgraded.bucket(1).basis, 30 ether);
        assertEq(upgraded.recoveryBucket(0).budget, 90 ether);
        assertEq(upgraded.recoveryBucket(1).returnedTokens, 30 ether);
        assertEq(upgraded.recoveryInstance(), instance);
        assertEq(upgraded.initialManifest(), evidence);
        assertEq(upgraded.settlementManifest(), classification);
        assertTrue(upgraded.operators(operator));
        assertEq(upgraded.asset(), address(token));
        assertEq(upgraded.basisAsset(), address(0));
        assertEq(upgraded.manager(), address(coordinator));
        assertEq(upgraded.treasury(), address(safe));
        assertEq(upgraded.rocketStorage(), address(registry));
        assertEq(upgraded.maximumReportAge(), 2 days);
        assertNotEq(
            vm.load(address(vault), bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)),
            oldImplementation
        );
        _unlock();
        vm.prank(alice);
        assertEq(upgraded.withdraw(id, 90 ether, block.timestamp), 90 ether);
        vm.expectRevert();
        vm.prank(address(safe));
        upgraded.upgradeToAndCall(address(token), "");
        vm.expectRevert();
        upgraded.proxiableUUID();
        assertEq(next.proxiableUUID(), bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
    }
}
