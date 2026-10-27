// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract RecognizeEthSurplusTest is ManagerTestBase {
    function test_OnlyExplicitUnassignedCashCanBeClassified() public {
        vm.deal(address(manager), 10);
        vm.startPrank(address(safe));
        manager.recognizeEthSurplus(0, 2);
        manager.recognizeEthSurplus(1, 3);
        manager.recognizeEthSurplus(2, 5);
        vm.stopPrank();
        assertEq(manager.pendingEth(0), 2);
        assertEq(manager.pendingEth(1), 3);
        assertEq(manager.pendingEth(2), 5);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(address(safe));
        manager.recognizeEthSurplus(0, 1);
    }
    function test_InvalidPurposeZeroExcessAndUnauthorized() public {
        vm.deal(address(manager), 10);
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.recognizeEthSurplus(0, 1);
        for (uint8 i; i < 3; ++i) {
            vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
            vm.prank(address(safe));
            manager.recognizeEthSurplus(i, 0);
        }
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(address(safe));
        manager.recognizeEthSurplus(3, 1);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(address(safe));
        manager.recognizeEthSurplus(0, 11);
    }
}
