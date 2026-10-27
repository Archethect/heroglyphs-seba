// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract DonateSBoldTest is ManagerTestBase {
    function setUp() public override {
        super.setUp();
        _enable();
        _fund(40 ether);
        vm.startPrank(operator);
        manager.convertEthRewards(20 ether, 1, block.timestamp);
        manager.convertBoldToSBold(20 ether, 1, block.timestamp);
        vm.stopPrank();
    }
    function test_DonationCountsOnlyClassifiedSharesAndClearsApproval() public {
        sBoldToken.mint(address(manager), 1 ether);
        vm.prank(operator);
        manager.donateSBold(20 ether);
        assertEq(manager.pendingSBold(), 0);
        assertEq(sBoldToken.balanceOf(address(sink)), 20 ether);
        assertEq(sBoldToken.balanceOf(address(manager)), 1 ether);
        assertEq(sBoldToken.allowance(address(manager), address(sink)), 0);
    }
    function test_ZeroExcessAndUnavailableSinkReject() public {
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.donateSBold(0);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.donateSBold(21 ether);
        sink.setBroken(true);
        vm.expectRevert(bytes("test sink unavailable"));
        vm.prank(operator);
        manager.donateSBold(1 ether);
        assertEq(manager.pendingSBold(), 20 ether);
    }
    function test_MissingSBoldBackingRejects() public {
        sBoldToken.burn(address(manager), 1);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(operator);
        manager.donateSBold(1);
    }
    function test_SafeCanMaintainButRecipientDeltaMustBeExact() public {
        vm.prank(address(safe));
        manager.donateSBold(1 ether);
        assertEq(manager.pendingSBold(), 19 ether);
        vm.mockCall(
            address(sBoldToken),
            abi.encodeWithSignature("balanceOf(address)", address(sink)),
            abi.encode(uint256(0))
        );
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(operator);
        manager.donateSBold(1 ether);
        assertEq(manager.pendingSBold(), 19 ether);
    }
}
