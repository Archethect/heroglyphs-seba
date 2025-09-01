// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/* ── Beefy vault ───────────────────────────────────────── */
interface IBeefyVault {
    function depositAll() external;
    function withdraw(uint256 shares) external;
    function balanceOf(address) external view returns (uint256);
    function getPricePerFullShare() external view returns (uint256);
    function want() external view returns (address);
}
