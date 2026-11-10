// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Typed Seba CoW order and settlement views
/// @author Seba
/// @notice Fixed exact-input sell orders; only WETH/rETH into BOLD are supported.
interface ISebaCowIntentModule {
    /// @notice Canonical GPv2 EIP-712 order fields, in protocol order.
    struct Data {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        bytes32 kind;
        bool partiallyFillable;
        bytes32 sellTokenBalance;
        bytes32 buyTokenBalance;
    }
    /// @notice Immutable order attribution; source is never supplied again at finalization.
    struct Order {
        address escrow;
        uint8 source;
        uint32 validTo;
        uint256 sellAmount;
        uint256 minBold;
        bool closed;
    }
    error Unauthorized();
    error InvalidConfiguration();
    error InvalidOrder();
    error ExecutionDisabled();
    error PendingOrder();
    error ClosedOrder();
    error UnexpectedTokenDelta();
    error InvalidFill();
    /// @notice Safe-approved caps, not automatically approved production parameters.
    /// @param maxWeth Maximum WETH input per ETH-source order.
    /// @param maxReth Maximum harvested rETH input per order.
    /// @param maxTtl Maximum lifetime in seconds.
    event CowLimitsConfigured(uint256 maxWeth, uint256 maxReth, uint32 maxTtl);
    /// @notice New orders were enabled or paused; existing orders remain reconcilable.
    /// @param enabled New-order permission, not revocation of outstanding authorizations.
    event CowExecutionSet(bool enabled);
    /// @notice One source was isolated in its own fixed CoW order escrow.
    /// @param orderId Module-local monotonic order identity.
    /// @param source 0 reward ETH, 1 ysy principal ETH, 2 supporter rETH carry, 3 protocol rETH carry.
    /// @param escrow One-shot owner and receiver of the order.
    /// @param sellToken WETH or rETH.
    /// @param sellAmount Exact input atoms reserved from source accounting.
    /// @param minBold Immutable minimum BOLD atoms; a backend quote is not a fill guarantee.
    /// @param validTo Last valid settlement timestamp, inclusive.
    /// @param appData CoW application-data hash.
    /// @param orderUid Canonical 56-byte domain-bound order identity.
    event CowOrderOpened(
        uint256 indexed orderId,
        uint8 indexed source,
        address indexed escrow,
        address sellToken,
        uint256 sellAmount,
        uint256 minBold,
        uint32 validTo,
        bytes32 appData,
        bytes orderUid
    );
    /// @notice Order custody was returned; gross BOLD after a proven fill includes same-purpose donations.
    /// @param orderId Module-local order identity.
    /// @param source Original immutable accounting source.
    /// @param escrow Closed one-shot custody address.
    /// @param filled True only when the entire finite input allowance was spent.
    /// @param sellAmount Original exact input atoms.
    /// @param refundSell Original unspent input returned; zero on a proven fill.
    /// @param boldReceived Gross BOLD after proven fill; zero on an unfilled cancellation.
    event CowOrderClosed(
        uint256 indexed orderId,
        uint8 indexed source,
        address indexed escrow,
        bool filled,
        uint256 sellAmount,
        uint256 refundSell,
        uint256 boldReceived
    );
    /// @notice Terminal unclassified surplus was transferred only to the Safe.
    /// @param orderId Closed order identity.
    /// @param token ERC20 token or zero for forced ETH.
    /// @param amount Exact surplus transferred.
    event CowSurplusSwept(uint256 indexed orderId, address indexed token, uint256 amount);

