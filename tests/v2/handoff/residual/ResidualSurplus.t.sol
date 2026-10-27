// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { HandoffUnitBase } from "../HandoffUnitBase.sol";
import { LegacyProtocolPrincipalHandoff } from "src/v2/LegacyProtocolPrincipalHandoff.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";

contract HandoffResidualSurplusTest is HandoffUnitBase {
    function test_routerEthAtApprovedCapPassesAndOneWeiAboveAborts() public {
        _testOneCap(0);
    }

    function test_oldBoldAtApprovedCapPassesAndOneAtomAboveAborts() public {
        _testOneCap(1);
    }

    function test_oldSBoldAtApprovedCapPassesAndOneAtomAboveAborts() public {
        _testOneCap(2);
    }

    function test_routerBoldAtApprovedCapPassesAndOneAtomAboveAborts() public {
        _testOneCap(3);
    }

    function test_exactResidualsAreEmittedAfterSuccessfulAtomicImport() public {
        vm.deal(address(router), 1);
        bold.mint(address(old), 2);
        sbold.mint(address(old), 3);
        bold.mint(address(router), 4);

        ILegacyProtocolPrincipalHandoff.Configuration memory c = _configuration();
        c.maximumRouterEth = 1;
        c.maximumOldBold = 2;
        c.maximumOldSBold = 3;
        c.maximumRouterBold = 4;
        handoff = new LegacyProtocolPrincipalHandoff(c);
        _arm(handoff);
        _pre();
        _switch();
        _import();
        _finalPointers();

        vm.expectEmit(true, false, false, true, address(handoff));
        emit ILegacyProtocolPrincipalHandoff.ResidualSurplusObserved(MANIFEST, 1, 2, 3, 4);
        _post();

        assertEq(address(old).balance, 0);
        assertEq(address(destination).balance, ETH_BUDGET);
        assertEq(address(router).balance, 1);
        assertEq(bold.balanceOf(address(old)), 2);
        assertEq(sbold.balanceOf(address(old)), 3);
        assertEq(bold.balanceOf(address(router)), 4);
    }

    function test_residualAddedAfterPreflightAboveCapAbortsImport() public {
        ILegacyProtocolPrincipalHandoff.Configuration memory c = _configuration();
        c.maximumRouterEth = 1;
        handoff = new LegacyProtocolPrincipalHandoff(c);
        _arm(handoff);
        _pre();
        vm.deal(address(router), 2);
        _switch();
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _import();
        assertEq(address(old).balance, ETH_BUDGET);
        assertFalse(handoff.used());
    }

    function test_residualAddedAfterImportAboveCapAbortsPostcheck() public {
        ILegacyProtocolPrincipalHandoff.Configuration memory c = _configuration();
        c.maximumOldBold = 1;
        handoff = new LegacyProtocolPrincipalHandoff(c);
        _arm(handoff);
        _pre();
        _switch();
        _import();
        _finalPointers();
        bold.mint(address(old), 2);
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _post();
    }

    function test_residualCapsAreCommittedInConfigurationHash() public {
        ILegacyProtocolPrincipalHandoff.Configuration memory c = _configuration();
        bytes32 baseline = handoff.CONFIGURATION_HASH();
        for (uint256 i; i < 4; ++i) {
            c = _configuration();
            _setCap(c, i, 1);
            LegacyProtocolPrincipalHandoff h = new LegacyProtocolPrincipalHandoff(c);
            assertEq(h.CONFIGURATION_HASH(), keccak256(abi.encode(c)));
            assertTrue(h.CONFIGURATION_HASH() != baseline);
        }
    }

    function _testOneCap(uint256 index) private {
        _setResidual(index, 1);
        ILegacyProtocolPrincipalHandoff.Configuration memory c = _configuration();
        _setCap(c, index, 1);
        handoff = new LegacyProtocolPrincipalHandoff(c);
        _arm(handoff);
        _pre();

        _setResidual(index, 2);
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidState.selector);
        _pre();
    }

    function _setCap(
        ILegacyProtocolPrincipalHandoff.Configuration memory c,
        uint256 index,
        uint256 amount
    ) private pure {
        if (index == 0) c.maximumRouterEth = amount;
        else if (index == 1) c.maximumOldBold = amount;
        else if (index == 2) c.maximumOldSBold = amount;
        else c.maximumRouterBold = amount;
    }

    function _setResidual(uint256 index, uint256 amount) private {
        if (index == 0) vm.deal(address(router), amount);
        else if (index == 1) bold.mint(address(old), amount - bold.balanceOf(address(old)));
        else if (index == 2) sbold.mint(address(old), amount - sbold.balanceOf(address(old)));
        else bold.mint(address(router), amount - bold.balanceOf(address(router)));
    }
}
