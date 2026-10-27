// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase, ManagerTokenMock } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract RescueTokenTest is ManagerTestBase {
    function test_OnlyNoncoreGoesToFixedSafe() public {
        ManagerTokenMock accidental = new ManagerTokenMock(address(0));
        accidental.mint(address(manager), 15);
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.rescueToken(address(accidental), 15);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(address(safe));
        manager.rescueToken(address(accidental), 0);
        vm.prank(address(safe));
        manager.rescueToken(address(accidental), 15);
        assertEq(accidental.balanceOf(address(safe)), 15);
        assertEq(accidental.balanceOf(address(manager)), 0);
    }
    function test_EveryCoreIdentityIsBlocked() public {
        _enable();
        address[7] memory tokens = [
            address(boldToken),
            address(sBoldToken),
            address(rethToken),
            address(ysyToken),
            address(yBoldToken),
            address(wethToken),
            address(usdcToken)
        ];
        for (uint256 i; i < tokens.length; ++i) {
            vm.expectRevert(IYieldManagerV2.CoreAsset.selector);
            vm.prank(address(safe));
            manager.rescueToken(tokens[i], 1);
        }
    }
    function test_ReceiverBalanceDeltaCannotBeFakedByToken() public {
        ManagerTokenMock accidental = new ManagerTokenMock(address(0));
        accidental.mint(address(manager), 15);
        vm.mockCall(
            address(accidental),
            abi.encodeWithSignature("balanceOf(address)", address(safe)),
            abi.encode(uint256(0))
        );
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        vm.prank(address(safe));
        manager.rescueToken(address(accidental), 15);
        assertEq(accidental.balanceOf(address(manager)), 15);
    }
}
