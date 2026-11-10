// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IWETH } from "src/vendor/various/IWETH.sol";
import { ICowSettlement } from "src/vendor/v2/ICowSettlement.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "./SebaCowOrderEscrow.sol";

/// @title Four-source CoW intent coordinator
/// @author Seba
/// @notice Quote/minimum-price trust is explicitly governed; no oracle or particular AMM is required.
/// @dev Only isolated already-assigned manager assets enter orders. Native supporter backing never enters this module.
contract SebaCowIntentModule is ISebaCowIntentModule, ReentrancyGuard {
    using SafeERC20 for IERC20;
    /// @inheritdoc ISebaCowIntentModule
    address public immutable manager;
    /// @inheritdoc ISebaCowIntentModule
    address public immutable treasury;
    /// @inheritdoc ISebaCowIntentModule
    address public immutable weth;
    /// @inheritdoc ISebaCowIntentModule
    address public immutable reth;
    /// @inheritdoc ISebaCowIntentModule
    address public immutable bold;
    /// @inheritdoc ISebaCowIntentModule
    address public immutable settlement;
    /// @inheritdoc ISebaCowIntentModule
    address public immutable relayer;
    /// @notice Locked clone implementation, never used to hold order funds.
    address public immutable implementation;
    /// @inheritdoc ISebaCowIntentModule
    bool public enabled;
    /// @inheritdoc ISebaCowIntentModule
    uint256 public maxWeth;
    /// @inheritdoc ISebaCowIntentModule
    uint256 public maxReth;
    /// @inheritdoc ISebaCowIntentModule
    uint32 public maxTtl;
    /// @inheritdoc ISebaCowIntentModule
    uint256 public nextOrderId = 1;
    /// @inheritdoc ISebaCowIntentModule
    mapping(uint8 source => uint256 orderId) public activeOrder;
    /// @inheritdoc ISebaCowIntentModule
    uint256 public activeCount;
    mapping(uint256 id => Order order) private _orders;

    /// @notice Pin reviewed integrations; address verification against the production chain remains a release gate.
    /// @param coordinator Fixed manager and sole accounting recipient.
    /// @param safe Fixed Safe configuration and terminal-surplus authority.
    /// @param wrapper Verified WETH contract.
    /// @param carry Verified rETH contract.
    /// @param output Verified BOLD contract.
    /// @param cow Verified CoW settlement contract and EIP-712 domain.
    constructor(address coordinator, address safe, address wrapper, address carry, address output, address cow) {
        if (
            coordinator.code.length == 0 ||
            safe.code.length == 0 ||
            wrapper == carry ||
            wrapper == output ||
            carry == output ||
            IERC20Metadata(wrapper).decimals() != 18 ||
            IERC20Metadata(carry).decimals() != 18 ||
            IERC20Metadata(output).decimals() != 18 ||
            cow.code.length == 0
        ) revert InvalidConfiguration();
        address spender = ICowSettlement(cow).vaultRelayer();
        if (spender.code.length == 0 || ICowSettlement(cow).domainSeparator() == bytes32(0))
            revert InvalidConfiguration();
        manager = coordinator;
        treasury = safe;
        weth = wrapper;
        reth = carry;
        bold = output;
        settlement = cow;
        relayer = spender;
        implementation = address(new SebaCowOrderEscrow(address(this), cow, spender, safe, output));
    }
    modifier onlySafe() {
        if (msg.sender != treasury) revert Unauthorized();
        _;
    }
    modifier onlyManager() {
        if (msg.sender != manager) revert Unauthorized();
        _;
    }
    /// @notice Accept only WETH unwrapping refunds; forced ETH remains unclassified.
    receive() external payable {
        if (msg.sender != weth) revert Unauthorized();
    }
    /// @inheritdoc ISebaCowIntentModule
    function configureLimits(uint256 wethCap, uint256 rethCap, uint32 ttl) external onlySafe {
        if (
            enabled ||
            wethCap == 0 ||
            rethCap == 0 ||
            wethCap == type(uint256).max ||
            rethCap == type(uint256).max ||
            ttl == 0
        ) revert InvalidConfiguration();
        maxWeth = wethCap;
        maxReth = rethCap;
        maxTtl = ttl;
        emit CowLimitsConfigured(wethCap, rethCap, ttl);
    }
    /// @inheritdoc ISebaCowIntentModule
    function setEnabled(bool value) external onlySafe {
        if (value && maxTtl == 0) revert InvalidConfiguration();
        enabled = value;
        emit CowExecutionSet(value);
    }
    /// @inheritdoc ISebaCowIntentModule
    function predictEscrow(uint256 id) public view returns (address) {
        return Clones.predictDeterministicAddress(implementation, bytes32(id), address(this));
    }
    /// @inheritdoc ISebaCowIntentModule
    function order(uint256 id) external view returns (Order memory) {
        return _orders[id];
    }
    /// @inheritdoc ISebaCowIntentModule
    function orderUid(uint256 id) external view returns (bytes memory) {
        return SebaCowOrderEscrow(_existing(id).escrow).orderUid();
    }
    /// @inheritdoc ISebaCowIntentModule
    function orderData(uint256 id) external view returns (Data memory) {
        return SebaCowOrderEscrow(_existing(id).escrow).orderData();
    }
    /// @inheritdoc ISebaCowIntentModule
    function openOrder(
        uint8 source,
        uint256 amount,
        uint256 minBold,
        uint32 validTo,
        uint256 expectedId,
        bytes32 appData
    ) external payable nonReentrant onlyManager returns (uint256 id, address escrow) {
        if (!enabled) revert ExecutionDisabled();
        if (
            source > 3 ||
            amount == 0 ||
            amount >= (type(uint256).max) ||
            amount > (source < 2 ? maxWeth : maxReth) ||
            minBold == 0 ||
            validTo <= block.timestamp ||
            uint256(validTo) - block.timestamp > maxTtl ||
            expectedId != nextOrderId ||
            activeOrder[source] != 0 ||
            msg.value != (source < 2 ? amount : 0)
        ) revert InvalidOrder();
        id = nextOrderId++;
        escrow = Clones.cloneDeterministic(implementation, bytes32(id));
        _orders[id] = Order(escrow, source, validTo, amount, minBold, false);
        activeOrder[source] = id;
        ++activeCount;
        address token = source < 2 ? weth : reth;
        SebaCowOrderEscrow(escrow).initialize(token, amount, minBold, validTo, appData);
        uint256 beforeBalance = IERC20(token).balanceOf(escrow);
        if (source < 2) {
            uint256 beforeWeth = IERC20(weth).balanceOf(address(this));
            IWETH(weth).deposit{ value: amount }();
            if (IERC20(weth).balanceOf(address(this)) != beforeWeth + amount) revert UnexpectedTokenDelta();
            IERC20(weth).safeTransfer(escrow, amount);
            if (IERC20(weth).balanceOf(address(this)) != beforeWeth) revert UnexpectedTokenDelta();
        } else {
            uint256 beforeManager = IERC20(reth).balanceOf(manager);
            IERC20(reth).safeTransferFrom(manager, escrow, amount);
            if (IERC20(reth).balanceOf(manager) != beforeManager - amount) revert UnexpectedTokenDelta();
        }
        if (IERC20(token).balanceOf(escrow) != beforeBalance + amount) revert UnexpectedTokenDelta();
        emit CowOrderOpened(
            id,
            source,
            escrow,
            token,
            amount,
            minBold,
            validTo,
            appData,
            SebaCowOrderEscrow(escrow).orderUid()
        );
    }
    /// @inheritdoc ISebaCowIntentModule
    function closeOrder(
        uint256 id,
        bool allowEarlyCancel
    )
        external
        nonReentrant
        onlyManager
        returns (uint8 source, uint256 sellAmount, bool filled, uint256 refundSell, uint256 receivedBold)
    {
        Order storage o = _orders[id];
        if (o.escrow == address(0) || o.closed) revert ClosedOrder();
        o.closed = true;
        source = o.source;
        sellAmount = o.sellAmount;
        uint256 beforeBold = IERC20(bold).balanceOf(address(this));
        address token = source < 2 ? weth : reth;
        uint256 beforeSell = IERC20(token).balanceOf(address(this));
        (filled, refundSell, receivedBold) = SebaCowOrderEscrow(o.escrow).close(
            allowEarlyCancel || block.timestamp > o.validTo
        );
        if (
            IERC20(bold).balanceOf(address(this)) != beforeBold + receivedBold ||
            IERC20(token).balanceOf(address(this)) != beforeSell + refundSell
        ) revert UnexpectedTokenDelta();
        delete activeOrder[source];
        --activeCount;
        if (refundSell != 0) {
            if (source < 2) {
                IWETH(weth).withdraw(refundSell);
                (bool ok, ) = manager.call{ value: refundSell }("");
                if (!ok) revert UnexpectedTokenDelta();
            } else _send(reth, refundSell);
        }
        if (receivedBold != 0) _send(bold, receivedBold);
        emit CowOrderClosed(id, source, o.escrow, filled, sellAmount, refundSell, receivedBold);
    }
    /// @inheritdoc ISebaCowIntentModule
    function sweepOrderSurplus(uint256 id, address token) external nonReentrant onlySafe {
        Order memory o = _existing(id);
        if (!o.closed) revert PendingOrder();
        emit CowSurplusSwept(id, token, SebaCowOrderEscrow(o.escrow).sweep(token));
    }
    function _existing(uint256 id) private view returns (Order memory o) {
        o = _orders[id];
        if (o.escrow == address(0)) revert InvalidOrder();
    }
    function _send(address token, uint256 amount) private {
        uint256 beforeSender = IERC20(token).balanceOf(address(this));
        uint256 beforeReceiver = IERC20(token).balanceOf(manager);
        IERC20(token).safeTransfer(manager, amount);
        if (
            IERC20(token).balanceOf(address(this)) != beforeSender - amount ||
            IERC20(token).balanceOf(manager) != beforeReceiver + amount
        ) revert UnexpectedTokenDelta();
    }
}
