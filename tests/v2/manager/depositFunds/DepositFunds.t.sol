// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ManagerDepositFundsTest is ManagerTestBase {
    function test_RejectsPublicETH() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.depositFunds{ value: 1 ether }();
    }
    function test_IntakeStartsDisabled() public {
        vm.expectRevert(IYieldManagerV2.IntakeDisabled.selector);
        _fund(1 ether);
    }
    function test_RejectsEmptyPoolReceipt() public {
        _enable();
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        _fund(0);
    }
    function testFuzz_ExactAssignmentAndFutureOnlyWeights(uint256 amount, uint16 r) public {
        amount = bound(amount, 1, 100_000 ether);
        r = uint16(bound(r, 0, 10_000));
        _enable();
        _fund(amount);
        uint256 beforeR = manager.pendingEth(1);
        uint256 beforeY = manager.pendingEth(2);
        vm.prank(address(safe));
        manager.setFutureInvestmentWeights(r, 10_000 - r);
        assertEq(manager.pendingEth(1), beforeR);
        assertEq(manager.pendingEth(2), beforeY);
        _fund(amount);
        uint256 investment = amount - amount / 2;
        assertEq(manager.pendingEth(0), 2 * (amount / 2));
        assertEq(manager.pendingEth(1), beforeR + (investment * r) / 10_000);
        assertEq(manager.pendingEth(2), beforeY + investment - (investment * r) / 10_000);
        assertEq(address(manager).balance, manager.pendingEth(0) + manager.pendingEth(1) + manager.pendingEth(2));
    }
    function test_OddWeiAndZeroWeightBoundaries() public {
        _enable();
        _fund(3);
        assertEq(manager.pendingEth(0), 1);
        assertEq(manager.pendingEth(1), 1);
        assertEq(manager.pendingEth(2), 1);
        vm.prank(address(safe));
        manager.setFutureInvestmentWeights(0, 10_000);
        _fund(1);
        assertEq(manager.pendingEth(2), 2);
        vm.prank(address(safe));
        manager.setFutureInvestmentWeights(10_000, 0);
        _fund(1);
        assertEq(manager.pendingEth(1), 2);
    }
    function test_ForcedETHNeedsExplicitClassification() public {
        _enable();
        vm.deal(address(manager), 9 ether);
        assertEq(manager.pendingEth(0), 0);
        vm.prank(address(safe));
        manager.recognizeEthSurplus(1, 9 ether);
        assertEq(manager.pendingEth(1), 9 ether);
        vm.prank(address(safe));
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        manager.recognizeEthSurplus(2, 1);
    }
}
