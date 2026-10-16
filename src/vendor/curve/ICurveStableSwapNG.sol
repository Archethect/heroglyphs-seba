// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ICurveStableSwapNG
 * @notice Minimal interface for the Curve StableSwap-NG BOLD/USDC pool.
 */
interface ICurveStableSwapNG {
    /**
     * @notice Returns a pool coin by index.
     * @param index Coin index.
     * @return token Coin address.
     */
    function coins(uint256 index) external view returns (address token);

    /**
     * @notice Returns the exponential moving-average price for coin `index + 1` in coin 0 units.
     * @param index Oracle index; zero for a two-coin pool.
     * @return price Oracle price scaled to 18 decimals.
     */
    function price_oracle(uint256 index) external view returns (uint256 price);

    /**
     * @notice Exchanges an exact amount of one pool coin for another.
     * @param i Input coin index.
     * @param j Output coin index.
     * @param dx Exact input amount.
     * @param minDy Minimum output amount.
     * @param receiver Output recipient.
     * @return dy Actual output amount.
     */
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy, address receiver) external returns (uint256 dy);
}
