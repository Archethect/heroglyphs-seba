// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockSimpleYieldVault {
    function claimYield() external {
        payable(msg.sender).transfer(1 ether);
    }

    function deposit() external payable returns (uint256 value) {
        value = msg.value;
    }
    receive() external payable {}
}
