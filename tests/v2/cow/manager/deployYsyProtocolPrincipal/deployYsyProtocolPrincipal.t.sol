// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../../../manager/ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { CowSettlementMock } from "../../CowMocks.sol";
import { ManagerCowTestBase } from "../ManagerCowTestBase.sol";

contract ManagerCowTestDeployYsyProtocolPrincipalTest is ManagerCowTestBase {
    function test_PrincipalSettlementNeverBecomesRewardsOrDoubleDebitsEth() public {
        (uint256 id, address escrow) = _openSource(1, 10 ether);
        assertEq(manager.pendingEth(2), 0);
        assertEq(manager.pendingBold(), 0);
        cowSettlement.fill(escrow, address(wethToken), address(boldToken), 10 ether, 100 ether);
        vm.prank(operator);
        manager.finalizeCowOrder(id);
        assertEq(manager.pendingProtocolBold(), 100 ether);
        assertEq(manager.pendingBold(), 0);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertBoldToSBold(1, 1, block.timestamp);
        vm.prank(operator);
        manager.deployYsyProtocolPrincipal(100 ether, 1, 1, block.timestamp);
        assertEq(manager.pendingProtocolBold(), 0);
        assertEq(yVault.protocolBasis(), 100 ether);
        assertEq(manager.pendingEth(2), 0);
        assertEq(manager.pendingEth(0), 20 ether);
        assertEq(boldToken.allowance(address(manager), address(execution)), 0);
        assertEq(ysyToken.allowance(address(manager), address(yVault)), 0);
    }

    function test_ProtocolDeploymentRejectsUnderfundingBadDeltasAndBadVaultReceipt() public {
        (uint256 id, address escrow) = _openSource(1, 1 ether);
        cowSettlement.fill(escrow, address(wethToken), address(boldToken), 1 ether, 10 ether);
        vm.prank(operator);
        manager.finalizeCowOrder(id);
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.deployYsyProtocolPrincipal(1, 1, 1, block.timestamp);
        for (uint8 i; i < 2; ++i) {
            vm.prank(operator);
            vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
            manager.deployYsyProtocolPrincipal(i == 0 ? 0 : 11 ether, 1, 1, block.timestamp);
        }
        for (uint8 i; i < 3; ++i) {
            execution.setMode(i == 2 ? 4 : i + 1);
            vm.prank(operator);
            vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
            manager.deployYsyProtocolPrincipal(10 ether, 1, 1, block.timestamp);
        }
        execution.setMode(0);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        manager.deployYsyProtocolPrincipal(10 ether, 11 ether, 1, block.timestamp);
        for (uint8 i = 1; i < 3; ++i) {
            yVault.setMode(i);
            vm.prank(operator);
            vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
            manager.deployYsyProtocolPrincipal(10 ether, 1, 1, block.timestamp);
        }
        yVault.setMode(0);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.Expired.selector);
        manager.deployYsyProtocolPrincipal(10 ether, 1, 1, block.timestamp - 1);
        vm.prank(address(safe));
        manager.setExecutionEnabled(false);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.ExecutionDisabled.selector);
        manager.deployYsyProtocolPrincipal(10 ether, 1, 1, block.timestamp);
        uint256 beforeSafe = boldToken.balanceOf(address(safe));
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(42)));
        assertEq(boldToken.balanceOf(address(safe)) - beforeSafe, 10 ether);
        assertEq(manager.pendingProtocolBold(), 0);
        assertEq(manager.pendingBold(), 0);
    }
}
