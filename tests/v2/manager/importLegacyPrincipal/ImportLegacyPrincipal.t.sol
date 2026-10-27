// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { ManagerHandoffMock } from "../armLegacyImport/ArmLegacyImport.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ImportLegacyPrincipalTest is ManagerTestBase {
    ManagerHandoffMock internal h;
    function setUp() public override {
        super.setUp();
        h = new ManagerHandoffMock(address(manager), 11, block.timestamp + 100, block.chainid);
        uint256 end = h.expiry();
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 11, end, bytes32(uint256(1)));
        vm.deal(address(h), 100);
    }
    function test_ExactlyOnceAllInvestmentWithoutRewardHaircut() public {
        vm.prank(address(h));
        manager.importLegacyPrincipal{ value: 11 }();
        assertTrue(manager.legacyImported());
        assertEq(manager.pendingEth(0), 0);
        assertEq(manager.pendingEth(1), 5);
        assertEq(manager.pendingEth(2), 6);
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(h));
        manager.importLegacyPrincipal{ value: 11 }();
        vm.prank(address(safe));
        manager.setFutureInvestmentWeights(0, 10_000);
        assertEq(manager.weightVersion(), 2);
    }
    function test_WrongCallerValueExpiryAndRecoveredReject() public {
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        manager.importLegacyPrincipal{ value: 11 }();
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(h));
        manager.importLegacyPrincipal{ value: 10 }();
        vm.warp(h.expiry() + 1);
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(h));
        manager.importLegacyPrincipal{ value: 11 }();
        vm.warp(h.expiry());
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(h));
        manager.importLegacyPrincipal{ value: 11 }();
    }
}
