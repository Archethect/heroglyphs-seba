// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IMockApxETH {
    function convertToShares(uint256 assets) external view returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
    function maxRedeem(address owner) external view returns (uint256 maxShares);
    function mint(address to, uint256 amount) external;
}
