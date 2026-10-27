// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { HandoffUnitBase } from "../HandoffUnitBase.sol";
import { LegacyProtocolPrincipalHandoff } from "src/v2/LegacyProtocolPrincipalHandoff.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";

contract HandoffConstructorTest is HandoffUnitBase {
    function test_stageBRequiresExitedZeroPrincipalAndExactKnownCash() public {
        ILegacyProtocolPrincipalHandoff.Configuration memory c = _configuration();
        c.oldPrincipal = 1;
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidConfiguration.selector);
        new LegacyProtocolPrincipalHandoff(c);
        c = _configuration();
        c.oldIdleEth = c.expectedEth + 1;
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidConfiguration.selector);
        new LegacyProtocolPrincipalHandoff(c);
        c = _configuration();
        c.stagingVault = address(safe);
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidConfiguration.selector);
        new LegacyProtocolPrincipalHandoff(c);
    }
    function test_eachInvalidImmutableConfigurationField() public {
        for (uint256 i; i < 16; ++i) {
            ILegacyProtocolPrincipalHandoff.Configuration memory c = _configuration();
            if (i < 7)
                assembly {
                    mstore(add(c, mul(i, 32)), 0)
                }
            else if (i == 7) c.destination = c.oldManager;
            else if (i == 8) c.expectedEth = 0;
            else if (i == 9) c.expiry = block.timestamp - 1;
            else if (i == 10) c.oldPrincipal = 1;
            else if (i == 11) c.oldIdleEth = c.expectedEth + 1;
            else if (i == 12) c.safeOwnersHash = 0;
            else if (i == 13) c.safeThreshold = 0;
            else if (i == 14) c.rethBps = 10001;
            else c.manifest = 0;
            vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidConfiguration.selector);
            new LegacyProtocolPrincipalHandoff(c);
        }
    }
    function test_nonContractCoreTokenIdentitiesCannotDeploy() public {
        ILegacyProtocolPrincipalHandoff.Configuration memory c = handoff.configuration();
        _mock(address(old), "BOLD()", abi.encode(address(1)));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidConfiguration.selector);
        new LegacyProtocolPrincipalHandoff(c);
        vm.clearMockedCalls();
        _mock(address(old), "sBOLD()", abi.encode(address(1)));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidConfiguration.selector);
        new LegacyProtocolPrincipalHandoff(c);
        vm.clearMockedCalls();
        _mock(address(adapter), "beefy()", abi.encode(address(1)));
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.InvalidConfiguration.selector);
        new LegacyProtocolPrincipalHandoff(c);
    }
    function test_configurationAndIdentityCommitmentsArePubliclyReconstructable() public view {
        ILegacyProtocolPrincipalHandoff.Configuration memory c = handoff.configuration();
        assertEq(handoff.CONFIGURATION_HASH(), keccak256(abi.encode(c)));
        assertEq(handoff.oldManager(), address(old));
        assertEq(handoff.destination(), address(destination));
        assertEq(handoff.treasury(), address(safe));
        assertEq(handoff.expectedEth(), destination.legacyExpectedEth());
        assertEq(handoff.expiry(), destination.legacyExpiry());
        assertEq(handoff.chainId(), block.chainid);
    }
}
