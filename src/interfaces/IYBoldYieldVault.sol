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
     * @notice Lifecycle of a treasury-led recovery.
     */
    enum RecoveryState {
        Normal,
        SharesTransferred,
        SettlementActive,
        Settled
    }

    /**
     * @notice One-time proxy initialization parameters.
     */
    struct InitializationParams {
        address admin;
        address yieldManager;
        address upgradeAuthority;
        address recoveryTreasury;
        address weth;
        address usdc;
        address bold;
        address router;
        address boldUsdcPool;
        address yearnBold;
        address stakedYearnBold;
        address ethUsd;
        address usdcUsd;
    }

    /**
     * @notice Auditable accounting for an active or completed treasury recovery.
     */
    struct RecoveryAccounting {
        uint256 principalSnapshot;
        uint256 sharesTransferred;
        uint256 ethFunded;
        uint256 settlementEth;
        uint256 payoutRateWad;
        uint256 principalSettled;
        uint256 ethPaid;
    }

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
     * New deposits cannot recapitalize existing principal after a strategy loss.
     */
    error StrategyUnderwater();
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
     * A recovery state transition was attempted from the wrong state.
     */
    error InvalidRecoveryState(RecoveryState current);
    /**
     * Tracked shares no longer match the strategy's actual st-yBOLD balance.
     */
    error ShareAccountingMismatch(uint256 tracked, uint256 actual);
    /**
     * Only the configured treasury can fund a recovery settlement.
     */
    error UnauthorizedRecoveryFunder(address sender);
    /**
     * The treasury has not funded enough ETH for the proposed settlement.
     */
    error RecoveryUnderfunded(uint256 required, uint256 funded);
    /**
     * The proposed settlement would round every unit of principal to zero ETH.
     */
    error RecoveryRateTooLow();

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
     * Emitted when all remaining st-yBOLD shares enter treasury recovery custody.
     */
    event RecoveryInitiated(address indexed treasury, uint256 principalValueSnapshot, uint256 sharesTransferred);
    /**
     * Emitted when the treasury funds recovery settlement liquidity.
     */
    event RecoveryFunded(address indexed treasury, uint256 amount, uint256 cumulativeAmount);
    /**
     * Emitted when the immutable pro-rata ETH settlement rate is activated.
     */
    event RecoverySettlementActivated(uint256 fundedEth, uint256 committedEth, uint256 payoutRateWad);
    /**
     * Emitted for each principal slice settled through the existing YieldManager.
     */
    event RecoveryPrincipalSettled(uint256 principalValue, uint256 ethOut);
    /**
     * Emitted after the final outstanding principal slice is settled.
     */
    event RecoveryCompleted(uint256 principalSettled, uint256 ethPaid);
    /**
     * Emitted when surplus recovery ETH is returned after every claim is settled.
     */
    event RecoveryExcessSwept(address indexed treasury, uint256 amount);

    /**
     * @return Access-control administrator role identifier.
     */
    function ADMIN_ROLE() external view returns (bytes32);
    /**
     * @return YieldManager caller role identifier.
     */
    function YIELDMANAGER_ROLE() external view returns (bytes32);
    /**
     * @return Proxy-upgrade authority role identifier.
     */
    function UPGRADER_ROLE() external view returns (bytes32);
    /**
     * @return Treasury-recovery authority role identifier.
     */
    function RECOVERY_ROLE() external view returns (bytes32);
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
     * @return Treasury that receives recovered st-yBOLD and funds ETH settlement.
     */
    function recoveryTreasury() external view returns (address);
    /**
     * @return Current recovery lifecycle state.
     */
    function recoveryState() external view returns (RecoveryState);
    /**
     * @return Complete recovery accounting for independent reconciliation.
     */
    function recoveryAccounting() external view returns (RecoveryAccounting memory);
    /**
     * @return Unlocked yBOLD assets currently attributable to yield.
     */
    function claimableYield() external view returns (uint256);
    /**
     * @return Active Yearn redemption loss tolerance in basis points.
     */
    function currentYearnMaxLossBps() external view returns (uint16);

    /**
     * Initializes the proxy exactly once.
     */
    function initialize(InitializationParams calldata params) external;

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
    /**
     * Freezes normal operations and transfers all exactly reconciled st-yBOLD shares to treasury custody.
     */
    function initiateRecovery() external;
    /**
     * Funds the proxy with ETH that will settle existing YieldManager claims.
     */
    function fundRecovery() external payable;
    /**
     * Activates a single pro-rata payout rate after sufficient ETH has been funded.
     */
    function activateRecoverySettlement(uint256 settlementEth) external;
    /**
     * Returns ETH left after every snapshotted claim is settled.
     */
    function sweepRecoveryExcess() external;
}
