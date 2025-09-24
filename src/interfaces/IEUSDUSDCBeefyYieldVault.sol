// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IYieldVault } from "src/interfaces/IYieldVault.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IQuoter } from "src/vendor/uniswap_v3/IQuoter.sol";
import { ICurvePool } from "src/vendor/curve/ICurvePool.sol";
import { IBeefyVault } from "src/vendor/beefy/IBeefyVault.sol";

/**
 * @title IEUSDUSDCBeefyYieldVault
 * @notice Yield-strategy vault that:
 *         1. Wraps ETH → WETH → USDC (Uniswap V3),
 *         2. Adds liquidity to the USDe/USDC Curve pool,
 *         3. Stakes LP tokens in a Beefy vault,
 *         4. Realises yield in ETH on demand.
 *
 * @dev Implements the generic {IYieldVault} hooks (`deposit`, `claimYield`,
 *      `retrievePrincipal`) so it can plug into the Seba Yield-Manager.
 */
interface IEUSDUSDCBeefyYieldVault is IYieldVault {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// Zero address passed to constructor.
    error InvalidAddress();

    /// `deposit()` called with zero ETH.
    error NoEthProvided();

    /// Vault finds no yield to claim.
    error NothingToClaim();

    /// Curve or Uniswap swap / mint returned less than the min-out.
    error SlippageExceeded();

    // No shares minted on Beefy
    error NoSharesMinted();

    // Value of deposit is zero
    error ZeroDepositValue();

    /// Asked to retrieve 0 principal.
    error CannotRetrieveZero();

    /// No shares to withdraw
    error NoSharesToWithdraw();

    /// Configured slippage is too high
    error SlippageTooHigh();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// Emitted after ETH is invested and Beefy shares are minted.
    event Deposited(address indexed depositor, uint256 ethIn, uint256 sharesMinted);

    /// Emitted when yield is harvested and paid out in ETH.
    event YieldClaimed(uint256 sharesRedeemed, uint256 ethOut);

    /// Emitted when principal is unwound and returned to caller.
    event PrincipalRetrieved(uint256 sharesRedeemed, uint256 ethOut);

    /// Emitted when admin updates slippage tolerance.
    event SlippageSet(uint16 bps);

    /*//////////////////////////////////////////////////////////////
                      PUBLIC CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// Current slippage tolerance (basis-points) used for every swap.
    function slippageBps() external view returns (uint16);

    /// Fixed Uniswap V3 fee tier (0.05 % = 500).
    function UNIV3_FEE_TIER() external view returns (uint24);

    /// Access-control role identifiers.
    function ADMIN_ROLE() external view returns (bytes32);
    function YIELDMANAGER_ROLE() external view returns (bytes32);

    /// Token & protocol references.
    function WETH() external view returns (address);
    function USDC() external view returns (address);
    function swapRouter() external view returns (ISwapRouter);
    function quoter() external view returns (IQuoter);
    function curvePool() external view returns (ICurvePool);
    function beefy() external view returns (IBeefyVault);

    /// Accounting snapshots.
    function principalShares() external view returns (uint256);
    function principalValue() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Admin setter to update the vault-wide slippage tolerance.
     * @param bps  New tolerance in basis-points (max 1 000 = 10 %).
     *
     * @dev Emits {SlippageSet}.
     *      Reverts {InvalidAddress} if `msg.sender` lacks `ADMIN_ROLE`.
     */
    function setSlippageBps(uint16 bps) external;
}
