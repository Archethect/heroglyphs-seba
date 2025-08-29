// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/* ── Curve USDeUSDC pool ──────────────────────────────────────── */
interface ICurvePool {
    /// @notice Add liquidity (indices: 0=USDe 1=USDC)
    function add_liquidity(uint256[] calldata amounts, uint256 minMint) external returns (uint256);

    /// @notice Remove liquidity in a single coin
    function remove_liquidity_one_coin(uint256 lpAmount, int128 i, uint256 minOut) external returns (uint256);

    /* -------- view helpers -------- */
    function calc_token_amount(uint256[] calldata amounts, bool isDeposit) external view returns (uint256);
    function calc_withdraw_one_coin(uint256 lpAmount, int128 i) external view returns (uint256 outAmount);
}