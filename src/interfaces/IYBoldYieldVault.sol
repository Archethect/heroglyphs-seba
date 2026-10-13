// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { ICurveStableSwapNG } from "src/vendor/curve/ICurveStableSwapNG.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IYearnVault } from "src/vendor/yearn/IYearnVault.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";

/**
 * @title IYBoldYieldVault
 * @notice Seba yield adapter that converts ETH into staked yBOLD and realizes unlocked yield in ETH.
 */
interface IYBoldYieldVault is IYieldVault {
    /**
     * Zero address supplied for a required dependency or recipient.
     */
    error InvalidAddress();
    /**
     * Address expected to contain deployed bytecode does not.
     */
    error InvalidContract(address target);
    /**
     * A configured integration exposes an unexpected token or asset.
     */
    error InvalidAsset(address integration, address expected, address actual);
    /**
     * A configured token or oracle exposes unsupported decimals.
     */
    error InvalidDecimals(address target, uint8 expected, uint8 actual);
    /**
     * Deposit called without ETH.
     */
    error NoEthProvided();
    /**
     * Deposits or claims are disabled.
     */
    error StrategyNotOperational();
    /**
     * A Yearn vault is shut down or cannot accept the requested amount.
     */
    error StrategyUnavailable(address vault, uint256 requested, uint256 available);
    /**
     * A Yearn vault returned no shares for a non-zero deposit.
     */
    error NoSharesMinted(address vault);
    /**
     * The strategy produced no output for a required conversion.
     */
    error ZeroOutput();
    /**
     * Principal retrieval requested zero.
     */
    error CannotRetrieveZero();
    /**
     * No principal shares are available for retrieval.
     */
    error NoPrincipal();
    /**
     * A Yearn vault cannot redeem all requested shares atomically.
     */
    error InsufficientLiquidity(address vault, uint256 requested, uint256 available);
    /**
     * A Chainlink answer or round is invalid.
     */
    error OracleInvalid(address feed);
    /**
     * A Chainlink answer is older than its configured maximum age.
     */
    error OracleStale(address feed, uint256 updatedAt);
    /**
     * Curve's BOLD/USDC moving-average price exceeds the configured deviation.
     */
    error BoldPegDeviationExceeded(uint256 price, uint256 maximumDeviationBps);
    /**
     * A configured swap slippage exceeds its hard cap.
     */
    error SlippageTooHigh(uint256 suppliedBps);
    /**
     * A configured BOLD peg deviation exceeds its hard cap.
     */
    error PegDeviationTooHigh(uint256 suppliedBps);
    /**
     * A configured Yearn loss tolerance exceeds its hard cap or has an invalid ordering.
     */
    error InvalidYearnLossConfiguration(uint256 normalBps, uint256 emergencyBps);
    /**
     * Core strategy assets cannot be rescued by governance.
     */
    error CoreAsset(address token);
    /**
     * ETH may only be received from WETH during an unwrap.
     */
    error UnauthorizedEthSender(address sender);

    /**
     * Emitted after ETH is converted and st-yBOLD shares are received.
     */
    event Deposited(address indexed depositor, uint256 ethIn, uint256 principalValue, uint256 sharesMinted);
    /**
     * Emitted when unlocked st-yBOLD yield is realized and paid to the YieldManager.
     */
    event YieldClaimed(uint256 sharesRedeemed, uint256 yBoldAssets, uint256 ethOut);
    /**
     * Emitted when principal is unwound and paid to the YieldManager.
     */
    event PrincipalRetrieved(uint256 principalValue, uint256 sharesRedeemed, uint256 ethOut);
    /**
     * Emitted when swap slippage configuration changes.
     */
    event SwapSlippageSet(uint16 wethUsdcBps, uint16 boldUsdcBps);
    /**
     * Emitted when the maximum accepted BOLD peg deviation changes.
     */
    event BoldPegDeviationSet(uint16 bps);
    /**
     * Emitted when Yearn loss tolerances change.
     */
    event YearnMaxLossSet(uint16 normalBps, uint16 emergencyBps);
    /**
     * Emitted when emergency withdrawal mode changes.
     */
    event EmergencyModeSet(bool enabled);
    /**
     * Emitted when a non-core ERC-20 is rescued.
     */
    event TokenRescued(address indexed token, address indexed recipient, uint256 amount);

