// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ManagerProtocolDeployTest is ManagerTestBase {
    function test_ExecutionDisabledByDefault() public {
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.ExecutionDisabled.selector);
        manager.deployProtocolPrincipal(0, 1, 0, 0, block.timestamp);
    }
    function test_BothLegsCreditActualBackingWithoutSupporterClaims() public {
        _enable();
        _fund(8 ether);
        vm.startPrank(operator);
        manager.deployProtocolPrincipal(0, 2 ether, 2 ether, 2 ether, block.timestamp);
        manager.deployProtocolPrincipal(1, 2 ether, 2 ether, 2 ether, block.timestamp);
        vm.stopPrank();
        assertEq(rVault.protocolBasis(), 2 ether);
        assertEq(yVault.protocolBasis(), 2 ether);
        assertEq(rethToken.balanceOf(address(rVault)), 2 ether);
        assertEq(ysyToken.balanceOf(address(yVault)), 2 ether);
        assertEq(manager.pendingEth(0), 4 ether);
        assertEq(manager.pendingEth(1), 0);
        assertEq(manager.pendingEth(2), 0);
        assertEq(rethToken.allowance(address(manager), address(rVault)), 0);
        assertEq(ysyToken.allowance(address(manager), address(yVault)), 0);
    }
    function test_FailedRouteRollsBackAssignedCashAndMint() public {
        _enable();
        _fund(4 ether);
        execution.setMode(1);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        manager.deployProtocolPrincipal(0, 1 ether, 0, 0, block.timestamp);
        assertEq(manager.pendingEth(1), 1 ether);
        assertEq(address(manager).balance, 4 ether);
        assertEq(rethToken.totalSupply(), 0);
    }
    function test_UnexpectedRefundCannotMisreportEthSpent() public {
        _enable();
        _fund(4 ether);
        execution.setMode(3);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        manager.deployProtocolPrincipal(0, 1 ether, 0, 0, block.timestamp);
        assertEq(manager.pendingEth(1), 1 ether);
    }
    function test_FailedVaultCreditRollsBackWholeRoute() public {
        _enable();
        _fund(4 ether);
        rVault.setMode(2);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        manager.deployProtocolPrincipal(0, 1 ether, 0, 0, block.timestamp);
        assertEq(rethToken.totalSupply(), 0);
        assertEq(manager.pendingEth(1), 1 ether);
    }
    function test_UnauthorizedExpiredInvalidLegAndAmounts() public {
        _enable();
        _fund(4 ether);
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.deployProtocolPrincipal(0, 1, 0, 0, block.timestamp);
        vm.startPrank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidLeg.selector);
        manager.deployProtocolPrincipal(2, 1, 0, 0, block.timestamp);
        vm.expectRevert(IYieldManagerV2.Expired.selector);
        manager.deployProtocolPrincipal(0, 1, 0, 0, block.timestamp - 1);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        manager.deployProtocolPrincipal(0, 0, 0, 0, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        manager.deployProtocolPrincipal(0, 2 ether, 0, 0, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InsufficientOutput.selector);
        manager.deployProtocolPrincipal(0, 1 ether, 2 ether, 0, block.timestamp);
        vm.stopPrank();
    }
}
