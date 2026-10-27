// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { HandoffUnitBase } from "../HandoffUnitBase.sol";
import { LegacyProtocolPrincipalHandoff } from "src/v2/LegacyProtocolPrincipalHandoff.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";

contract HandoffPreMigrationTest is HandoffUnitBase {
    function test_authorityChainAndExpiryBoundaries() public {
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.Unauthorized.selector);
        handoff.assertPreMigration();
        vm.chainId(handoff.chainId() + 1);
        _expectPre(ILegacyProtocolPrincipalHandoff.WrongChain.selector);
        vm.chainId(handoff.chainId());
        vm.warp(handoff.expiry() + 1);
        _expectPre(ILegacyProtocolPrincipalHandoff.Expired.selector);
        vm.warp(handoff.expiry());
        _pre();
    }
    function test_everyPinnedCodeIdentityIsChecked() public {
        address[5] memory targets = [address(old), address(adapter), address(router), address(pool), address(stopper)];
        for (uint256 i; i < targets.length; ++i) {
            bytes memory original = targets[i].code;
            vm.etch(targets[i], hex"00");
            _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
            vm.etch(targets[i], original);
        }
    }
    function test_everyPinnedLegacySnapshotFieldIsChecked() public {
        _mock(address(old), "yieldVault()", abi.encode(address(safe)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        _mock(address(old), "principalValue()", abi.encode(uint256(1)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        vm.deal(address(old), 1);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.deal(address(old), ETH_BUDGET);
        _mock(address(adapter), "principalValue()", abi.encode(uint256(1)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        _mock(address(adapter), "principalShares()", abi.encode(uint256(1)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        adapter.beefy().mint(address(adapter), 1);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
    }
    function test_legacyLinksAndInterveningDepositCounterAreChecked() public {
        _mock(address(old), "sebaPool()", abi.encode(address(safe)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        _mock(address(old), "router()", abi.encode(address(safe)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        pool.setYieldManager(address(safe));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        pool.setYieldManager(address(old));
        _mock(address(old), "depositId()", abi.encode(uint256(2)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
    }
    function test_aLiveLegacyClaimAbortsEvenWhenAllOtherSnapshotValuesMatch() public {
        // Explicitly construct an invalid staged snapshot with a live legacy claim; normal stopper intake cannot do this.
        vm.prank(address(safe));
        old.setYieldVault(address(adapter));
        address user = address(0x999);
        vm.deal(user, 1 ether);
        vm.prank(user);
        old.depositFunds{ value: 1 ether }();
        vm.prank(address(safe));
        old.setYieldVault(address(stopper));
        handoff = new LegacyProtocolPrincipalHandoff(_configuration());
        _arm(handoff);
        vm.expectRevert(abi.encodeWithSelector(ILegacyProtocolPrincipalHandoff.ActiveLegacyClaim.selector, 2));
        _pre();
    }
    function test_allPendingOrderAndCashStatesAbort() public {
        _mock(address(old), "pendingBoldConversion()", abi.encode(uint256(1)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        _mock(address(old), "activeRouterUid()", abi.encode(bytes32(uint256(1))));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        router.setActive(true);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        router.setActive(false);
        vm.deal(address(router), 1);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.deal(address(router), 0);
        _mock(address(bold), "balanceOf(address)", abi.encode(uint256(1)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        _mock(address(sbold), "balanceOf(address)", abi.encode(uint256(1)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        vm.clearMockedCalls();
        bold.mint(address(router), 1);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
    }
    function test_allDestinationIdentityAndImportPinsAbortWhenChanged() public {
        string[11] memory signatures = [
            "treasury()",
            "sebaPool()",
            "bold()",
            "sBold()",
            "pybSeba()",
            "legacyHandoff()",
            "legacyExpectedEth()",
            "legacyExpiry()",
            "legacyManifest()",
            "rethBps()",
            "ysyBoldBps()"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            _mock(address(destination), signatures[i], abi.encode(uint256(1)));
            _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
            vm.clearMockedCalls();
        }
    }
    function test_destinationMustBeArmedEmptyAndDisabled() public {
        string[6] memory signatures = [
            "legacyImported()",
            "intakeEnabled()",
            "executionEnabled()",
            "buffersRecovered()",
            "pendingBold()",
            "pendingSBold()"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            _mock(address(destination), signatures[i], abi.encode(uint256(1)));
            _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
            vm.clearMockedCalls();
        }
        for (uint256 i; i < 3; ++i) {
            vm.mockCall(
                address(destination),
                abi.encodeWithSignature("pendingEth(uint256)", i),
                abi.encode(uint256(1))
            );
            _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
            vm.clearMockedCalls();
        }
        for (uint8 leg; leg < 2; ++leg)
            for (uint8 bucket; bucket < 2; ++bucket) {
                vm.mockCall(
                    address(destination),
                    abi.encodeWithSignature("harvestInventory(uint8,uint8)", leg, bucket),
                    abi.encode(uint256(1))
                );
                _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
                vm.clearMockedCalls();
            }
    }
    function test_everySafeSecurityAssumptionIsChecked() public {
        address[] memory owners = new address[](1);
        owners[0] = address(0xaaa);
        safe.setOwners(owners);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        owners = new address[](3);
        owners[0] = address(0xaaa);
        owners[1] = address(0xbbb);
        owners[2] = address(0xccc);
        safe.setOwners(owners);
        safe.setThreshold(1);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        safe.setThreshold(2);
        safe.setModule(true, address(1));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        safe.setModule(false, address(2));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        safe.setModule(false, address(1));
        safe.setGuard(hex"");
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        safe.setGuard(abi.encode(uint256(1)));
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
    }
    function test_thresholdCannotExceedTheApprovedOwnerCount() public {
        safe.setThreshold(4);
        handoff = new LegacyProtocolPrincipalHandoff(_configuration());
        _arm(handoff);
        _expectPre(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
    }
}
