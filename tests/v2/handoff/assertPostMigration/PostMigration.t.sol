// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { HandoffUnitBase } from "../HandoffUnitBase.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";

contract HandoffPostMigrationTest is HandoffUnitBase {
    function test_postassertNeedsAuthorityAndSameTransactionImport() public {
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.Unauthorized.selector);
        handoff.assertPostMigration();
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.MissingAtomicPreflight.selector);
        _post();
    }
    function test_missingFinalPointersAndOldCashAbort() public {
        _pre();
        _switch();
        _import();
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _post();
        _finalPointers();
        vm.deal(address(old), 1);
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _post();
        vm.deal(address(old), 0);
        _mock(address(old), "yieldVault()", abi.encode(address(adapter)));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _post();
        vm.clearMockedCalls();
        _mock(address(old), "principalValue()", abi.encode(uint256(1)));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _post();
        vm.clearMockedCalls();
        _post();
    }
    function test_everyFinalDestinationAccountingConditionIsChecked() public {
        _pre();
        _switch();
        _import();
        _finalPointers();
        string[4] memory signatures = [
            "legacyImported()",
            "intakeEnabled()",
            "executionEnabled()",
            "buffersRecovered()"
        ];
        for (uint256 i; i < 4; ++i) {
            _mock(address(destination), signatures[i], abi.encode(i < 2 ? uint256(0) : uint256(1)));
            vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
            _post();
            vm.clearMockedCalls();
        }
        for (uint256 i; i < 3; ++i) {
            uint256 correct = destination.pendingEth(i);
            destination.setPending(uint8(i), correct + 1);
            vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
            _post();
            destination.setPending(uint8(i), correct);
        }
        vm.deal(address(destination), ETH_BUDGET + 1);
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _post();
        vm.deal(address(destination), ETH_BUDGET);
        _post();
    }
}
