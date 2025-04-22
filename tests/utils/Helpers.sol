// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";
import { StdUtils } from "forge-std/src/StdUtils.sol";
import { Users, Contracts } from "./Types.sol";

abstract contract Helpers is PRBTest, StdCheats, StdUtils {
    error DoesNotHandleBigCreateCount();

    Users internal users;
    Contracts internal contracts;

    function setVariables(Users memory _users, Contracts memory _contracts) public {
        users = _users;
        contracts = _contracts;
    }

    /// @dev Stops the active prank and sets a new one.
    function resetPrank(address msgSender) internal {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }

    /// @dev Generates a user
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        return user;
    }

    function grantRole(address admin, address accessControl, bytes32 role, address account) internal {
        vm.startPrank(admin);
        IAccessControl(accessControl).grantRole(role, account);
        vm.stopPrank();
    }
}
