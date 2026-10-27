// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { HandoffUnitBase } from "../HandoffUnitBase.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";

/// @notice Foundry executes setup and test as separate EVM transactions, exercising actual transient reset.
contract HandoffTransactionBoundaryTest is HandoffUnitBase {
    function setUp() public override {
        super.setUp();
        _pre();
    }
    function test_preflightFromPriorTransactionCannotAuthorizeImport() public {
        _switch();
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.MissingAtomicPreflight.selector);
        _import();
        assertFalse(handoff.used());
        assertEq(address(old).balance, ETH_BUDGET);
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _pre(); // No funds/state can be re-armed after switching: precheck must fail atomically on wrong old vault.
    }
}
