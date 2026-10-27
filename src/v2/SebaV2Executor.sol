// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { IWETH } from "src/vendor/various/IWETH.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import {
    IExecutorYearn,
    IExecutorCurve,
    IExecutorRocketStorage,
    IExecutorRocketBalances,
    IExecutorRocketSettings,
    IExecutorRocketPool,
    IExecutorReth
} from "src/vendor/v2/IExecutorProtocols.sol";

/// @title Seba V2 fixed-route executor
/// @notice Non-upgradeable, manager-only execution with Safe-approved, disabled-by-default limits.
/// @dev Every hop must consume the full current call's input or the whole call reverts. Existing dust is never swept.
/// @author Seba Protocol
contract SebaV2Executor is IV2Executor, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Public getter names deliberately match the shared interface.
    // solhint-disable immutable-vars-naming
    /// @notice Fixed manager, sole route caller and output recipient.
    address public immutable override manager;
    /// @notice Fixed governance Safe authorized to configure and enable routes.
    address public immutable override treasury;
    // solhint-enable immutable-vars-naming
    Config private _config;
    Limits private _limits;
    /// @inheritdoc IV2Executor
    bool public override enabled;
    bool private _configured;

    /// @notice Set immutable integrations; governance and manager must already be deployed contracts.
    /// @param c Fixed integrations, token asset graph and contract authorities for the deployment chain.
    constructor(Config memory c) {
        address[13] memory identities = [
            c.manager,
            c.treasury,
            c.reth,
            c.weth,
            c.usdc,
            c.bold,
            c.yBold,
            c.ysyBold,
            c.swapRouter,
            c.curvePool,
            c.ethUsdFeed,
            c.usdcUsdFeed,
            c.rocketStorage
        ];
        for (uint256 i; i < identities.length; ++i) {
            if (identities[i].code.length == 0) revert InvalidConfiguration();
        }
        if (c.manager == c.treasury) revert InvalidConfiguration();
        address[6] memory tokens = [c.reth, c.weth, c.usdc, c.bold, c.yBold, c.ysyBold];
        for (uint256 i; i < tokens.length; ++i) {
            if (IERC20Metadata(tokens[i]).decimals() != (i == 2 ? 6 : 18)) revert InvalidConfiguration();
            for (uint256 j; j < i; ++j) if (tokens[i] == tokens[j]) revert InvalidConfiguration();
        }
        _validateAssetGraph(c);
        manager = c.manager;
        treasury = c.treasury;
        _config = c;
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
    function configureLimits(Limits calldata proposed) external {
        if (msg.sender != treasury) revert Unauthorized();
        if (
            enabled ||
            proposed.maxEth == 0 ||
            proposed.maxReth == 0 ||
            proposed.maxYsy == 0 ||
            proposed.maxMintFeeWad >= 1e18 ||
            proposed.ethMaxAge == 0 ||
            proposed.usdcMaxAge == 0 ||
            proposed.reportMaxAge == 0 ||
            proposed.reportMaxBlockLag == 0 ||
            proposed.maxDeadline == 0 ||
            proposed.slippageBps >= 10_000 ||
            proposed.pegBps >= 10_000 ||
            proposed.wethUsdcFee == 0 ||
            proposed.rethWethFee == 0 ||
            proposed.depositPool.code.length == 0 ||
            proposed.networkBalances.code.length == 0 ||
            proposed.depositSettings.code.length == 0
        ) revert InvalidConfiguration();
        _limits = proposed;
        _configured = true;
        emit LimitsConfigured(keccak256(abi.encode(proposed)));
    }

    /// @inheritdoc IV2Executor
    function setEnabled(bool proposed) external {
        if (msg.sender != treasury) revert Unauthorized();
        if (proposed && !_configured) revert InvalidConfiguration();
        enabled = proposed;
        emit ExecutionEnabled(proposed);
    }

    /// @inheritdoc IV2Executor
    function investReth(uint256 minimum, uint256 deadline) external payable nonReentrant returns (uint256 output) {
        _begin(msg.value, minimum, deadline, _limits.maxEth);
        _rocket(true);
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

    /// @inheritdoc IV2Executor
    function investYsyBold(uint256 minimum, uint256 deadline) external payable nonReentrant returns (uint256 output) {
        _begin(msg.value, minimum, deadline, _limits.maxEth);
        uint256 bold = _ethToBold(msg.value, deadline);
        uint256 yBold = _deposit(_config.yBold, _config.bold, bold);
        output = _deposit(_config.ysyBold, _config.yBold, yBold);
        _deliver(_config.ysyBold, output, minimum);
        emit RouteExecuted(1, msg.value, output);
    }

    /// @inheritdoc IV2Executor
    function convertEthToBold(
        uint256 minimum,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 output) {
        _begin(msg.value, minimum, deadline, _limits.maxEth);
        output = _ethToBold(msg.value, deadline);
        _deliver(_config.bold, output, minimum);
        emit RouteExecuted(2, msg.value, output);
    }

    /// @inheritdoc IV2Executor
    function convertRethToBold(
        uint256 amount,
        uint256 minimum,
        uint256 deadline
    ) external nonReentrant returns (uint256 output) {
        _begin(amount, minimum, deadline, _limits.maxReth);
        _rocket(false);
        _pull(_config.reth, amount);
        uint256 referenceEth = IExecutorReth(_config.reth).getEthValue(amount);
        uint256 weth = _swap(_config.reth, _config.weth, _limits.rethWethFee, amount, _floor(referenceEth), deadline);
        output = _wethToBold(weth, deadline);
        _deliver(_config.bold, output, minimum);
        emit RouteExecuted(3, amount, output);
    }

    /// @inheritdoc IV2Executor
    function convertYsyToBold(
        uint256 amount,
        uint256 minimum,
        uint256 deadline
    ) external nonReentrant returns (uint256 output) {
        _begin(amount, minimum, deadline, _limits.maxYsy);
        _pull(_config.ysyBold, amount);
        uint256 yBold = _redeem(_config.ysyBold, _config.yBold, amount);
        output = _redeem(_config.yBold, _config.bold, yBold);
        _deliver(_config.bold, output, minimum);
        emit RouteExecuted(4, amount, output);
    }

    /// @dev Verify both Yearn asset edges and the exact Curve coin orientation at deployment.
    function _validateAssetGraph(Config memory c) private view {
        if (
            IExecutorYearn(c.yBold).asset() != c.bold ||
            IExecutorYearn(c.ysyBold).asset() != c.yBold ||
            IExecutorCurve(c.curvePool).coins(0) != c.bold ||
            IExecutorCurve(c.curvePool).coins(1) != c.usdc
        ) revert InvalidConfiguration();
    }

    /// @dev Bound the current call before any venue interaction; cap is in that route's native input atoms.
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

    /// @dev Require the Safe-reviewed current registry entries and fresh, non-future Rocket Pool report.
    function _rocket(bool minting) private view {
        IExecutorRocketStorage registry = IExecutorRocketStorage(_config.rocketStorage);
        if (
            registry.getAddress(keccak256(abi.encodePacked("contract.address", "rocketNetworkBalances"))) !=
            _limits.networkBalances
        ) {
            revert RegistryChanged();
        }
        if (
            minting &&
            (registry.getAddress(keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))) !=
                _limits.depositPool ||
                registry.getAddress(
                    keccak256(abi.encodePacked("contract.address", "rocketDAOProtocolSettingsDeposit"))
                ) !=
                _limits.depositSettings)
        ) {
            revert RegistryChanged();
        }
        uint256 timestamp = IExecutorRocketBalances(_limits.networkBalances).getBalancesTimestamp();
        uint256 number = IExecutorRocketBalances(_limits.networkBalances).getBalancesBlock();
        if (timestamp == 0 || timestamp > block.timestamp || number == 0 || number > block.number)
            revert InvalidOracle();
        if (block.timestamp - timestamp > _limits.reportMaxAge || block.number - number > _limits.reportMaxBlockLag)
            revert StaleOracle();
    }

    /// @dev Wrap exactly this call's ETH; preserve all pre-existing WETH and forced ETH.
    function _ethToBold(uint256 amount, uint256 deadline) private returns (uint256) {
        uint256 beforeBalance = IERC20(_config.weth).balanceOf(address(this));
        IWETH(_config.weth).deposit{ value: amount }();
        if (IERC20(_config.weth).balanceOf(address(this)) - beforeBalance != amount) revert UnexpectedTokenDelta();
        return _wethToBold(amount, deadline);
    }

    /// @dev Independently floor both swap hops and normalize the inverse Curve EMA to BOLD/USD.
    function _wethToBold(uint256 amount, uint256 deadline) private returns (uint256) {
        uint256 ethPrice = _price(_config.ethUsdFeed, _limits.ethMaxAge);
        uint256 usdcPrice = _price(_config.usdcUsdFeed, _limits.usdcMaxAge);
        _peg(usdcPrice);
        uint256 usd = Math.mulDiv(amount, ethPrice, 1e18);
        uint256 expected = Math.mulDiv(usd, 1e6, usdcPrice);
        uint256 usdc = _swap(_config.weth, _config.usdc, _limits.wethUsdcFee, amount, _floor(expected), deadline);
        // Curve coin[1] (USDC) is quoted in coin[0] (BOLD), not the other way round.
        uint256 boldPerUsdc = IExecutorCurve(_config.curvePool).price_oracle(0);
        if (boldPerUsdc == 0) revert PegExceeded();
        _peg(Math.mulDiv(usdcPrice, 1e18, boldPerUsdc));
        uint256 boldFloor = Math.mulDiv(Math.mulDiv(usdc, usdcPrice, 1e6), 10_000, 10_000 + _limits.pegBps);
        return _curve(usdc, _floor(boldFloor));
    }

    /// @dev Return positive, complete, source-fresh USD price normalized to 18 decimals.
    function _price(address feed, uint256 maxAge) private view returns (uint256 value) {
        (uint80 round, int256 answer, uint256 started, uint256 updated, uint80 answered) = AggregatorV3Interface(feed)
            .latestRoundData();
        uint8 decimals = AggregatorV3Interface(feed).decimals();
        if (
            round == 0 ||
            answer <= 0 ||
            started == 0 ||
            updated < started ||
            updated > block.timestamp ||
            answered < round ||
            decimals > 18
        ) revert InvalidOracle();
        if (block.timestamp - updated > maxAge) revert StaleOracle();
        value = Math.mulDiv(uint256(answer), 1e18, 10 ** decimals);
    }

    /// @dev Reject deviation from one USD beyond the Safe-approved cap, including a zero price.
    function _peg(uint256 price) private view {
        uint256 deviation = price > 1e18 ? price - 1e18 : 1e18 - price;
        if (deviation > uint256(_limits.pegBps) * 1e14) revert PegExceeded();
    }

    /// @dev Round conservative minimum down, but never allow a rounded-to-zero swap floor.
    function _floor(uint256 expected) private view returns (uint256 minimum) {
        minimum = Math.mulDiv(expected, 10_000 - _limits.slippageBps, 10_000);
        if (minimum == 0) revert InsufficientOutput();
    }

    /// @dev Fixed Uniswap exact-input hop; partial consumption or misleading return values revert atomically.
    function _swap(
        address input,
        address output,
        uint24 fee,
        uint256 amount,
        uint256 minimum,
        uint256 deadline
    ) private returns (uint256 received) {
        IERC20 token = IERC20(input);
        uint256 beforeInput = token.balanceOf(address(this));
        uint256 beforeOutput = IERC20(output).balanceOf(address(this));
        token.forceApprove(_config.swapRouter, amount);
        uint256 reported = ISwapRouter(_config.swapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: input,
                tokenOut: output,
                fee: fee,
                recipient: address(this),
                deadline: deadline,
                amountIn: amount,
                amountOutMinimum: minimum,
                sqrtPriceLimitX96: 0
            })
        );
        token.forceApprove(_config.swapRouter, 0);
        if (beforeInput - token.balanceOf(address(this)) != amount) revert PartialInput();
        received = IERC20(output).balanceOf(address(this)) - beforeOutput;
        if (received != reported) revert UnexpectedTokenDelta();
        if (received < minimum) revert InsufficientOutput();
    }

    /// @dev Exchange only USDC index 1 for BOLD index 0, with exact temporary approval and measured deltas.
    function _curve(uint256 amount, uint256 minimum) private returns (uint256 received) {
        IERC20 usdc = IERC20(_config.usdc);
        uint256 beforeInput = usdc.balanceOf(address(this));
        uint256 beforeOutput = IERC20(_config.bold).balanceOf(address(this));
        usdc.forceApprove(_config.curvePool, amount);
        uint256 reported = IExecutorCurve(_config.curvePool).exchange(1, 0, amount, minimum);
        usdc.forceApprove(_config.curvePool, 0);
        if (beforeInput - usdc.balanceOf(address(this)) != amount) revert PartialInput();
        received = IERC20(_config.bold).balanceOf(address(this)) - beforeOutput;
        if (received != reported) revert UnexpectedTokenDelta();
        if (received < minimum) revert InsufficientOutput();
    }

    /// @dev Deposit through one fixed Yearn edge without accepting fewer shares than its canonical preview.
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

    /// @dev Redeem the current call's shares with actual maxLoss zero, not merely a maxRedeem query.
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

    /// @dev Reject fee-on-transfer or non-standard input accounting for the fixed supported token.
    function _pull(address token, uint256 amount) private {
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(manager, address(this), amount);
        if (IERC20(token).balanceOf(address(this)) - beforeBalance != amount) revert UnexpectedTokenDelta();
    }

    /// @dev Deliver only measured current-call output, exclusively to manager; reject transfer taxes.
    function _deliver(address token, uint256 amount, uint256 minimum) private {
        if (amount == 0 || amount < minimum) revert InsufficientOutput();
        uint256 beforeBalance = IERC20(token).balanceOf(manager);
        IERC20(token).safeTransfer(manager, amount);
        if (IERC20(token).balanceOf(manager) - beforeBalance != amount) revert UnexpectedTokenDelta();
    }
}
