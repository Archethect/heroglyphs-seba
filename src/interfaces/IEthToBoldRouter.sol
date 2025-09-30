// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";

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
    /// @notice Thrown when fee bps is invalid or exceeds the max.
    error InvalidFee(uint256 fee, uint256 maxFee);
    /// @notice Thrown when an initiator already has an open order.
    error OrderAlreadyOpen();
    /// @notice Thrown when the Chainlink price is non-positive.
    error OraclePriceInvalid(int256 px);
    /// @notice Thrown when the Chainlink price is stale.
    error StaleOracle();
    /// @notice Thrown when cancel is invoked with no active order.
    error NoActiveOrder();
    /// @notice Thrown when refunding ETH to the initiator fails.
    error FailedETHRefund();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an intent is created on Eth-flow.
    /// @param initiator The initiating address (also the receiver of BOLD).
    /// @param ethIn The ETH amount committed.
    /// @param minBoldOut The minimum BOLD the order will accept.
    /// @param uid The 56-byte order UID.
    /// @param validTo Expiry timestamp used by the order.
    event IntentCreated(address indexed initiator, uint256 ethIn, uint256 minBoldOut, bytes32 uid, uint32 validTo);

    /// @notice Emitted when an open intent is actively cancelled.
    /// @param initiator The initiator cancelling their order.
    /// @param uid The order UID.
    /// @param ethRefunded Any ETH refunded back to the initiator.
    /// @param boldReceived Any BOLD received as results of succesful intent solving
    event IntentFinalized(address indexed initiator, bytes32 uid, uint256 ethRefunded, uint256 boldReceived);

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Local tracking for a single open order per initiator.
    struct Order {
        address initiator; // the calling address
        uint256 ethAmount; // telemetry/reference only
        bytes32 uid; // 56-byte order UID
        bool active; // order is open in our local view
        IEthFlow.Data data; // Intent data
    }

    /*//////////////////////////////////////////////////////////////
                       PUBLIC CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// Role IDs used by AccessControl.
    function ADMIN_ROLE() external view returns (bytes32);
    function YIELD_MANAGER_ROLE() external view returns (bytes32);

    /// @notice Returns the CowSwap Eth-flow contract.
    function ETH_FLOW() external view returns (IEthFlow);

    /// @notice Returns the BOLD ERC-20 token.
    function BOLD() external view returns (IERC20);

    /// @notice Public getter for the pending order.
    function order()
        external
        view
        returns (address initiator, uint256 ethAmount, bytes32 uid, bool active, IEthFlow.Data memory data);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Swap caller’s ETH→BOLD via Eth-flow.
     * @dev Uses Chainlink ETH/USD to size `minOut` with the provided slippage bps and validity.
     *      Reverts with {NoEthSent}, {InvalidSlippage}, {OrderAlreadyOpen},
     *      {OraclePriceInvalid}, {StaleOracle} on failure.
     * @param minBoldBeforeSlippage Minimum amount of BOLD to expect before slippage taken into account.
     * @param slippageBps Maximum slippage in basis points (0 … 9,999).
     * @param validity Validity window (seconds) added to current timestamp.
     * @return uid The 56-byte UID of the created order.
     */
    function swapExactEthForBold(
        uint256 minBoldBeforeSlippage,
        uint16 slippageBps,
        uint32 validity
    ) external payable returns (bytes32 uid);

    /**
     * @notice Finalize the caller’s open intent and returns ETH and/or BOLD. If already filled/expired, closes local state without reverting.
     */
    function finalizeIntent() external;
}
