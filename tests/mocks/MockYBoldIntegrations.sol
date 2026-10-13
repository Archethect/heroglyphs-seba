// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";

contract MockToken is ERC20 {
    uint8 private immutable tokenDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function burn(address owner, uint256 amount) external {
        _burn(owner, amount);
    }
}

contract MockWeth is MockToken {
    constructor() MockToken("Wrapped Ether", "WETH", 18) { }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "ETH_TRANSFER");
    }
}

contract MockAggregator {
    uint8 public immutable decimals;
    uint80 public roundId = 1;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public answeredInRound = 1;

    constructor(uint8 decimals_, int256 answer_) {
        decimals = decimals_;
        answer = answer_;
        updatedAt = block.timestamp;
    }

    function setRound(uint80 roundId_, int256 answer_, uint256 updatedAt_, uint80 answeredInRound_) external {
        roundId = roundId_;
        answer = answer_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}

contract MockSwapRouter is ISwapRouter {
    using SafeERC20 for IERC20;

    address public immutable weth;
    address public immutable usdc;
    uint16 public outputBps = 10_000;
    uint256 public lastMinimum;
    bool public shouldRevert;

    constructor(address weth_, address usdc_) {
        weth = weth_;
        usdc = usdc_;
    }

    function setOutputBps(uint16 bps) external {
        outputBps = bps;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        require(!shouldRevert, "ROUTER_REVERT");
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        if (params.tokenIn == weth && params.tokenOut == usdc) {
            amountOut = Math.mulDiv(params.amountIn, 2000e6 * uint256(outputBps), 1e18 * 10_000);
        } else {
            amountOut = Math.mulDiv(params.amountIn, 1e18 * uint256(outputBps), 2000e6 * 10_000);
        }
        lastMinimum = params.amountOutMinimum;
        require(amountOut >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");
        IERC20(params.tokenOut).safeTransfer(params.recipient, amountOut);
    }
}

contract MockCurveStableSwapNG {
    using SafeERC20 for IERC20;

    address[2] private poolCoins;
    uint256 public oraclePrice = 1e18;
    uint16 public outputBps = 10_000;
    uint256 public lastMinimum;
    bool public shouldRevert;
    bool public returnZero;

    constructor(address bold, address usdc) {
        poolCoins[0] = bold;
        poolCoins[1] = usdc;
    }

    function coins(uint256 index) external view returns (address) {
        return poolCoins[index];
    }

    function setOraclePrice(uint256 price) external {
        oraclePrice = price;
    }

    function setOutputBps(uint16 bps) external {
        outputBps = bps;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function setReturnZero(bool value) external {
        returnZero = value;
    }

    function price_oracle(uint256) external view returns (uint256) {
        return oraclePrice;
    }

    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy, address receiver) external returns (uint256 dy) {
        require(!shouldRevert, "CURVE_REVERT");
        require((i == 0 && j == 1) || (i == 1 && j == 0), "INDICES");
        address tokenIn = i == 0 ? poolCoins[0] : poolCoins[1];
        address tokenOut = j == 0 ? poolCoins[0] : poolCoins[1];
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), dx);
        if (returnZero) return 0;
        if (i == 0 && j == 1) {
            dy = Math.mulDiv(dx, 1e6 * uint256(outputBps), 1e18 * 10_000);
        } else {
            dy = Math.mulDiv(dx, 1e18 * uint256(outputBps), 1e6 * 10_000);
        }
        lastMinimum = minDy;
        require(dy >= minDy, "CURVE_SLIPPAGE");
        IERC20(tokenOut).safeTransfer(receiver, dy);
    }
}

contract MockYearnVault is ERC4626 {
    using SafeERC20 for IERC20;

    uint256 public redeemLimit = type(uint256).max;
    uint256 public depositLimit = type(uint256).max;
    uint256 public lastMaxLoss;
    bool public isShutdown;
    bool public depositReturnsZero;
    bool public convertToSharesReturnsZero;
    bool public previewWithdrawReturnsZero;
    bool public customRedeemEnabled;
    uint256 public customRedeemAssets;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC4626(asset_) { }

    function setRedeemLimit(uint256 limit) external {
        redeemLimit = limit;
    }

    function setDepositLimit(uint256 limit) external {
        depositLimit = limit;
    }

    function setShutdown(bool value) external {
        isShutdown = value;
    }

    function setDepositReturnsZero(bool value) external {
        depositReturnsZero = value;
    }

    function setConvertToSharesReturnsZero(bool value) external {
        convertToSharesReturnsZero = value;
    }

    function setPreviewWithdrawReturnsZero(bool value) external {
        previewWithdrawReturnsZero = value;
    }

    function setCustomRedeem(bool enabled, uint256 assets) external {
        customRedeemEnabled = enabled;
        customRedeemAssets = assets;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        if (depositReturnsZero) return 0;
        return super.deposit(assets, receiver);
    }

    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        if (convertToSharesReturnsZero) return 0;
        return super.convertToShares(assets);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        if (previewWithdrawReturnsZero) return 0;
        return super.previewWithdraw(assets);
    }

    function maxDeposit(address) public view override returns (uint256) {
        return isShutdown ? 0 : depositLimit;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return Math.min(super.maxRedeem(owner), redeemLimit);
    }

    function maxRedeem(address owner, uint256) external view returns (uint256) {
        return maxRedeem(owner);
    }

    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss)
        external
        returns (uint256 assets)
    {
        lastMaxLoss = maxLoss;
        if (customRedeemEnabled) {
            _burn(owner, shares);
            IERC20(asset()).safeTransfer(receiver, customRedeemAssets);
            return customRedeemAssets;
        }
        return super.redeem(shares, receiver, owner);
    }
}

contract MockYBoldYieldManager {
    bool public yieldFlowActive = true;

    receive() external payable { }

    function setYieldFlowActive(bool active) external {
        yieldFlowActive = active;
    }

    function deposit(address vault) external payable returns (uint256 value) {
        (bool success, bytes memory data) = vault.call{ value: msg.value }(abi.encodeWithSignature("deposit()"));
        if (!success) _bubble(data);
        return abi.decode(data, (uint256));
    }

    function claim(address vault) external {
        (bool success, bytes memory data) = vault.call(abi.encodeWithSignature("claimYield()"));
        if (!success) _bubble(data);
    }

    function retrieve(address vault, uint256 value) external {
        (bool success, bytes memory data) = vault.call(abi.encodeWithSignature("retrievePrincipal(uint256)", value));
        if (!success) _bubble(data);
    }

    function _bubble(bytes memory data) private pure {
        assembly ("memory-safe") {
            revert(add(data, 32), mload(data))
        }
    }
}
