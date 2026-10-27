// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ConvertBoldToSBoldTest is ManagerTestBase {
    function setUp() public override {
        super.setUp();
        _enable();
        _fund(40 ether);
        vm.prank(operator);
        manager.convertEthRewards(20 ether, 20 ether, block.timestamp);
    }
    function test_MintIsExactAndUnsolicitedBoldIsNotDonated() public {
        boldToken.mint(address(manager), 1 ether);
        vm.prank(operator);
        manager.convertBoldToSBold(10 ether, 10 ether, block.timestamp);
        assertEq(manager.pendingBold(), 10 ether);
        assertEq(manager.pendingSBold(), 10 ether);
        assertEq(boldToken.balanceOf(address(manager)), 11 ether);
        assertEq(boldToken.allowance(address(manager), address(sBoldToken)), 0);
    }
    function test_ZeroMinimumRejected() public {
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertBoldToSBold(1 ether, 0, block.timestamp);
    }
    function test_InvalidAmountsAndMinimum() public {
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertBoldToSBold(0, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.convertBoldToSBold(21 ether, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.InsufficientOutput.selector);
        vm.prank(operator);
        manager.convertBoldToSBold(1 ether, 2 ether, block.timestamp);
        assertEq(manager.pendingBold(), 20 ether);
        assertEq(manager.pendingSBold(), 0);
    }
    function test_ZeroOrMisreportedMintRollsBack() public {
        for (uint8 mode = 1; mode <= 2; ++mode) {
            sBoldToken.setMode(mode);
            vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
            vm.prank(operator);
            manager.convertBoldToSBold(1 ether, 1, block.timestamp);
            assertEq(manager.pendingBold(), 20 ether);
            assertEq(manager.pendingSBold(), 0);
        }
    }
    function test_CustodyDeficitRejects() public {
        boldToken.burn(address(manager), 1);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(operator);
        manager.convertBoldToSBold(1 ether, 1, block.timestamp);
    }
    function test_CanonicalPreviewFloorCannotBeLoweredByOperator() public {
        sBoldToken.setMode(3);
        vm.expectRevert(IYieldManagerV2.InsufficientOutput.selector);
        vm.prank(operator);
        manager.convertBoldToSBold(1 ether, 1, block.timestamp);
        sBoldToken.setMode(4);
        vm.expectRevert(IYieldManagerV2.InsufficientOutput.selector);
        vm.prank(operator);
        manager.convertBoldToSBold(1 ether, 1, block.timestamp);
        assertEq(manager.pendingBold(), 20 ether);
        assertEq(manager.pendingSBold(), 0);
    }
}
