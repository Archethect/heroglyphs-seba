// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { ICurveStableSwapNG } from "src/vendor/curve/ICurveStableSwapNG.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IWETH } from "src/vendor/various/IWETH.sol";
import { IYearnVault } from "src/vendor/yearn/IYearnVault.sol";

/**
 * @title YBoldYieldVault
 * @notice Converts ETH into st-yBOLD, tracks principal in yBOLD assets, and pays unlocked yield back in ETH.
 * @dev This is a non-upgradeable adapter for Seba's existing {IYieldManager}. It deliberately keeps governance from
 *      rescuing any core asset, and leaves principal retrieval enabled while deposits and claims are paused.
 */
contract YBoldYieldVault is AccessControl, Pausable, ReentrancyGuard, IYBoldYieldVault {
    using Address for address payable;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYBoldYieldVault
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @inheritdoc IYBoldYieldVault
    bytes32 public constant YIELDMANAGER_ROLE = keccak256("YIELDMANAGER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// Basis-point denominator.
    uint256 public constant BPS_DENOMINATOR = 10_000;
    /// Uniswap V3 WETH/USDC pool fee tier (0.05%).
    uint24 public constant UNIV3_FEE_TIER = 500;
    /// Maximum configurable per-swap slippage (10%).
    uint16 public constant MAX_SWAP_SLIPPAGE_BPS = 1000;
    /// Maximum configurable BOLD moving-average peg deviation (5%).
    uint16 public constant MAX_BOLD_PEG_DEVIATION_BPS = 500;
    /// Maximum configurable Yearn redemption loss tolerance (10%).
    uint16 public constant MAX_YEARN_LOSS_BPS = 1000;
    /// Yearn ERC-4626 share rounding dust tolerated when checking for a strategy loss (0.000001 yBOLD).
    uint256 public constant MAX_ACCOUNTING_DUST = 1e12;
    /// Maximum ETH/USD oracle age (one hour).
    uint256 public constant ETH_USD_ORACLE_MAX_AGE = 1 hours;
    /// Maximum USDC/USD oracle age (23 hours).
    uint256 public constant USDC_USD_ORACLE_MAX_AGE = 23 hours;

    /*//////////////////////////////////////////////////////////////
                       IMMUTABLE REFERENCES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYBoldYieldVault
    address public immutable WETH;
    /// @inheritdoc IYBoldYieldVault
    address public immutable USDC;
    /// @inheritdoc IYBoldYieldVault
    address public immutable BOLD;
    /// @inheritdoc IYBoldYieldVault
    ISwapRouter public immutable swapRouter;
    /// @inheritdoc IYBoldYieldVault
    ICurveStableSwapNG public immutable curvePool;
    /// @inheritdoc IYBoldYieldVault
    IYearnVault public immutable yBold;
    /// @inheritdoc IYBoldYieldVault
    IYearnVault public immutable stYBold;
    /// @inheritdoc IYBoldYieldVault
    AggregatorV3Interface public immutable ethUsdFeed;
    /// @inheritdoc IYBoldYieldVault
    AggregatorV3Interface public immutable usdcUsdFeed;

    uint8 private immutable ethUsdFeedDecimals;
    uint8 private immutable usdcUsdFeedDecimals;

    /*//////////////////////////////////////////////////////////////
                             CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYBoldYieldVault
    uint16 public wethUsdcSlippageBps = 50;
    /// @inheritdoc IYBoldYieldVault
    uint16 public boldUsdcSlippageBps = 50;
    /// @inheritdoc IYBoldYieldVault
    uint16 public maxBoldPegDeviationBps = 100;
    /// @inheritdoc IYBoldYieldVault
    uint16 public normalYearnMaxLossBps;
    /// @inheritdoc IYBoldYieldVault
    uint16 public emergencyYearnMaxLossBps = 100;
    /// @inheritdoc IYBoldYieldVault
    bool public emergencyMode;

    /*//////////////////////////////////////////////////////////////
                              ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYBoldYieldVault
    uint256 public principalShares;
    /// @inheritdoc IYBoldYieldVault
    uint256 public principalValue;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes and validates the immutable production integration graph.
     * @param admin Address granted the self-administered {ADMIN_ROLE}.
     * @param yieldManager Existing Seba YieldManager granted {YIELDMANAGER_ROLE}.
     * @param weth WETH token.
     * @param usdc USDC token.
     * @param bold BOLD token.
     * @param router Uniswap V3 SwapRouter.
     * @param boldUsdcPool Curve StableSwap-NG BOLD/USDC pool.
     * @param yearnBold Yearn yBOLD vault whose asset must be BOLD.
     * @param stakedYearnBold Yearn st-yBOLD strategy whose asset must be yBOLD.
     * @param ethUsd Chainlink ETH/USD feed.
     * @param usdcUsd Chainlink USDC/USD feed.
     */
    constructor(
        address admin,
        address yieldManager,
        address weth,
        address usdc,
        address bold,
        address router,
        address boldUsdcPool,
        address yearnBold,
        address stakedYearnBold,
        address ethUsd,
        address usdcUsd
    ) {
        if (admin == address(0) || yieldManager == address(0)) revert InvalidAddress();

        _requireContract(yieldManager);
        _requireContract(weth);
        _requireContract(usdc);
        _requireContract(bold);
        _requireContract(router);
        _requireContract(boldUsdcPool);
        _requireContract(yearnBold);
        _requireContract(stakedYearnBold);
        _requireContract(ethUsd);
        _requireContract(usdcUsd);

        _requireDecimals(weth, 18);
        _requireDecimals(usdc, 6);
        _requireDecimals(bold, 18);
        _requireDecimals(yearnBold, 18);
        _requireDecimals(stakedYearnBold, 18);

        ICurveStableSwapNG pool = ICurveStableSwapNG(boldUsdcPool);
        _requireAsset(boldUsdcPool, bold, pool.coins(0));
        _requireAsset(boldUsdcPool, usdc, pool.coins(1));
        _requireAsset(yearnBold, bold, IYearnVault(yearnBold).asset());
        _requireAsset(stakedYearnBold, yearnBold, IYearnVault(stakedYearnBold).asset());

        uint8 ethDecimals = AggregatorV3Interface(ethUsd).decimals();
        uint8 usdcDecimals = AggregatorV3Interface(usdcUsd).decimals();
        if (ethDecimals > 18) revert InvalidDecimals(ethUsd, 18, ethDecimals);
        if (usdcDecimals > 18) revert InvalidDecimals(usdcUsd, 18, usdcDecimals);

        _grantRole(ADMIN_ROLE, admin);
        _grantRole(YIELDMANAGER_ROLE, yieldManager);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(YIELDMANAGER_ROLE, ADMIN_ROLE);

        WETH = weth;
        USDC = usdc;
        BOLD = bold;
        swapRouter = ISwapRouter(router);
        curvePool = pool;
        yBold = IYearnVault(yearnBold);
        stYBold = IYearnVault(stakedYearnBold);
        ethUsdFeed = AggregatorV3Interface(ethUsd);
        usdcUsdFeed = AggregatorV3Interface(usdcUsd);
        ethUsdFeedDecimals = ethDecimals;
        usdcUsdFeedDecimals = usdcDecimals;
    }

    /*//////////////////////////////////////////////////////////////
                               DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldVault
    function deposit()
        external
        payable
        override
        nonReentrant
        onlyRole(YIELDMANAGER_ROLE)
        returns (uint256 depositValue)
    {
        _requireOperational();
        if (msg.value == 0) revert NoEthProvided();
        if (principalValue != 0) {
            uint256 currentAssets = stYBold.convertToAssets(principalShares);
            if (currentAssets < principalValue && principalValue - currentAssets > MAX_ACCOUNTING_DUST) {
                revert StrategyUnderwater();
            }
        }
        _requireYearnDepositAvailable(yBold, 1);
        _requireYearnDepositAvailable(stYBold, 1);

        IWETH(WETH).deposit{ value: msg.value }();
        uint256 usdcOut = _swapUniswap(WETH, USDC, msg.value, _minEthToUsdc(msg.value));

        _checkBoldPeg();
        uint256 nominalBold = Math.mulDiv(usdcOut, 1e18, 1e6);
        uint256 boldMin = _minBoldSwapOutput(nominalBold);
        uint256 boldOut = _swapCurve(1, 0, USDC, usdcOut, boldMin);

        uint256 yBoldCapacity = yBold.maxDeposit(address(this));
        if (yBold.isShutdown() || boldOut > yBoldCapacity) {
            revert StrategyUnavailable(address(yBold), boldOut, yBoldCapacity);
        }
        uint256 yBoldShares = _depositIntoYearn(IERC20(BOLD), yBold, boldOut);

        uint256 stYBoldCapacity = stYBold.maxDeposit(address(this));
        if (stYBold.isShutdown() || yBoldShares > stYBoldCapacity) {
            revert StrategyUnavailable(address(stYBold), yBoldShares, stYBoldCapacity);
        }
        uint256 stYBoldShares = _depositIntoYearn(IERC20(address(yBold)), stYBold, yBoldShares);

        principalShares += stYBoldShares;
        principalValue += yBoldShares;
        depositValue = yBoldShares;

        emit Deposited(msg.sender, msg.value, depositValue, stYBoldShares);
    }

    /*//////////////////////////////////////////////////////////////
                            YIELD REALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldVault
    function claimYield() external override nonReentrant onlyRole(YIELDMANAGER_ROLE) {
        _requireOperational();
        if (!IYieldManager(msg.sender).yieldFlowActive()) {
            emit YieldClaimed(0, 0, 0);
            return;
        }

        uint256 yBoldYield = claimableYield();
        if (yBoldYield < 1e12) {
            emit YieldClaimed(0, 0, 0);
            return;
        }

        uint256 sharesToRedeem = stYBold.convertToShares(yBoldYield);
        if (sharesToRedeem == 0) {
            emit YieldClaimed(0, 0, 0);
            return;
        }

        principalShares -= sharesToRedeem;
        uint256 yBoldOut = _redeemYearn(stYBold, sharesToRedeem);
        uint256 ethOut = _yBoldToEth(yBoldOut);

        payable(msg.sender).sendValue(ethOut);
        emit YieldClaimed(sharesToRedeem, yBoldOut, ethOut);
    }

    /// @inheritdoc IYBoldYieldVault
    function claimableYield() public view returns (uint256) {
        uint256 currentValue = stYBold.convertToAssets(principalShares);
        return currentValue > principalValue ? currentValue - principalValue : 0;
    }

    /*//////////////////////////////////////////////////////////////
                         PRINCIPAL RETRIEVAL
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldVault
    function retrievePrincipal(uint256 depositValue) external override nonReentrant onlyRole(YIELDMANAGER_ROLE) {
        if (depositValue == 0) revert CannotRetrieveZero();
        if (principalShares == 0 || principalValue == 0) revert NoPrincipal();

        uint256 valueToRemove;
        uint256 sharesToRedeem;
        uint256 currentAssets = stYBold.convertToAssets(principalShares);
        if (depositValue >= principalValue) {
            valueToRemove = principalValue;
            sharesToRedeem = currentAssets > principalValue ? stYBold.previewWithdraw(principalValue) : principalShares;
            if (sharesToRedeem == 0 || sharesToRedeem > principalShares) revert NoPrincipal();
            principalValue = 0;
            principalShares -= sharesToRedeem;
        } else {
            valueToRemove = depositValue;
            sharesToRedeem = currentAssets < principalValue
                ? Math.mulDiv(principalShares, depositValue, principalValue, Math.Rounding.Ceil)
                : stYBold.previewWithdraw(depositValue);
            if (sharesToRedeem == 0 || sharesToRedeem > principalShares) revert NoPrincipal();
            principalValue -= depositValue;
            principalShares -= sharesToRedeem;
        }

        uint256 yBoldOut = _redeemYearn(stYBold, sharesToRedeem);
        uint256 ethOut = _yBoldToEth(yBoldOut);

        payable(msg.sender).sendValue(ethOut);
        emit PrincipalRetrieved(valueToRemove, sharesToRedeem, ethOut);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYBoldYieldVault
    function setSwapSlippageBps(uint16 wethUsdcBps, uint16 boldUsdcBps) external onlyRole(ADMIN_ROLE) {
        if (wethUsdcBps > MAX_SWAP_SLIPPAGE_BPS) revert SlippageTooHigh(wethUsdcBps);
        if (boldUsdcBps > MAX_SWAP_SLIPPAGE_BPS) revert SlippageTooHigh(boldUsdcBps);
        wethUsdcSlippageBps = wethUsdcBps;
        boldUsdcSlippageBps = boldUsdcBps;
        emit SwapSlippageSet(wethUsdcBps, boldUsdcBps);
    }

    /// @inheritdoc IYBoldYieldVault
    function setMaxBoldPegDeviationBps(uint16 bps) external onlyRole(ADMIN_ROLE) {
        if (bps > MAX_BOLD_PEG_DEVIATION_BPS) revert PegDeviationTooHigh(bps);
        maxBoldPegDeviationBps = bps;
        emit BoldPegDeviationSet(bps);
    }

    /// @inheritdoc IYBoldYieldVault
    function setYearnMaxLossBps(uint16 normalBps, uint16 emergencyBps) external onlyRole(ADMIN_ROLE) {
        if (normalBps > emergencyBps || emergencyBps > MAX_YEARN_LOSS_BPS) {
            revert InvalidYearnLossConfiguration(normalBps, emergencyBps);
        }
        normalYearnMaxLossBps = normalBps;
        emergencyYearnMaxLossBps = emergencyBps;
        emit YearnMaxLossSet(normalBps, emergencyBps);
    }

    /// @inheritdoc IYBoldYieldVault
    function setEmergencyMode(bool enabled) external onlyRole(ADMIN_ROLE) {
        emergencyMode = enabled;
        emit EmergencyModeSet(enabled);
    }

    /// @inheritdoc IYBoldYieldVault
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @inheritdoc IYBoldYieldVault
    function unpause() external onlyRole(ADMIN_ROLE) {
        if (emergencyMode) revert StrategyNotOperational();
        _unpause();
    }

    /// @inheritdoc IYBoldYieldVault
    function rescueToken(address token, address recipient, uint256 amount) external nonReentrant onlyRole(ADMIN_ROLE) {
        if (token == address(0) || recipient == address(0)) revert InvalidAddress();
        if (_isCoreAsset(token)) revert CoreAsset(token);
        _requireContract(token);
        if (amount == 0) revert ZeroOutput();
        IERC20(token).safeTransfer(recipient, amount);
        emit TokenRescued(token, recipient, amount);
    }

    /// @inheritdoc IYBoldYieldVault
    function currentYearnMaxLossBps() public view returns (uint16) {
        return emergencyMode ? emergencyYearnMaxLossBps : normalYearnMaxLossBps;
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _yBoldToEth(uint256 yBoldAmount) internal returns (uint256 ethOut) {
        uint256 boldOut = _redeemYearn(yBold, yBoldAmount);

        _checkBoldPeg();
        uint256 nominalUsdc = Math.mulDiv(boldOut, 1e6, 1e18);
        if (nominalUsdc == 0) revert ZeroOutput();
        uint256 usdcMin = _minBoldSwapOutput(nominalUsdc);
        uint256 usdcOut = _swapCurve(0, 1, BOLD, boldOut, usdcMin);

        uint256 wethOut = _swapUniswap(USDC, WETH, usdcOut, _minUsdcToEth(usdcOut));
        IWETH(WETH).withdraw(wethOut);
        return wethOut;
    }

    function _depositIntoYearn(IERC20 asset, IYearnVault yearnVault, uint256 amount) internal returns (uint256 shares) {
        asset.forceApprove(address(yearnVault), amount);
        shares = yearnVault.deposit(amount, address(this));
        asset.forceApprove(address(yearnVault), 0);
        if (shares == 0) revert NoSharesMinted(address(yearnVault));
    }

    function _redeemYearn(IYearnVault yearnVault, uint256 shares) internal returns (uint256 assets) {
        uint256 maxLoss = currentYearnMaxLossBps();
        uint256 available = yearnVault.maxRedeem(address(this), maxLoss);
        if (shares > available) revert InsufficientLiquidity(address(yearnVault), shares, available);
        assets = yearnVault.redeem(shares, address(this), address(this), maxLoss);
        if (assets == 0) revert ZeroOutput();
    }

    function _swapUniswap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: UNIV3_FEE_TIER,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(tokenIn).forceApprove(address(swapRouter), 0);
        if (amountOut == 0) revert ZeroOutput();
    }

    function _swapCurve(
        int128 i,
        int128 j,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).forceApprove(address(curvePool), amountIn);
        amountOut = curvePool.exchange(i, j, amountIn, amountOutMinimum, address(this));
        IERC20(tokenIn).forceApprove(address(curvePool), 0);
        if (amountOut == 0) revert ZeroOutput();
    }

    function _minEthToUsdc(uint256 ethAmount) internal view returns (uint256) {
        uint256 ethPrice = _readOracle(ethUsdFeed, ethUsdFeedDecimals, ETH_USD_ORACLE_MAX_AGE);
        uint256 usdcPrice = _readOracle(usdcUsdFeed, usdcUsdFeedDecimals, USDC_USD_ORACLE_MAX_AGE);
        uint256 quote = Math.mulDiv(ethAmount, ethPrice, usdcPrice * 1e12);
        return _subtractBps(quote, wethUsdcSlippageBps);
    }

    function _minUsdcToEth(uint256 usdcAmount) internal view returns (uint256) {
        uint256 ethPrice = _readOracle(ethUsdFeed, ethUsdFeedDecimals, ETH_USD_ORACLE_MAX_AGE);
        uint256 usdcPrice = _readOracle(usdcUsdFeed, usdcUsdFeedDecimals, USDC_USD_ORACLE_MAX_AGE);
        uint256 quote = Math.mulDiv(usdcAmount, usdcPrice * 1e12, ethPrice);
        return _subtractBps(quote, wethUsdcSlippageBps);
    }

    function _readOracle(
        AggregatorV3Interface feed,
        uint8 decimals_,
        uint256 maxAge
    ) internal view returns (uint256 price) {
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        if (answer <= 0 || updatedAt == 0 || updatedAt > block.timestamp || answeredInRound < roundId) {
            revert OracleInvalid(address(feed));
        }
        if (block.timestamp - updatedAt > maxAge) revert OracleStale(address(feed), updatedAt);
        uint256 unsignedAnswer = SafeCast.toUint256(answer);
        uint256 scale = 10 ** (18 - decimals_);
        if (unsignedAnswer > type(uint256).max / scale) revert OracleInvalid(address(feed));
        return unsignedAnswer * scale;
    }

    function _checkBoldPeg() internal view {
        uint256 price = curvePool.price_oracle(0);
        uint256 deviation = price > 1e18 ? price - 1e18 : 1e18 - price;
        uint256 maximumDeviation = Math.mulDiv(1e18, maxBoldPegDeviationBps, BPS_DENOMINATOR);
        if (deviation > maximumDeviation) revert BoldPegDeviationExceeded(price, maxBoldPegDeviationBps);
    }

    function _requireOperational() internal view {
        if (paused() || emergencyMode) revert StrategyNotOperational();
    }

    function _requireYearnDepositAvailable(IYearnVault yearnVault, uint256 requested) internal view {
        uint256 available = yearnVault.maxDeposit(address(this));
        if (yearnVault.isShutdown() || available < requested) {
            revert StrategyUnavailable(address(yearnVault), requested, available);
        }
    }

    function _subtractBps(uint256 amount, uint16 bps) internal pure returns (uint256) {
        return Math.mulDiv(amount, BPS_DENOMINATOR - bps, BPS_DENOMINATOR);
    }

    function _minBoldSwapOutput(uint256 nominalOutput) internal view returns (uint256) {
        // The peg guard permits this much deviation from parity before execution slippage is applied.
        // A stricter nominal swap floor would reject prices that the peg guard explicitly accepts.
        return _subtractBps(nominalOutput, boldUsdcSlippageBps + maxBoldPegDeviationBps);
    }

    function _isCoreAsset(address token) internal view returns (bool) {
        return token == WETH || token == USDC || token == BOLD || token == address(yBold) || token == address(stYBold);
    }

    function _requireContract(address target) internal view {
        if (target == address(0)) revert InvalidAddress();
        if (target.code.length == 0) revert InvalidContract(target);
    }

    function _requireDecimals(address token, uint8 expected) internal view {
        uint8 actual = IERC20Metadata(token).decimals();
        if (actual != expected) revert InvalidDecimals(token, expected, actual);
    }

    function _requireAsset(address integration, address expected, address actual) internal pure {
        if (actual != expected) revert InvalidAsset(integration, expected, actual);
    }

    /**
     * @notice Receives ETH only from the configured WETH contract during an unwrap.
     */
    receive() external payable {
        if (msg.sender != WETH) revert UnauthorizedEthSender(msg.sender);
    }
}
