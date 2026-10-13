// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";

contract YBoldReceiveTest is YBoldYieldVaultTestBase {
    function test_RevertWhenEthSenderIsNotWeth() external {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.UnauthorizedEthSender.selector, address(this)));
        (bool success, ) = address(vault).call{ value: 1 ether }("");
        success;
    }

    function test_ReceivesEthFromWethUnwrap() external {
        weth.mint(address(vault), 1 ether);
        vm.prank(address(vault));
        weth.withdraw(1 ether);
        assertEq(address(vault).balance, 1 ether);
    }
}
