// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*───────────────────────────── Dependencies ───────────────────────────*/
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { IEthToBoldRouter } from "src/interfaces/IEthToBoldRouter.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
/*────────────────────────── Contract Implementation ───────────────────*/

/**
 * @title EthToBoldRouter
 * @notice Swaps ETH→BOLD via CowSwap Eth-flow with `minOut` sized from Chainlink ETH/USD.
 *         Tracks a single open order per initiator and supports cancellation/refunds.
 * @dev See {IEthToBoldRouter} for the external interface.
 */
contract EthToBoldRouter is AccessControl, IEthToBoldRouter {
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                          IMMUTABLE REFERENCES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEthToBoldRouter
    IEthFlow public immutable ETH_FLOW;
    /// @inheritdoc IEthToBoldRouter
    IERC20 public immutable BOLD;

    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEthToBoldRouter
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @inheritdoc IEthToBoldRouter
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Basis points denominator (10,000).
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Order tracking.
    Order public order;
    int64 public quoteCounter;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the EthToBoldRouter.
     * @param ethFlow CowSwap Eth-flow contract address.
     * @param bold BOLD ERC-20 token address.
     * @param admin Admin of the contract
     * @param yieldManager YieldManager address
     */
    constructor(address ethFlow, address bold, address admin, address yieldManager) {
        if (ethFlow == address(0)) revert InvalidAddress();
        if (bold == address(0)) revert InvalidAddress();
        if (admin == address(0)) revert InvalidAddress();
        if (yieldManager == address(0)) revert InvalidAddress();

        _grantRole(ADMIN_ROLE, admin);
        _grantRole(YIELD_MANAGER_ROLE, yieldManager);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(YIELD_MANAGER_ROLE, ADMIN_ROLE);

        ETH_FLOW = IEthFlow(ethFlow);
        BOLD = IERC20(bold);
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow receiving ETH (Eth-flow refunds).
     */
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL / PUBLIC API
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEthToBoldRouter
    function swapExactEthForBold(
        uint256 minBoldBeforeSlippage,
        uint16 slippageBps,
        uint32 validity
    ) external payable override onlyRole(YIELD_MANAGER_ROLE) returns (bytes32 uid) {
        if (msg.value == 0) revert NoEthSent();
        if (slippageBps >= BPS_DENOMINATOR) revert InvalidSlippage(slippageBps, BPS_DENOMINATOR);
        if (order.active) revert OrderAlreadyOpen();

        // 2) Compute min BOLD out (applying slippage)
        uint256 minBold = (minBoldBeforeSlippage * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;

        // 3) Create Eth-flow intent
        IEthFlow.Data memory data = IEthFlow.Data({
            buyToken: BOLD,
            receiver: address(this),
            sellAmount: msg.value,
            buyAmount: minBold,
            appData: bytes32(uint256(0x53ba1)),
            feeAmount: 0,
            validTo: uint32(block.timestamp) + validity,
            partiallyFillable: false,
            quoteId: quoteCounter
        });

        uid = ETH_FLOW.createOrder{ value: msg.value }(data);

        // 4) Record
        order = Order({ initiator: msg.sender, ethAmount: msg.value, uid: uid, active: true, data: data });

        quoteCounter++;

        emit IntentCreated(msg.sender, msg.value, minBold, uid, data.validTo);
    }

    /// @inheritdoc IEthToBoldRouter
    function finalizeIntent() external override onlyRole(YIELD_MANAGER_ROLE) {
        if (!order.active) revert NoActiveOrder();

        // Try to invalidate. If already invalidated by someone else after expiry, ignore failure.
        try ETH_FLOW.invalidateOrder(order.data) {} catch {
            /* already invalidated or non-cancellable; ignore */
        }

        uint256 balance = address(this).balance;
        uint256 boldBalance = BOLD.balanceOf(address(this));

        if (balance > 0) {
            (bool ok, ) = msg.sender.call{ value: balance }("");
            if (!ok) revert FailedETHRefund();
        }

        if (boldBalance > 0) {
            BOLD.safeTransfer(msg.sender, boldBalance);
        }

        order.active = false;
        emit IntentFinalized(msg.sender, order.uid, balance, boldBalance);
    }
}
