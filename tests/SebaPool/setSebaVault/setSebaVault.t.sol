// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { ISebaPool } from "src/interfaces/ISebaPool.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetSebaVault is BaseTest {
    function test_RevertWhen_NotTheAdminRole(address caller) external {
        vm.assume(caller != users.admin);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                sebaPool.ADMIN_ROLE()
            )
        );
        resetPrank(caller);
        sebaPool.setSebaVault(address(0));
    }

    function test_RevertWhen_TheSebaVaultAddressIsZero() external whenTheAdminRole {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaPool.InvalidAddress.selector));
        sebaPool.setSebaVault(address(0));
    }

    function test_WhenTheSebaVaultAddressIsNotZero(address newSebaVault) external whenTheAdminRole {
        assumeNotZeroAddress(newSebaVault);

        // it should emit SebaVaultSet
        vm.expectEmit();
        emit ISebaPool.SebaVaultSet(newSebaVault);
        sebaPool.setSebaVault(newSebaVault);

        // it should set the new sBOLD address
        assertEq(address(sebaPool.sebaVault()), newSebaVault, "sebaVault should be set correctly");
    }
}