    /**
     * @return Access-control administrator role identifier.
     */
    function ADMIN_ROLE() external view returns (bytes32);
    /**
     * @return YieldManager caller role identifier.
     */
    function YIELDMANAGER_ROLE() external view returns (bytes32);
    /**
     * @return WETH token address.
     */
    function WETH() external view returns (address);
    /**
     * @return USDC token address.
     */
    function USDC() external view returns (address);
    /**
     * @return BOLD token address.
     */
    function BOLD() external view returns (address);
    /**
     * @return Uniswap V3 router.
     */
    function swapRouter() external view returns (ISwapRouter);
    /**
     * @return Curve BOLD/USDC pool.
     */
    function curvePool() external view returns (ICurveStableSwapNG);
    /**
     * @return Yearn yBOLD vault.
     */
    function yBold() external view returns (IYearnVault);
    /**
     * @return Yearn st-yBOLD strategy.
     */
    function stYBold() external view returns (IYearnVault);
    /**
     * @return Chainlink ETH/USD feed.
     */
    function ethUsdFeed() external view returns (AggregatorV3Interface);
    /**
     * @return Chainlink USDC/USD feed.
     */
    function usdcUsdFeed() external view returns (AggregatorV3Interface);
    /**
     * @return Tracked st-yBOLD shares attributable to Seba principal.
     */
    function principalShares() external view returns (uint256);
    /**
     * @return Tracked principal denominated in yBOLD assets.
     */
    function principalValue() external view returns (uint256);
    /**
     * @return WETH/USDC swap slippage in basis points.
     */
    function wethUsdcSlippageBps() external view returns (uint16);
    /**
     * @return BOLD/USDC swap slippage in basis points.
     */
    function boldUsdcSlippageBps() external view returns (uint16);
    /**
     * @return Maximum BOLD peg deviation in basis points.
     */
    function maxBoldPegDeviationBps() external view returns (uint16);
    /**
     * @return Normal Yearn redemption loss tolerance in basis points.
     */
    function normalYearnMaxLossBps() external view returns (uint16);
    /**
     * @return Emergency Yearn redemption loss tolerance in basis points.
     */
    function emergencyYearnMaxLossBps() external view returns (uint16);
    /**
     * @return Whether emergency withdrawal mode is active.
     */
    function emergencyMode() external view returns (bool);
    /**
     * @return Unlocked yBOLD assets currently attributable to yield.
     */
    function claimableYield() external view returns (uint256);
    /**
     * @return Active Yearn redemption loss tolerance in basis points.
     */
    function currentYearnMaxLossBps() external view returns (uint16);

    /**
     * Sets independent slippage limits for volatile and stable swaps.
     */
    function setSwapSlippageBps(uint16 wethUsdcBps, uint16 boldUsdcBps) external;
    /**
     * Sets the maximum accepted Curve BOLD peg deviation.
     */
    function setMaxBoldPegDeviationBps(uint16 bps) external;
    /**
     * Sets normal and emergency Yearn redemption loss tolerances.
     */
    function setYearnMaxLossBps(uint16 normalBps, uint16 emergencyBps) external;
    /**
     * Enables or disables emergency withdrawal mode.
     */
    function setEmergencyMode(bool enabled) external;
    /**
     * Pauses deposits and yield claims while keeping principal retrieval available.
     */
    function pause() external;
    /**
     * Re-enables deposits and yield claims when emergency mode is disabled.
     */
    function unpause() external;
    /**
     * Rescues an ERC-20 that is not a core strategy asset.
     */
    function rescueToken(address token, address recipient, uint256 amount) external;
}
