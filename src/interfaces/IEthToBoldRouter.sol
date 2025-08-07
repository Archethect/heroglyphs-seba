// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IEthFlow} from "src/vendor/cowswap/IEthFlow.sol";
import {IWETH} from "src/vendor/various/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "src/vendor/chainlink/AggregatorV3Interface.sol";
import {IGPv2Settlement} from "src/vendor/cowswap/IGPv2Settlement.sol";

/**
 * @title IEthToBoldRouter
 * @notice Interface for the router that swaps ETH→BOLD using CowSwap Eth-flow,
 *         sizes `minOut` via Chainlink ETH/USD, tracks a single open intent per initiator,
 *         and exposes helpers to query or cancel the intent.
 */
interface IEthToBoldRouter {
    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an address parameter is the zero address.
    error InvalidAddress();
    /// @notice Thrown when no ETH is sent for a swap.
    error NoEthSent();
    /// @notice Thrown when slippage bps is invalid or exceeds the max.
    error InvalidSlippage(uint256 slippage, uint256 maxSlippage);
    /// @notice Thrown when an initiator already has an open order.
    error OrderAlreadyOpen();
    /// @notice Thrown when the Chainlink price is non-positive.
    error OraclePriceInvalid(int256 px);
    /// @notice Thrown when the Chainlink price is stale.
    error StaleOracle();
    /// @notice Thrown when cancel is invoked with no active order.
    error NoActiveOrder();
    /// @notice Thrown when a non-initiator tries to cancel an order.
    error NotInitiator();
    /// @notice Thrown when refunding ETH to the initiator fails.
    error FailedETHRefund();
    /// @notice Thrown when the UID bytes format is invalid.
    error BadUID(bytes uid);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an intent is created on Eth-flow.
    /// @param initiator The initiating address (also the receiver of BOLD).
    /// @param ethIn The ETH amount committed.
    /// @param minBoldOut The minimum BOLD the order will accept.
    /// @param uid The 56-byte order UID.
    /// @param validTo Expiry timestamp used by the order.
    event IntentCreated(address indexed initiator, uint256 ethIn, uint256 minBoldOut, bytes uid, uint32 validTo);

    /// @notice Emitted when an open intent is actively cancelled.
    /// @param initiator The initiator cancelling their order.
    /// @param uid The order UID.
    /// @param ethRefunded Any ETH refunded back to the initiator.
    event IntentCancelled(address indexed initiator, bytes uid, uint256 ethRefunded);

    /// @notice Emitted when we close the local record because it’s finalized/expired already.
    /// @param initiator The initiator whose order was closed.
    /// @param uid The order UID.
    event IntentClosedAsFinalized(address indexed initiator, bytes uid);

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Local tracking for a single open order per initiator.
    struct Order {
        address initiator; // the calling address
        uint256 ethAmount; // telemetry/reference only
        bytes uid;         // 56-byte order UID
        uint32 validTo;    // expiry timestamp
        bool active;       // order is open in our local view
    }

    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Lifecycle view of an intent.
    enum IntentState { None, Open, Filled, Expired }

    /*//////////////////////////////////////////////////////////////
                       PUBLIC CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the CowSwap Eth-flow contract.
    function ETH_FLOW() external view returns (IEthFlow);

    /// @notice Returns the BOLD ERC-20 token.
    function BOLD() external view returns (IERC20);

    /// @notice Returns the WETH contract.
    function WETH() external view returns (IWETH);

    /// @notice Returns the Chainlink ETH/USD aggregator.
    function ETH_USD_FEED() external view returns (AggregatorV3Interface);

    /// @notice Returns the CowSwap settlement contract.
    function SETTLEMENT() external view returns (IGPv2Settlement);

    /// @notice Public getter for the per-initiator pending order.
    function pending(address initiator)
    external
    view
    returns (address _initiator, uint256 ethAmount, bytes memory uid, uint32 validTo, bool active);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Swap caller’s ETH→BOLD via Eth-flow.
     * @dev Uses Chainlink ETH/USD to size `minOut` with the provided slippage bps and validity.
     *      Reverts with {NoEthSent}, {InvalidSlippage}, {OrderAlreadyOpen},
     *      {OraclePriceInvalid}, {StaleOracle} on failure.
     * @param slippageBps Maximum slippage in basis points (0 … 9,999).
     * @param validity Validity window (seconds) added to current timestamp.
     * @return uid The 56-byte UID of the created order.
     */
    function swapExactEthForBold(uint16 slippageBps, uint32 validity) external payable returns (bytes memory uid);

    /**
     * @notice Cancel the caller’s open intent. If already filled/expired, closes local state without reverting.
     * @dev Reverts with {NoActiveOrder} or {NotInitiator} when applicable.
     */
    function cancelMyIntent() external;

    /**
     * @notice Returns status derived on-chain from CowSwap settlement and local expiry.
     * @param initiator The address whose order is queried.
     * @return state The derived {IntentState}.
     * @return filled Filled amount reported by settlement (zero for our non-partial intents unless filled).
     * @return validTo The expiry timestamp recorded in the UID.
     */
    function getIntentState(address initiator)
    external
    view
    returns (IntentState state, uint256 filled, uint32 validTo);

    /**
     * @notice Seconds remaining before the initiator’s order expiry (0 if none/expired).
     * @param initiator The address to query.
     * @return secondsRemaining Seconds to expiry.
     */
    function secondsToExpiry(address initiator) external view returns (uint256 secondsRemaining);
}