    /// @notice Fixed manager, the only opener and accounting recipient.
    function manager() external view returns (address);
    /// @notice Fixed Safe configuration and surplus authority.
    function treasury() external view returns (address);
    /// @notice Fixed ETH wrapper.
    function weth() external view returns (address);
    /// @notice Fixed harvested rETH input.
    function reth() external view returns (address);
    /// @notice Fixed output token.
    function bold() external view returns (address);
    /// @notice Fixed verified GPv2 settlement deployment.
    function settlement() external view returns (address);
    /// @notice Verified GPv2 vault relayer, sole finite-allowance spender.
    function relayer() external view returns (address);
    /// @notice Whether new orders may open; starts false.
    function enabled() external view returns (bool);
    /// @notice Maximum WETH atoms per ETH-source order.
    function maxWeth() external view returns (uint256);
    /// @notice Maximum rETH atoms per harvested-source order.
    function maxReth() external view returns (uint256);
    /// @notice Maximum order lifetime in seconds.
    function maxTtl() external view returns (uint32);
    /// @notice Race-protected next deterministic escrow ID, starting at one.
    function nextOrderId() external view returns (uint256);
    /// @notice Active order per source, or zero; there is no global single-order lock.
    /// @param source One of the four accounting sources.
    function activeOrder(uint8 source) external view returns (uint256);
    /// @notice Number of open orders; at most four.
    function activeCount() external view returns (uint256);
    /// @notice Predict a quote's owner/receiver without binding its amount or limit.
    /// @param orderId Expected next module-local identity.
    function predictEscrow(uint256 orderId) external view returns (address);
    /// @notice Return source and lifecycle data.
    /// @param orderId Module-local identity, including closed orders.
    function order(uint256 orderId) external view returns (Order memory);
    /// @notice Canonical 56-byte order UID.
    /// @param orderId Existing module-local identity.
    function orderUid(uint256 orderId) external view returns (bytes memory);
    /// @notice Return immutable canonical fields for posting, never reconstruct from another quote.
    /// @param orderId Existing module-local identity.
    function orderData(uint256 orderId) external view returns (Data memory);
    /// @notice Safe approves nonzero caps while new orders are paused.
    /// @param wethCap Maximum WETH atoms per order, strictly below uint256 maximum.
    /// @param rethCap Maximum harvested rETH atoms per order, strictly below uint256 maximum.
    /// @param ttl Maximum order lifetime in seconds.
    function configureLimits(uint256 wethCap, uint256 rethCap, uint32 ttl) external;
    /// @notice Safe controls only new-order availability.
    /// @param value True permits configured opens; false does not revoke existing orders.
    function setEnabled(bool value) external;
    /// @notice Debit exactly one already-classified source into a one-shot escrow.
    /// @dev Sources 0/1 receive exact ETH; sources 2/3 pull exact harvested rETH from manager.
    /// @param source One of the four immutable accounting sources.
    /// @param amount Exact source input atoms.
    /// @param minBold Nonzero immutable minimum BOLD atoms.
    /// @param validTo Last valid settlement timestamp within the approved TTL.
    /// @param expectedId Race-protected next identity used for the quote's predicted owner.
    /// @param appData Approved CoW application-data hash.
    /// @return orderId Newly reserved identity.
    /// @return escrow Newly funded one-shot owner and receiver.
    function openOrder(
        uint8 source,
        uint256 amount,
        uint256 minBold,
        uint32 validTo,
        uint256 expectedId,
        bytes32 appData
    ) external payable returns (uint256 orderId, address escrow);
    /// @notice Reconcile once without API/oracle dependency; Safe may cancel before expiry through manager.
    /// @param orderId Existing open identity.
    /// @param allowEarlyCancel Manager authenticates whether the initiating caller is the Safe.
    /// @return source Original immutable accounting source.
    /// @return sellAmount Original input atoms.
    /// @return filled Proven full input consumption.
    /// @return refundSell Unspent original input, excluding unsolicited tokens.
    /// @return receivedBold Gross BOLD following a proven fill.
    function closeOrder(
        uint256 orderId,
        bool allowEarlyCancel
    ) external returns (uint8 source, uint256 sellAmount, bool filled, uint256 refundSell, uint256 receivedBold);
    /// @notice Safe sweeps terminal unsolicited surplus only to fixed treasury; zero token denotes forced ETH.
    /// @param orderId Existing closed identity.
    /// @param token ERC20 token or zero for forced ETH.
    function sweepOrderSurplus(uint256 orderId, address token) external;
}
