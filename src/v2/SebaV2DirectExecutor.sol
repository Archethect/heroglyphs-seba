// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IV2DirectExecutor } from "src/interfaces/v2/IV2DirectExecutor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import {
    IExecutorYearn,
    IExecutorRocketStorage,
    IExecutorRocketBalances,
    IExecutorRocketSettings,
    IExecutorRocketPool,
    IExecutorReth
} from "src/vendor/v2/IExecutorProtocols.sol";

/// @title Direct-only Seba protocol executor
/// @author Seba
/// @notice Rocket Pool minting and canonical Yearn deposits/redemptions; no DEX or USD oracle paths exist.
/// @dev Legacy Config/Limits ABI is retained for tooling; unused DEX fields must be zero.
contract SebaV2DirectExecutor is IV2DirectExecutor, ReentrancyGuard {
    using SafeERC20 for IERC20;
    /// @inheritdoc IV2DirectExecutor
    uint256 public maximumBold;
    /// @inheritdoc IV2Executor
    bool public enabled;
    /// @inheritdoc IV2Executor
    address public immutable manager;
    /// @inheritdoc IV2Executor
    address public immutable treasury;
    Config private _config;
    Limits private _limits;
    /// @notice BOLD investment cap changed while paused.
    /// @param amount Maximum BOLD atoms per investment.
    event BoldLimitConfigured(uint256 amount);
    /// @notice Deprecated synchronous swap route must use a CoW intent.
    error AsyncOrderRequired();

    /// @notice Validate reciprocal identities and canonical Yearn asset edges.
    /// @param c Fixed identities; deprecated DEX and USD-feed fields must all be zero.
    constructor(Config memory c) {
        address[8] memory identities = [
            c.manager,
            c.treasury,
            c.reth,
            c.weth,
            c.bold,
            c.yBold,
            c.ysyBold,
            c.rocketStorage
        ];
        for (uint256 i; i < identities.length; ++i) if (identities[i].code.length == 0) revert InvalidConfiguration();
        if (
            c.manager == c.treasury ||
            c.usdc != address(0) ||
            c.swapRouter != address(0) ||
            c.curvePool != address(0) ||
            c.ethUsdFeed != address(0) ||
            c.usdcUsdFeed != address(0)
        ) revert InvalidConfiguration();
        _validateTokens([c.reth, c.weth, c.bold, c.yBold, c.ysyBold]);
        if (IExecutorYearn(c.yBold).asset() != c.bold || IExecutorYearn(c.ysyBold).asset() != c.yBold)
            revert InvalidConfiguration();
        _config = c;
        manager = c.manager;
        treasury = c.treasury;
    }
    function _validateTokens(address[5] memory tokens) private view {
        for (uint256 i; i < tokens.length; ++i) {
            if (IERC20Metadata(tokens[i]).decimals() != 18) revert InvalidConfiguration();
            for (uint256 j; j < i; ++j) if (tokens[i] == tokens[j]) revert InvalidConfiguration();
        }
    }
    /// @inheritdoc IV2Executor
    function configuration() external view returns (Config memory) {
        return _config;
    }
    /// @inheritdoc IV2Executor
    function limits() external view returns (Limits memory) {
        return _limits;
    }
    /// @inheritdoc IV2Executor
    function configureLimits(Limits calldata l) external {
        if (msg.sender != treasury) revert Unauthorized();
        if (
            enabled ||
            l.maxEth == 0 ||
            l.maxYsy == 0 ||
            l.maxMintFeeWad >= 1e18 ||
            l.reportMaxAge == 0 ||
            l.reportMaxBlockLag == 0 ||
            l.maxDeadline == 0 ||
            l.ethMaxAge != 0 ||
            l.usdcMaxAge != 0 ||
            l.slippageBps != 0 ||
            l.pegBps != 0 ||
            l.wethUsdcFee != 0 ||
            l.rethWethFee != 0 ||
            l.depositPool.code.length == 0 ||
            l.networkBalances.code.length == 0 ||
            l.depositSettings.code.length == 0
        ) revert InvalidConfiguration();
        _limits = l;
        emit LimitsConfigured(keccak256(abi.encode(l)));
    }
    /// @inheritdoc IV2DirectExecutor
    function configureBoldLimit(uint256 amount) external {
        if (msg.sender != treasury) revert Unauthorized();
        if (enabled || amount == 0) revert InvalidConfiguration();
        maximumBold = amount;
        emit BoldLimitConfigured(amount);
    }
    /// @inheritdoc IV2Executor
    function setEnabled(bool value) external {
        if (msg.sender != treasury) revert Unauthorized();
        if (value && (_limits.maxDeadline == 0 || maximumBold == 0)) revert InvalidConfiguration();
        enabled = value;
        emit ExecutionEnabled(value);
    }
    /// @inheritdoc IV2Executor
    function investReth(uint256 minimum, uint256 deadline) external payable nonReentrant returns (uint256 output) {
        _begin(msg.value, minimum, deadline, _limits.maxEth);
        _rocket();
        uint256 fee = IExecutorRocketSettings(_limits.depositSettings).getDepositFee();
        if (fee > _limits.maxMintFeeWad) revert MintFeeExceeded();
        if (msg.value > IExecutorRocketPool(_limits.depositPool).getMaximumDepositAmount()) revert InvalidExecution();
        uint256 floor = IExecutorReth(_config.reth).getRethValue(msg.value - Math.mulDiv(msg.value, fee, 1e18));
        uint256 beforeBalance = IERC20(_config.reth).balanceOf(address(this));
        IExecutorRocketPool(_limits.depositPool).deposit{ value: msg.value }();
        output = IERC20(_config.reth).balanceOf(address(this)) - beforeBalance;
        _deliver(_config.reth, output, Math.max(minimum, floor));
        emit RouteExecuted(0, msg.value, output);
    }
    /// @inheritdoc IV2DirectExecutor
    function investBold(
        uint256 amount,
        uint256 minimum,
        uint256 deadline
    ) external nonReentrant returns (uint256 output) {
        _begin(amount, minimum, deadline, maximumBold);
        _pull(_config.bold, amount);
        output = _deposit(_config.ysyBold, _config.yBold, _deposit(_config.yBold, _config.bold, amount));
        _deliver(_config.ysyBold, output, minimum);
        emit RouteExecuted(1, amount, output);
    }
    /// @inheritdoc IV2Executor
    function convertYsyToBold(
        uint256 amount,
        uint256 minimum,
        uint256 deadline
    ) external nonReentrant returns (uint256 output) {
        _begin(amount, minimum, deadline, _limits.maxYsy);
        _pull(_config.ysyBold, amount);
        output = _redeem(_config.yBold, _config.bold, _redeem(_config.ysyBold, _config.yBold, amount));
        _deliver(_config.bold, output, minimum);
        emit RouteExecuted(4, amount, output);
    }
    /// @inheritdoc IV2Executor
    function investYsyBold(uint256, uint256) external payable returns (uint256) {
        revert AsyncOrderRequired();
    }
    /// @inheritdoc IV2Executor
    function convertEthToBold(uint256, uint256) external payable returns (uint256) {
        revert AsyncOrderRequired();
    }
    /// @inheritdoc IV2Executor
    function convertRethToBold(uint256, uint256, uint256) external pure returns (uint256) {
        revert AsyncOrderRequired();
    }
    function _begin(uint256 amount, uint256 minimum, uint256 deadline, uint256 cap) private view {
        if (msg.sender != manager) revert Unauthorized();
        if (!enabled) revert ExecutionDisabled();
        if (
            amount == 0 ||
            amount > cap ||
            minimum == 0 ||
            deadline < block.timestamp ||
            deadline - block.timestamp > _limits.maxDeadline
        ) revert InvalidExecution();
    }
    function _rocket() private view {
        IExecutorRocketStorage r = IExecutorRocketStorage(_config.rocketStorage);
        if (
            r.getAddress(keccak256(abi.encodePacked("contract.address", "rocketNetworkBalances"))) !=
            _limits.networkBalances ||
            r.getAddress(keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))) != _limits.depositPool ||
            r.getAddress(keccak256(abi.encodePacked("contract.address", "rocketDAOProtocolSettingsDeposit"))) !=
            _limits.depositSettings
        ) revert RegistryChanged();
        uint256 timestamp = IExecutorRocketBalances(_limits.networkBalances).getBalancesTimestamp();
        uint256 number = IExecutorRocketBalances(_limits.networkBalances).getBalancesBlock();
        if (timestamp == 0 || timestamp > block.timestamp || number == 0 || number > block.number)
            revert InvalidOracle();
        if (block.timestamp - timestamp > _limits.reportMaxAge || block.number - number > _limits.reportMaxBlockLag)
            revert StaleOracle();
    }
    function _deposit(address vault, address asset, uint256 amount) private returns (uint256 received) {
        uint256 minimum = IExecutorYearn(vault).previewDeposit(amount);
        uint256 beforeInput = IERC20(asset).balanceOf(address(this));
        uint256 beforeOutput = IERC20(vault).balanceOf(address(this));
        IERC20(asset).forceApprove(vault, amount);
        uint256 reported = IExecutorYearn(vault).deposit(amount, address(this));
        IERC20(asset).forceApprove(vault, 0);
        if (beforeInput - IERC20(asset).balanceOf(address(this)) != amount) revert PartialInput();
        received = IERC20(vault).balanceOf(address(this)) - beforeOutput;
        if (received != reported) revert UnexpectedTokenDelta();
        if (minimum == 0 || received < minimum) revert InsufficientOutput();
    }
    function _redeem(address vault, address asset, uint256 amount) private returns (uint256 received) {
        if (amount > IExecutorYearn(vault).maxRedeem(address(this))) revert InvalidExecution();
        uint256 minimum = IExecutorYearn(vault).convertToAssets(amount);
        uint256 beforeInput = IERC20(vault).balanceOf(address(this));
        uint256 beforeOutput = IERC20(asset).balanceOf(address(this));
        uint256 reported = IExecutorYearn(vault).redeem(amount, address(this), address(this), 0);
        if (beforeInput - IERC20(vault).balanceOf(address(this)) != amount) revert PartialInput();
        received = IERC20(asset).balanceOf(address(this)) - beforeOutput;
        if (received != reported) revert UnexpectedTokenDelta();
        if (minimum == 0 || received < minimum) revert InsufficientOutput();
    }
    function _pull(address token, uint256 amount) private {
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(manager, address(this), amount);
        if (IERC20(token).balanceOf(address(this)) - beforeBalance != amount) revert UnexpectedTokenDelta();
    }
    function _deliver(address token, uint256 amount, uint256 minimum) private {
        if (amount == 0 || amount < minimum) revert InsufficientOutput();
        uint256 beforeBalance = IERC20(token).balanceOf(manager);
        IERC20(token).safeTransfer(manager, amount);
        if (IERC20(token).balanceOf(manager) != beforeBalance + amount) revert UnexpectedTokenDelta();
    }
}
