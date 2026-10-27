// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";

contract ExecutorActor {}

contract ExecutorToken is ERC20 {
    uint8 public tokenDecimals;
    uint256 public pullFee;
    uint256 public sendFee;
    constructor(uint8 d) ERC20("Executor mock", "MOCK") {
        tokenDecimals = d;
    }
    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
    function setDecimals(uint8 d) external {
        tokenDecimals = d;
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function setFees(uint256 p, uint256 s) external {
        pullFee = p;
        sendFee = s;
    }
    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        if (sendFee != 0) _burn(to, Math.min(sendFee, amount));
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        if (pullFee != 0) _burn(to, Math.min(pullFee, amount));
        return true;
    }
}

contract ExecutorWeth is ExecutorToken {
    uint256 public mintBps = 10_000;
    constructor() ExecutorToken(18) {}
    function setMintBps(uint256 bps) external {
        mintBps = bps;
    }
    function deposit() external payable {
        _mint(msg.sender, (msg.value * mintBps) / 10_000);
    }
}

contract ExecutorReth is ExecutorToken {
    uint256 public rate = 1.2e18;
    constructor() ExecutorToken(18) {}
    function setRate(uint256 r) external {
        rate = r;
    }
    function getEthValue(uint256 q) external view returns (uint256) {
        return Math.mulDiv(q, rate, 1e18);
    }
    function getRethValue(uint256 b) external view returns (uint256) {
        return Math.mulDiv(b, 1e18, rate);
    }
}

contract ExecutorYearn is ExecutorToken {
    address public asset;
    uint256 public rate = 1e18;
    uint256 public spendBps = 10_000;
    uint256 public outputBps = 10_000;
    uint256 public reportDelta;
    uint256 public redeemLimit = type(uint256).max;
    uint256 public lastMaxLoss;
    constructor(address a) ExecutorToken(18) {
        asset = a;
    }
    function setAsset(address a) external {
        asset = a;
    }
    function setRate(uint256 r) external {
        rate = r;
    }
    function setBehavior(uint256 spend, uint256 out, uint256 report) external {
        spendBps = spend;
        outputBps = out;
        reportDelta = report;
    }
    function setRedeemLimit(uint256 n) external {
        redeemLimit = n;
    }
    function previewDeposit(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(amount, 1e18, rate);
    }
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return Math.mulDiv(shares, rate, 1e18);
    }
    function maxRedeem(address) external view returns (uint256) {
        return redeemLimit;
    }
    function deposit(uint256 amount, address to) external returns (uint256 out) {
        IERC20(asset).transferFrom(msg.sender, address(this), (amount * spendBps) / 10_000);
        out = (previewDeposit(amount) * outputBps) / 10_000;
        _mint(to, out);
        return out + reportDelta;
    }
    function redeem(uint256 shares, address to, address owner, uint256 maxLoss) external returns (uint256 out) {
        require(maxLoss == 0, "nonzero loss");
        lastMaxLoss = maxLoss;
        _burn(owner, (shares * spendBps) / 10_000);
        out = (convertToAssets(shares) * outputBps) / 10_000;
        ExecutorToken(asset).mint(to, out);
        return out + reportDelta;
    }
}

contract ExecutorFeed {
    uint8 public decimals = 8;
    uint80 public round = 1;
    int256 public answer;
    uint256 public started;
    uint256 public updated;
    uint80 public answered = 1;
    constructor(int256 a) {
        answer = a;
        started = block.timestamp;
        updated = block.timestamp;
    }
    function set(uint80 r, int256 a, uint256 s, uint256 u, uint80 ar, uint8 d) external {
        round = r;
        answer = a;
        started = s;
        updated = u;
        answered = ar;
        decimals = d;
    }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (round, answer, started, updated, answered);
    }
}

contract ExecutorRouter {
    mapping(address => mapping(address => uint256)) public rate;
    uint256 public spendBps = 10_000;
    uint256 public outputBps = 10_000;
    uint256 public reportDelta;
    uint256 public lastDeadline;
    address public callback;
    bytes public callbackData;
    function setRate(address i, address o, uint256 r) external {
        rate[i][o] = r;
    }
    function setBehavior(uint256 spend, uint256 out, uint256 report) external {
        spendBps = spend;
        outputBps = out;
        reportDelta = report;
    }
    function setCallback(address to, bytes calldata data) external {
        callback = to;
        callbackData = data;
    }
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata p) external returns (uint256 out) {
        lastDeadline = p.deadline;
        if (callback != address(0)) {
            (bool ok, bytes memory reason) = callback.call(callbackData);
            if (!ok)
                assembly {
                    revert(add(reason, 32), mload(reason))
                }
        }
        IERC20(p.tokenIn).transferFrom(msg.sender, address(this), (p.amountIn * spendBps) / 10_000);
        out = (Math.mulDiv(p.amountIn, rate[p.tokenIn][p.tokenOut], 1e18) * outputBps) / 10_000;
        ExecutorToken(p.tokenOut).mint(p.recipient, out);
        return out + reportDelta;
    }
}

contract ExecutorCurve {
    address public bold;
    address public usdc;
    uint256 public peg = 1e18;
    uint256 public spendBps = 10_000;
    uint256 public outputBps = 10_000;
    uint256 public reportDelta;
    constructor(address b, address u) {
        bold = b;
        usdc = u;
    }
    function setCoins(address b, address u) external {
        bold = b;
        usdc = u;
    }
    function setPeg(uint256 p) external {
        peg = p;
    }
    function coins(uint256 i) external view returns (address) {
        return i == 0 ? bold : usdc;
    }
    function price_oracle(uint256) external view returns (uint256) {
        return peg;
    }
    function setBehavior(uint256 spend, uint256 out, uint256 report) external {
        spendBps = spend;
        outputBps = out;
        reportDelta = report;
    }
    function exchange(int128 i, int128 j, uint256 amount, uint256) external returns (uint256 out) {
        require(i == 1 && j == 0, "wrong route");
        IERC20(usdc).transferFrom(msg.sender, address(this), (amount * spendBps) / 10_000);
        out = (amount * 1e12 * outputBps) / 10_000;
        ExecutorToken(bold).mint(msg.sender, out);
        return out + reportDelta;
    }
}

contract ExecutorRocketRegistry {
    mapping(bytes32 => address) public getAddress;
    function set(string calldata name, address value) external {
        getAddress[keccak256(abi.encodePacked("contract.address", name))] = value;
    }
}

contract ExecutorRocketBalances {
    uint256 public getBalancesTimestamp;
    uint256 public getBalancesBlock;
    constructor() {
        getBalancesTimestamp = block.timestamp;
        getBalancesBlock = block.number;
    }
    function set(uint256 t, uint256 b) external {
        getBalancesTimestamp = t;
        getBalancesBlock = b;
    }
}

contract ExecutorRocketSettings {
    uint256 public getDepositFee = 5e14;
    function set(uint256 n) external {
        getDepositFee = n;
    }
}

contract ExecutorRocketPool {
    ExecutorReth public reth;
    ExecutorRocketSettings public settings;
    uint256 public getMaximumDepositAmount = type(uint256).max;
    uint256 public outputBps = 10_000;
    constructor(ExecutorReth r, ExecutorRocketSettings s) {
        reth = r;
        settings = s;
    }
    function set(uint256 maximum, uint256 out) external {
        getMaximumDepositAmount = maximum;
        outputBps = out;
    }
    function deposit() external payable {
        uint256 net = msg.value - Math.mulDiv(msg.value, settings.getDepositFee(), 1e18);
        reth.mint(msg.sender, (reth.getRethValue(net) * outputBps) / 10_000);
    }
}
