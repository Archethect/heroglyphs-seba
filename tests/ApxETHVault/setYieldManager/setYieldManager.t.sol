// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";

contract SetYieldManagerTest is BaseTest {
    function test_WhenNotTheOwner(address caller) external {
        vm.assume(users.admin != caller);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        resetPrank(caller);
        apxETHVault.setYieldManager(address(0));
    }

    function test_RevertWhen_TheYieldManagerAddressIsZero() external whenTheOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IDripVault.ZeroAddress.selector));
        apxETHVault.setYieldManager(address(0));
    }

    function test_WhenTheYieldManagerAddressIsNotZero(address newYieldManager) external whenTheOwner {
        assumeNotZeroAddress(newYieldManager);

        // it should emit YieldManagerUpdated
        vm.expectEmit();
        emit IDripVault.YieldManagerUpdated(newYieldManager);
        apxETHVault.setYieldManager(newYieldManager);

        // it should set the new yield manager
        assertEq(
            address(apxETHVault.yieldManager()),
            newYieldManager,
            "YieldManager: yield manager should be set correctly"
        );
    }
}
