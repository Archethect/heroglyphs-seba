// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { HandoffUnitBase } from "../HandoffUnitBase.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";
import { LegacyProtocolPrincipalHandoff } from "src/v2/LegacyProtocolPrincipalHandoff.sol";

contract HandoffDepositTest is HandoffUnitBase {
    function testFuzz_approvedWeightsAndOddWeiConserveOneHundredPercentProtocolCapital(
        uint16 weight,
        uint256 odd
    ) public {
        uint16 r = uint16(bound(weight, 0, 10000));
        odd = bound(odd, 0, 9999);
        vm.deal(address(old), ETH_BUDGET + odd);
        ILegacyProtocolPrincipalHandoff.Configuration memory c = _configuration();
        c.rethBps = r;
        c.expectedEth = ETH_BUDGET + odd;
        handoff = new LegacyProtocolPrincipalHandoff(c);
        destination.setWeights(r, 10000 - r);
        _arm(handoff);
        _pre();
        _switch();
        _import();
        _finalPointers();
        _post();
        uint256 rEth = destination.pendingEth(1);
        uint256 yEth = destination.pendingEth(2);
        assertEq(rEth + yEth, ETH_BUDGET + odd);
        assertEq(destination.pendingEth(0), 0);
        assertLe(rEth * 10000, (ETH_BUDGET + odd) * r);
        assertGt((rEth + 1) * 10000, (ETH_BUDGET + odd) * r);
        assertEq(address(destination).balance, ETH_BUDGET + odd);
    }
    function test_fullAtomicTypedSequenceAndResidueTelemetry() public {
        vm.deal(address(destination), 123);
        vm.deal(address(handoff), 456);
        _pre();
        _switch();
        _import();
        _finalPointers();
        _post();
        assertTrue(handoff.used());
        assertEq(old.principalValue(), 0);
        assertEq(address(old).balance, 0);
        assertEq(destination.pendingEth(0), 0);
        assertEq(destination.pendingEth(1), ETH_BUDGET / 2);
        assertEq(destination.pendingEth(2), ETH_BUDGET - ETH_BUDGET / 2);
        assertEq(address(destination).balance, ETH_BUDGET + 123);
        assertEq(address(handoff).balance, 456);
        assertEq(adapter.principalValue(), 150);
        assertEq(adapter.principalShares(), 121);
    }
    function test_actualLegacyUserDepositZeroReturnRollsBackEveryImportEffect() public {
        _pre();
        _switch();
        address user = address(0x5678);
        vm.deal(user, ETH_BUDGET);
        vm.prank(user);
        vm.expectRevert(IYieldManager.ZeroDepositValue.selector);
        old.depositFunds{ value: ETH_BUDGET }();
        assertFalse(handoff.used());
        assertFalse(destination.legacyImported());
        assertEq(destination.pendingEth(1), 0);
        assertEq(address(destination).balance, 0);
        assertEq(address(old).balance, ETH_BUDGET);
        assertEq(old.depositId(), 1);
        // The failed public attempt did not consume the approved admin route or its transient preflight.
        _import();
        _finalPointers();
        _post();
    }
    function test_wrongCallerAndNoAtomicPreflight() public {
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.Unauthorized.selector);
        handoff.deposit{ value: ETH_BUDGET }();
        vm.prank(address(old));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.MissingAtomicPreflight.selector);
        handoff.deposit();
    }
    function test_wrongAmountAndIntermediateState() public {
        _pre();
        vm.deal(address(old), ETH_BUDGET + 1);
        vm.prank(address(old));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.WrongAmount.selector);
        handoff.deposit{ value: 1 }();
        vm.deal(address(old), ETH_BUDGET);
        vm.prank(address(old));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        handoff.deposit{ value: ETH_BUDGET }();
        _mock(address(old), "yieldVault()", abi.encode(address(handoff)));
        _mock(address(old), "principalValue()", abi.encode(uint256(1)));
        vm.prank(address(old));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        handoff.deposit{ value: ETH_BUDGET }();
    }
    function test_importRevertAndReplayAreAtomic() public {
        _pre();
        _switch();
        destination.setReject(true);
        vm.expectRevert(bytes("synthetic import rejected"));
        _import();
        assertFalse(handoff.used());
        assertEq(address(old).balance, ETH_BUDGET);
        destination.setReject(false);
        _import();
        vm.prank(address(old));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.AlreadyUsed.selector);
        handoff.deposit();
        _finalPointers();
        _post();
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.AlreadyUsed.selector);
        _pre();
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.MissingAtomicPreflight.selector);
        _post();
    }
    function test_unsupportedAndUnrecognizedCallsCannotSweep() public {
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.UnsupportedOperation.selector);
        handoff.claimYield();
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.UnsupportedOperation.selector);
        handoff.retrievePrincipal(1);
        (bool ok, ) = address(handoff).call{ value: 1 }("");
        assertFalse(ok);
        (ok, ) = address(handoff).call(abi.encodeWithSignature("sweep(address)", address(bold)));
        assertFalse(ok);
    }
}
