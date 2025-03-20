// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "solmate/src/tokens/ERC20.sol";
import "src/mocks/IMockApxETH.sol";

/**
 * @title MockApxETH
 * @notice Minimal mock of the ApxETH token that:
 *  - Implements a price-per-share for yield simulation
 *  - Mints/burns like an ERC20
 *  - Implements all IApxETH functions used by ApxETHVault
 */
contract MockApxETH is ERC20, IMockApxETH {
    /// @notice Reference to the PirexEth contract (just stored, not used for logic here).
    address public pirexEth;

    /**
     * @notice Price per share used in convertToShares / convertToAssets
     *         Example: 1e18 means 1 share = 1 ETH.
     *         If set to 2e18, then 1 share = 2 ETH, simulating yield.
     */
    uint256 public pricePerShare = 1e18;

    constructor(address _pirexEth) ERC20("Mock ApxETH", "mAPXETH", 18) {
        pirexEth = _pirexEth;
    }

    /**
     * @notice Adjust the price per share to simulate yield or growth in ApxETH value.
     * @param newPrice New price (in wei) for 1 share of ApxETH in terms of ETH.
     */
    function setPricePerShare(uint256 newPrice) external {
        require(newPrice > 0, "price cannot be 0");
        pricePerShare = newPrice;
    }

    /**
     * @notice Convert an amount of underlying assets (ETH) into the equivalent number of ApxETH shares.
     * @dev    If `pricePerShare` is e.g. 2e18, each share is worth 2 ETH, so converting 4 ETH => 2 shares.
     */
    function convertToShares(uint256 assets) external view override returns (uint256) {
        // shares = assets * 1e18 / pricePerShare
        return (assets * 1e18) / pricePerShare;
    }

    /**
     * @notice Convert an amount of ApxETH shares into the equivalent underlying assets (ETH).
     */
    function convertToAssets(uint256 shares) external view override returns (uint256) {
        // assets = shares * pricePerShare / 1e18
        return (shares * pricePerShare) / 1e18;
    }

    /**
     * @notice Returns how many shares can be redeemed from `account`. For a simple mock,
     *         we say maxRedeem = that account’s ApxETH balance. (No special logic needed.)
     */
    function maxRedeem(address account) external view override returns (uint256) {
        return this.balanceOf(account);
    }

    /**
     * @notice Expose a mint function so PirexEth or tests can mint ApxETH directly.
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
