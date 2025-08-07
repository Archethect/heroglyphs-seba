// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*────────────────────────────── OpenZeppelin ──────────────────────────*/
import { AccessControl }      from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard }    from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Address }            from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 }          from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 }             from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*─────────────────────────────── Interfaces ───────────────────────────*/
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IQuoter }     from "src/vendor/uniswap_v3/IQuoter.sol";
import { ICurvePool }  from "src/vendor/curve/ICurvePool.sol";
import { IBeefyVault } from "src/vendor/beefy/IBeefyVault.sol";
import { IWETH }       from "src/vendor/various/IWETH.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";

/**
 * @title EUSDUSDCBeefyYieldVault
 * @notice Implements an underlying vault asset-denominated yield strategy:
 *         ① Wraps ETH → WETH → USDC (Uniswap V3),
 *         ② Adds liquidity to USDe/USDC Curve pool,
 *         ③ Stakes LP tokens in a Beefy vault,
 *         ④ Realises yield in ETH on demand.
 */
contract EUSDUSDCBeefyYieldVault is AccessControl, ReentrancyGuard, IEUSDUSDCBeefyYieldVault {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    bytes32 public constant YIELDMANAGER_ROLE = keccak256("YIELDMANAGER_ROLE");

    /*//////////////////////////////////////////////////////////////
                       IMMUTABLE REFERENCES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    address public immutable WETH;
    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    address public immutable USDC;

    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    ISwapRouter public immutable swapRouter;
    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    IQuoter public immutable quoter;
    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    ICurvePool public immutable curvePool;
    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    IBeefyVault public immutable beefy;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    uint24 public constant UNIV3_FEE_TIER = 500; // 0.05 %

    /*//////////////////////////////////////////////////////////////
                             CONFIGURABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    uint16 public slippageBps = 50; // 0.50 %

    /*//////////////////////////////////////////////////////////////
                             ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    uint256 public principalShares;
    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    uint256 public principalValue;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the vault.
     * @param admin Admin address granted {ADMIN_ROLE}.
     * @param yieldManager YieldManager address granted {YIELDMANAGER_ROLE}.
     * @param _weth WETH token address.
     * @param _usdc USDC token address.
     * @param _swapRouter Uniswap V3 router.
     * @param _quoter Uniswap V3 quoter.
     * @param _curvePool Curve pool for USDe/USDC LP.
     * @param _beefy Beefy vault that stakes the LP tokens.
     */
    constructor(
        address admin,
        address yieldManager,
        address _weth,
        address _usdc,
        address _swapRouter,
        address _quoter,
        address _curvePool,
        address _beefy
    ) {
        if (_weth == address(0)) revert InvalidAddress();
        if (_usdc == address(0)) revert InvalidAddress();
        if (_swapRouter == address(0)) revert InvalidAddress();
        if (_quoter == address(0)) revert InvalidAddress();
        if (_curvePool == address(0)) revert InvalidAddress();
        if (_beefy == address(0)) revert InvalidAddress();

        _grantRole(ADMIN_ROLE, admin);
        _grantRole(YIELDMANAGER_ROLE, yieldManager);
        _setRoleAdmin(YIELDMANAGER_ROLE, ADMIN_ROLE);

        WETH = _weth;
        USDC = _usdc;
        swapRouter = ISwapRouter(_swapRouter);
        quoter = IQuoter(_quoter);
        curvePool = ICurvePool(_curvePool);
        beefy = IBeefyVault(_beefy);
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
        if (msg.value == 0) revert NoEthProvided();

        /* Wrap ETH → WETH */
        IWETH(WETH).deposit{ value: msg.value }();

        /* WETH → USDC via UniV3, using quoter for min-out */
        uint256 quotedUsdc = _quoteEthToUsdc(msg.value);
        uint256 usdcMin = (quotedUsdc * (10_000 - slippageBps)) / 10_000;
        uint256 usdcOut = _swapExactInput(WETH, USDC, msg.value, usdcMin);

        /* Add liquidity (USDe/USDC) → LP tokens */
        uint256[2] memory amounts; // [USDe, USDC]; we only fill USDC index 1
        amounts[1] = usdcOut;
        uint256 lpExpected = curvePool.calc_token_amount(amounts, true);
        uint256 minMint = (lpExpected * (10_000 - slippageBps)) / 10_000;

        IERC20(USDC).approve(address(curvePool), usdcOut);
        uint256 lpMinted = curvePool.add_liquidity(amounts, minMint);
        if (lpMinted == 0) revert SlippageExceeded();

        /* Stake LP into Beefy */
        uint256 preShares = beefy.balanceOf(address(this));
        IERC20(beefy.want()).approve(address(beefy), lpMinted);
        beefy.depositAll();
        uint256 sharesMinted = beefy.balanceOf(address(this)) - preShares;

        /* Bookkeeping */
        uint256 ppsNow = beefy.getPricePerFullShare();
        principalShares += sharesMinted;
        depositValue = (sharesMinted * ppsNow) / 1e18;
        principalValue += depositValue;

        emit Deposited(msg.sender, msg.value, sharesMinted);
    }

    /*//////////////////////////////////////////////////////////////
                                 CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldVault
    function claimYield() external override nonReentrant onlyRole(YIELDMANAGER_ROLE) {
        bool flowActive = IYieldManager(msg.sender).yieldFlowActive();
        uint256 ppsNow = beefy.getPricePerFullShare();
        uint256 currentVaultValue = (principalShares * ppsNow) / 1e18;

        if (!flowActive && currentVaultValue <= principalValue) {
            emit YieldClaimed(0, 0);
            return;
        }

        uint256 yieldShares = ((currentVaultValue - principalValue) * 1e18) / ppsNow;
        if (yieldShares == 0) revert NothingToClaim();

        /* Beefy withdraw yield → LP */
        uint256 lpBefore = IERC20(beefy.want()).balanceOf(address(this));
        beefy.withdraw(yieldShares);
        uint256 lpOut = IERC20(beefy.want()).balanceOf(address(this)) - lpBefore;

        /* LP → USDC */
        uint256 expectedUsdc = curvePool.calc_withdraw_one_coin(lpOut, 1);
        uint256 minUsdc = (expectedUsdc * (10_000 - slippageBps)) / 10_000;
        IERC20(beefy.want()).approve(address(curvePool), lpOut);
        uint256 usdcOut = curvePool.remove_liquidity_one_coin(lpOut, 1, minUsdc);

        /* USDC → ETH */
        uint256 quotedEth = _quoteUsdcToEth(usdcOut);
        uint256 ethMin = (quotedEth * (10_000 - slippageBps)) / 10_000;
        uint256 wethOut = _swapExactInput(USDC, WETH, usdcOut, ethMin);
        IWETH(WETH).withdraw(wethOut);

        /* Update principal BEFORE transfer */
        principalShares -= yieldShares;
        principalValue = (principalShares * ppsNow) / 1e18;

        Address.sendValue(payable(msg.sender), wethOut);
        emit YieldClaimed(yieldShares, wethOut);
    }

    /*//////////////////////////////////////////////////////////////
                        PRINCIPAL RETRIEVAL
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldVault
    function retrievePrincipal(uint256 depositValue)
    external
    override
    nonReentrant
    onlyRole(YIELDMANAGER_ROLE)
    {
        if (depositValue == 0) revert CannotRetrieveZero();

        uint256 ppsNow = beefy.getPricePerFullShare();

        /* Translate desired value → shares (rounded up) */
        uint256 sharesToWithdraw = (depositValue * 1e18) / ppsNow;
        if (sharesToWithdraw == 0) sharesToWithdraw = 1;
        if (sharesToWithdraw > principalShares) {
            sharesToWithdraw = principalShares;
            depositValue = (sharesToWithdraw * ppsNow) / 1e18;
        }

        /* Pre-bookkeeping */
        uint256 pvSlice = (principalValue * sharesToWithdraw) / principalShares;
        principalShares -= sharesToWithdraw;
        principalValue -= pvSlice;

        /* Beefy withdraw → LP */
        uint256 lpBefore = IERC20(beefy.want()).balanceOf(address(this));
        beefy.withdraw(sharesToWithdraw);
        uint256 lpOut = IERC20(beefy.want()).balanceOf(address(this)) - lpBefore;

        /* LP → USDC */
        uint256 minUsdc = (curvePool.calc_withdraw_one_coin(lpOut, 1) * (10_000 - slippageBps)) / 10_000;
        IERC20(beefy.want()).approve(address(curvePool), lpOut);
        uint256 usdcOut = curvePool.remove_liquidity_one_coin(lpOut, 1, minUsdc);

        /* USDC → ETH */
        uint256 ethQuoted = _quoteUsdcToEth(usdcOut);
        uint256 ethMin = (ethQuoted * (10_000 - slippageBps)) / 10_000;
        uint256 wethOut = _swapExactInput(USDC, WETH, usdcOut, ethMin);
        IWETH(WETH).withdraw(wethOut);

        /* Transfer */
        Address.sendValue(payable(msg.sender), wethOut);
        emit PrincipalRetrieved(sharesToWithdraw, wethOut);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN CONFIG SETTER
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEUSDUSDCBeefyYieldVault
    function setSlippageBps(uint16 bps) external override onlyRole(ADMIN_ROLE) {
        require(bps <= 1_000, "too high"); // hard cap 10 %
        slippageBps = bps;
        emit SlippageSet(bps);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL SWAP & QUOTE HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Executes an exact-input swap on UniV3.
     * @param tokenIn Token to sell.
     * @param tokenOut Token to buy.
     * @param amountIn Exact input amount.
     * @param amountOutMin Minimum acceptable output.
     * @return amountOut Tokens received.
     */
    function _swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: UNIV3_FEE_TIER,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(p);
    }

    /* ---------- UniV3 quoter wrappers ---------- */

    function _quoteEthToUsdc(uint256 ethIn) internal returns (uint256) {
        return quoter.quoteExactInputSingle(WETH, USDC, UNIV3_FEE_TIER, ethIn, 0);
    }

    function _quoteUsdcToEth(uint256 usdcIn) internal returns (uint256) {
        return quoter.quoteExactInputSingle(USDC, WETH, UNIV3_FEE_TIER, usdcIn, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow this contract to receive ETH (WETH unwraps).
     */
    receive() external payable {}
}
