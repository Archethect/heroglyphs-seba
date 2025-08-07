// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*───────────────────────────── Dependencies ───────────────────────────*/
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { IGPv2Settlement } from "src/vendor/cowswap/IGPv2Settlement.sol";
import { IWETH } from "src/vendor/various/IWETH.sol";
import { IEthToBoldRouter } from "src/interfaces/IEthToBoldRouter.sol";

/*────────────────────────── Contract Implementation ───────────────────*/

/**
 * @title EthToBoldRouter
 * @notice Swaps ETH→BOLD via CowSwap Eth-flow with `minOut` sized from Chainlink ETH/USD.
 *         Tracks a single open order per initiator and supports cancellation/refunds.
 * @dev See {IEthToBoldRouter} for the external interface.
 */
contract EthToBoldRouter is IEthToBoldRouter {
    /*//////////////////////////////////////////////////////////////
                          IMMUTABLE REFERENCES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEthToBoldRouter
    IEthFlow public immutable ETH_FLOW;
    /// @inheritdoc IEthToBoldRouter
    IERC20 public immutable BOLD;
    /// @inheritdoc IEthToBoldRouter
    IWETH public immutable WETH;
    /// @inheritdoc IEthToBoldRouter
    AggregatorV3Interface public immutable ETH_USD_FEED;
    /// @inheritdoc IEthToBoldRouter
    IGPv2Settlement public immutable SETTLEMENT;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Basis points denominator (10,000).
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice One open order per initiator.
    mapping(address => Order) public pending;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the EthToBoldRouter.
     * @param ethFlow CowSwap Eth-flow contract address.
     * @param bold BOLD ERC-20 token address.
     * @param weth WETH token address.
     * @param ethUsdFeed Chainlink ETH/USD aggregator address.
     * @param settlement CowSwap settlement contract address.
     */
    constructor(
        address ethFlow,
        address bold,
        address weth,
        address ethUsdFeed,
        address settlement
    ) {
        if (ethFlow == address(0)) revert InvalidAddress();
        if (bold == address(0)) revert InvalidAddress();
        if (weth == address(0)) revert InvalidAddress();
        if (ethUsdFeed == address(0)) revert InvalidAddress();
        if (settlement == address(0)) revert InvalidAddress();

        ETH_FLOW = IEthFlow(ethFlow);
        BOLD = IERC20(bold);
        WETH = IWETH(weth);
        ETH_USD_FEED = AggregatorV3Interface(ethUsdFeed);
        SETTLEMENT = IGPv2Settlement(settlement);
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow receiving ETH (Eth-flow refunds or WETH unwrap).
     */
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL / PUBLIC API
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEthToBoldRouter
    function swapExactEthForBold(uint16 slippageBps, uint32 validity)
    external
    payable
    override
    returns (bytes memory uid)
    {
        if (msg.value == 0) revert NoEthSent();
        if (slippageBps >= BPS_DENOMINATOR) revert InvalidSlippage(slippageBps, BPS_DENOMINATOR);
        if (pending[msg.sender].active) revert OrderAlreadyOpen();

        // 1) On-chain ETH/USD
        (, int256 px, , uint256 updatedAt, ) = ETH_USD_FEED.latestRoundData();
        if (px <= 0) revert OraclePriceInvalid(px);
        if (updatedAt + 600 < block.timestamp) revert StaleOracle();
        uint8 d = ETH_USD_FEED.decimals(); // typically 8

        // 2) Compute min BOLD out (1 BOLD = 1 USD; BOLD assumed 18 decimals)
        uint256 boldRaw = (msg.value * uint256(px)) / (10 ** d);
        uint256 minBold = (boldRaw * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;

        // 3) Create Eth-flow intent (receiver is the initiator)
        IEthFlow.Data memory data = IEthFlow.Data({
            buyToken: BOLD,
            receiver: msg.sender,
            sellAmount: msg.value,
            buyAmount: minBold,
            appData: bytes32(0),
            feeAmount: 0,
            validTo: uint32(block.timestamp) + validity,
            partiallyFillable: false,
            quoteId: 0
        });

        uid = ETH_FLOW.createOrder{ value: msg.value }(data);

        // 4) Record
        pending[msg.sender] = Order({
            initiator: msg.sender,
            ethAmount: msg.value,
            uid: uid,
            validTo: data.validTo,
            active: true
        });

        emit IntentCreated(msg.sender, msg.value, minBold, uid, data.validTo);
    }

    /// @inheritdoc IEthToBoldRouter
    function cancelMyIntent() external override {
        Order storage o = pending[msg.sender];
        if (!o.active) revert NoActiveOrder();
        if (o.initiator != msg.sender) revert NotInitiator();

        (IntentState state, , ) = getIntentState(msg.sender);

        if (state == IntentState.Open || state == IntentState.Expired) {
            // Track balances to forward any refunds back to initiator.
            uint256 preEth = address(this).balance;
            uint256 preWeth = WETH.balanceOf(address(this));

            // May revert if Eth-flow considers it non-cancellable; we gate by state==Open to avoid this.
            ETH_FLOW.cancelOrder(o.uid);

            // Convert any refunded WETH to ETH and sum ETH delta.
            uint256 wethRefund = WETH.balanceOf(address(this)) - preWeth;
            if (wethRefund > 0) {
                WETH.withdraw(wethRefund);
            }
            uint256 ethRefund = address(this).balance - preEth;
            if (ethRefund > 0) {
                (bool ok, ) = msg.sender.call{ value: ethRefund }("");
                if (!ok) revert FailedETHRefund();
            }

            o.active = false;
            emit IntentCancelled(msg.sender, o.uid, ethRefund);
        } else {
            // Already filled — just mark inactive, do not revert.
            o.active = false;
            emit IntentClosedAsFinalized(msg.sender, o.uid);
        }
    }

    /// @inheritdoc IEthToBoldRouter
    function getIntentState(address initiator)
    public
    view
    override
    returns (IntentState state, uint256 filled, uint32 validTo)
    {
        Order storage o = pending[initiator];
        if (!o.active || o.uid.length == 0) return (IntentState.None, 0, 0);

        (bytes32 orderHash, , uint32 _validTo) = _decodeUid(o.uid);
        validTo = _validTo;

        filled = SETTLEMENT.filledAmount(orderHash);

        if (filled > 0) {
            state = IntentState.Filled;
        } else if (block.timestamp < validTo) {
            state = IntentState.Open;
        } else {
            state = IntentState.Expired;
        }
    }

    /// @inheritdoc IEthToBoldRouter
    function secondsToExpiry(address initiator) external view override returns (uint256) {
        Order storage o = pending[initiator];
        if (!o.active || block.timestamp >= o.validTo) return 0;
        return o.validTo - block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev UID layout = 32 bytes orderHash | 20 bytes owner | 4 bytes validTo.
     * @param uid The 56-byte UID to decode.
     * @return orderHash The CowSwap order hash.
     * @return owner The order owner encoded in the UID.
     * @return validTo The order expiry timestamp encoded in the UID.
     */
    function _decodeUid(bytes memory uid)
    private
    pure
    returns (bytes32 orderHash, address owner, uint32 validTo)
    {
        if (uid.length != 56) revert BadUID(uid);
        assembly {
            orderHash := mload(add(uid, 32))
            owner := shr(96, mload(add(uid, 52)))
            validTo := mload(add(uid, 56))
        }
    }
}
