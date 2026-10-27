// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
contract SetOperatorTest is ManagerTestBase {
    function test_EveryMaintenanceEntryRejectsAnUnprivilegedCaller() public {
        bytes[] memory calls = new bytes[](5);
        calls[0] = abi.encodeCall(manager.deployProtocolPrincipal, (0, 1, 1, 1, block.timestamp));
        calls[1] = abi.encodeCall(manager.convertEthRewards, (1, 1, block.timestamp));
        calls[2] = abi.encodeCall(manager.convertHarvest, (0, 0, 1, 1, block.timestamp));
        calls[3] = abi.encodeCall(manager.convertBoldToSBold, (1, 1, block.timestamp));
        calls[4] = abi.encodeCall(manager.donateSBold, (1));
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory reason) = address(manager).call(calls[i]);
            assertFalse(ok);
            assertEq(reason, abi.encodeWithSelector(IYieldManagerV2.Unauthorized.selector));
        }
    }
    function test_SafeGrantsAndRevokesOnlyBoundedOperations() public {
        address next = makeAddr("new backend");
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        vm.prank(operator);
        manager.setOperator(next, true);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setOperator(address(0), true);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setOperator(address(safe), true);
        vm.prank(address(safe));
        manager.setOperator(next, true);
        assertTrue(manager.operators(next));
        vm.prank(address(safe));
        manager.setOperator(next, false);
        assertFalse(manager.operators(next));
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        vm.prank(next);
        manager.donateSBold(1);
    }
}
