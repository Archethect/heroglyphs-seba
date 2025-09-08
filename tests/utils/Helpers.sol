// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";
import { StdUtils } from "forge-std/src/StdUtils.sol";
import { Users, Contracts } from "./Types.sol";

abstract contract Helpers is PRBTest, StdCheats, StdUtils {
    error DoesNotHandleBigCreateCount();
    error UIDMustBe56Buytes();

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

    /// @dev Generates a mocked contract
    function createMockContract(string memory name) internal returns (address) {
        address mockContract = makeAddr(name);
        return mockContract;
    }

    function grantRole(address admin, address accessControl, bytes32 role, address account) internal {
        vm.startPrank(admin);
        IAccessControl(accessControl).grantRole(role, account);
        vm.stopPrank();
    }

    function mockAndExpectCall(address to, uint256 value, bytes memory data, bytes memory output) internal {
        vm.mockCall(to, value, data, output);
        vm.expectCall(to, value, data);
    }

    function mockAndExpectCall(address to, bytes memory data, bytes memory output) internal {
        mockAndExpectCall(to, 0, data, output);
    }

    function makeCOWUid(bytes32 orderHash, address owner, uint32 validTo) internal pure returns (bytes memory uid) {
        uid = abi.encodePacked(orderHash, owner, validTo);
        if (uid.length != 56) revert UIDMustBe56Buytes();
    }

    function calculateOrderAmounts(
        uint256 amount,
        int256 price,
        uint16 fee,
        uint16 slippage
    ) internal pure returns (uint256 sellAmount, uint256 feeAmount, uint256 minBold) {
        feeAmount = fee;
        sellAmount = amount - feeAmount;
        uint256 boldRaw = (sellAmount * uint256(price)) / (10 ** 8);
        minBold = (boldRaw * (10000 - slippage)) / 10000;
    }

    function accessControlMissingRoleForAccountRevert(
        address account,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(uint160(account), 20),
                    " is missing role ",
                    Strings.toHexString(uint256(role), 32)
                )
            );
    }
}
