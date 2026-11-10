// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { ICowSettlement } from "src/vendor/v2/ICowSettlement.sol";

/// @title One-shot CoW exact-input escrow, deployed only as OpenZeppelin clones
/// @author Seba
/// @notice A finite input allowance proves consumption even after CoW clears expired fill storage.
/// @dev WETH/rETH are fixed standard non-rebasing ERC20 integrations. Closed escrows are never reused/reapproved.
contract SebaCowOrderEscrow {
    using SafeERC20 for IERC20;
    /// @notice Fixed module permitted to initialize/close clones.
    address public immutable module;
    /// @notice Fixed verified settlement contract.
    address public immutable settlement;
    /// @notice Fixed verified finite-allowance spender.
    address public immutable relayer;
    /// @notice Fixed terminal surplus destination.
    address public immutable treasury;
    /// @notice Fixed BOLD output token.
    address public immutable bold;
    /// @notice Terminal flag; no path can approve again after closing.
    bool public closed;
    bool private _initialized;
    I.Data private _order;
    bytes private _uid;

    /// @notice Lock the implementation and pin integration identities for every clone.
    /// @param coordinator Fixed order module.
    /// @param cow Verified CoW settlement deployment.
    /// @param spender Verified CoW vault relayer.
    /// @param safe Fixed terminal surplus recipient.
    /// @param output Fixed BOLD token.
    constructor(address coordinator, address cow, address spender, address safe, address output) {
        module = coordinator;
        settlement = cow;
        relayer = spender;
        treasury = safe;
        bold = output;
        _initialized = true;
    }
    modifier onlyModule() {
        if (msg.sender != module) revert I.Unauthorized();
        _;
    }

    /// @notice Initialize atomically before funding; only the deploying module can initialize a fresh clone.
    /// @param token WETH or harvested rETH.
    /// @param amount Finite exact sell input, less than uint256 maximum.
    /// @param minimum Minimum BOLD atoms promised by the immutable FOK order.
    /// @param expiry Last valid settlement timestamp, inclusive.
    /// @param appData Approved CoW application-data hash.
    function initialize(
        address token,
        uint256 amount,
        uint256 minimum,
        uint32 expiry,
        bytes32 appData
    ) external onlyModule {
        if (_initialized) revert I.InvalidOrder();
        _initialized = true;
        _order = I.Data(
            token,
            bold,
            address(this),
            amount,
            minimum,
            expiry,
            appData,
            0,
            keccak256("sell"),
            false,
            keccak256("erc20"),
            keccak256("erc20")
        );
        bytes32 typeHash = keccak256(
            // Canonical protocol type must remain readable and byte-for-byte exact.
            // solhint-disable-next-line max-line-length
            "Order(address sellToken,address buyToken,address receiver,uint256 sellAmount,uint256 buyAmount,uint32 validTo,bytes32 appData,uint256 feeAmount,string kind,bool partiallyFillable,string sellTokenBalance,string buyTokenBalance)"
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                ICowSettlement(settlement).domainSeparator(),
                keccak256(abi.encode(typeHash, _order))
            )
        );
        _uid = abi.encodePacked(digest, address(this), expiry);
        IERC20(token).forceApprove(relayer, amount);
        ICowSettlement(settlement).setPreSignature(_uid, true);
    }
    /// @notice Return the exact canonical order to post to CoW.
    function orderData() external view returns (I.Data memory) {
        return _order;
    }
    /// @notice Return the exact authenticated 56-byte UID.
    function orderUid() external view returns (bytes memory) {
        return _uid;
    }
    /// @notice Close exactly once; caller has already authorized cancellation timing.
    /// @param cancelUnfilled Whether an unspent order may be revoked and refunded now.
    /// @return filled True only if the entire finite approved input was consumed.
    /// @return refund Exact original sell input on an unfilled cancellation, excluding donations.
    /// @return received Gross BOLD held after a proven fill, including source-specific donations.
    function close(bool cancelUnfilled) external onlyModule returns (bool filled, uint256 refund, uint256 received) {
        if (!_initialized || closed) revert I.ClosedOrder();
        uint256 allowance = IERC20(_order.sellToken).allowance(address(this), relayer);
        if (allowance != 0 && allowance != _order.sellAmount) revert I.InvalidFill();
        filled = allowance == 0;
        if (!filled && !cancelUnfilled) revert I.PendingOrder();
        closed = true;
        IERC20(_order.sellToken).forceApprove(relayer, 0);
        ICowSettlement(settlement).setPreSignature(_uid, false);
        if (filled) {
            received = IERC20(bold).balanceOf(address(this));
            if (received < _order.buyAmount) revert I.InvalidFill();
            _send(bold, module, received);
        } else {
            refund = _order.sellAmount;
            _send(_order.sellToken, module, refund);
        }
    }
    /// @notice Transfer terminal unsolicited tokens/forced ETH only to fixed Safe.
    /// @param token ERC20 address, or zero for forced ETH.
    /// @return amount Exact terminal surplus transferred to the Safe.
    function sweep(address token) external onlyModule returns (uint256 amount) {
        if (!closed) revert I.PendingOrder();
        if (token == address(0)) {
            amount = address(this).balance;
            (bool ok, ) = treasury.call{ value: amount }("");
            if (!ok) revert I.UnexpectedTokenDelta();
        } else {
            amount = IERC20(token).balanceOf(address(this));
            _send(token, treasury, amount);
        }
    }
    function _send(address token, address receiver, uint256 amount) private {
        uint256 beforeSender = IERC20(token).balanceOf(address(this));
        uint256 beforeReceiver = IERC20(token).balanceOf(receiver);
        IERC20(token).safeTransfer(receiver, amount);
        if (
            IERC20(token).balanceOf(address(this)) != beforeSender - amount ||
            IERC20(token).balanceOf(receiver) != beforeReceiver + amount
        ) revert I.UnexpectedTokenDelta();
    }
}
