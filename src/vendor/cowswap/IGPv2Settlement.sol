// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// GPv2 Settlement exposes filledAmount(orderHash) as public view.
interface IGPv2Settlement {
    function filledAmount(bytes32 orderHash) external view returns (uint256);
}
