// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPoap {
    function tokenEvent(uint256 poapId) external view returns (uint256);
    function ownerOf(uint256 poapId) external view returns (address);
}
