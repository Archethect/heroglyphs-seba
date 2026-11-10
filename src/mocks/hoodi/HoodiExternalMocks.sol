// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
import { MockBold } from "src/mocks/MockBold.sol";
import { MockSBold } from "src/mocks/MockSBold.sol";

/// @title Hoodi-only mock boundary
/// @notice None of the inheriting contracts can be deployed on mainnet or another chain.
abstract contract HoodiOnlyMock {
    /// @notice Test dependency deployed on a chain other than Hoodi.
    error HoodiOnly();

    constructor() {
        if (block.chainid != 560_048) revert HoodiOnly();
    }
}

/// @title Hoodi sBOLD adapter mock
/// @notice Retains the V1 mock's 1:1 deposit/withdraw and adds the V2 canonical preview API.
contract HoodiSBoldMock is MockSBold, HoodiOnlyMock {
    constructor(MockBold underlying) MockSBold(underlying) { }

    /// @notice Return 1:1 shares for V2's independent pre-deposit minimum check.
    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }
}

/// @title Hoodi fixed-price Chainlink feed mock
/// @notice Returns a fresh eight-decimal USD answer; not a real oracle.
contract HoodiPriceFeedMock is HoodiOnlyMock {
    /// @notice Fixed synthetic price with eight decimals.
    int256 public immutable answer;
    /// @notice Test-only manually selected report time.
    uint256 public updatedAt;

    constructor(int256 price) {
        answer = price;
        updatedAt = block.timestamp;
    }

    /// @notice Set a synthetic report timestamp to exercise stale-feed failure paths.
    function setUpdatedAt(uint256 timestamp) external {
        updatedAt = timestamp;
    }

    /// @notice Return eight decimals, matching the mainnet feed integration.
    function decimals() external pure returns (uint8) {
        return 8;
    }

    /// @notice Return a synthetic round; no external price discovery occurs.
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

/// @title Hoodi fixed-price Uniswap quoter/router mock
/// @notice Simulates 1 ETH = 2000 USDC solely to run unchanged legacy adapter logic.
contract HoodiUniswapMock is HoodiOnlyMock {
    using SafeERC20 for IERC20;

    address public immutable weth;
    address public immutable usdc;

    constructor(address wrapper, address dollar) {
        weth = wrapper;
        usdc = dollar;
    }

    /// @notice Quote a 0.05% fee-tier pair at a fixed synthetic price.
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    )
        external
        view
        returns (uint256)
    {
        require(fee == 500 && sqrtPriceLimitX96 == 0, "mock parameters");
        return _quote(tokenIn, tokenOut, amountIn);
    }

    /// @notice Transfer exact input and deliver synthetic output using held WETH or mintable mock USDC.
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata p) external returns (uint256 output) {
        require(p.deadline >= block.timestamp && p.fee == 500 && p.sqrtPriceLimitX96 == 0, "mock parameters");
        output = _quote(p.tokenIn, p.tokenOut, p.amountIn);
        require(output >= p.amountOutMinimum, "mock minimum");
        IERC20(p.tokenIn).safeTransferFrom(msg.sender, address(this), p.amountIn);
        if (p.tokenOut == usdc) {
            IHoodiMintable(usdc).mint(output, p.recipient);
        } else {
            IERC20(weth).safeTransfer(p.recipient, output);
        }
    }

    function _quote(address tokenIn, address tokenOut, uint256 amountIn) private view returns (uint256) {
        if (tokenIn == weth && tokenOut == usdc) return (amountIn * 2000e6) / 1e18;
        if (tokenIn == usdc && tokenOut == weth) return (amountIn * 1e18) / 2000e6;
        revert("mock pair");
    }
}

/// @title Hoodi synthetic Curve USDe/USDC pool and LP token
/// @notice Holds actual mock USDC and mints 18-decimal LP units one-for-one by value.
contract HoodiCurveMock is ERC20, HoodiOnlyMock {
    using SafeERC20 for IERC20;

    address public immutable usdc;

    constructor(address dollar) ERC20("Hoodi test LP", "hLP") {
        usdc = dollar;
    }

    /// @notice Take USDC-only liquidity and mint test LP tokens.
    function add_liquidity(uint256[] calldata amounts, uint256 minimum) external returns (uint256 minted) {
        require(amounts.length == 2 && amounts[0] == 0, "mock amounts");
        minted = amounts[1] * 1e12;
        require(minted >= minimum, "mock minimum");
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amounts[1]);
        _mint(msg.sender, minted);
    }

    /// @notice Burn test LP tokens and return the held mock USDC.
    function remove_liquidity_one_coin(uint256 lpAmount, int128 index, uint256 minimum) external returns (uint256 out) {
        require(index == 1, "mock coin");
        out = lpAmount / 1e12;
        require(out >= minimum, "mock minimum");
        _burn(msg.sender, lpAmount);
        IERC20(usdc).safeTransfer(msg.sender, out);
    }

    /// @notice Preview an LP mint or burn using the synthetic 1:1 value scale.
    function calc_token_amount(uint256[] calldata amounts, bool) external pure returns (uint256) {
        require(amounts.length == 2 && amounts[0] == 0, "mock amounts");
        return amounts[1] * 1e12;
    }

    /// @notice Preview a USDC-only withdrawal.
    function calc_withdraw_one_coin(uint256 lpAmount, int128 index) external pure returns (uint256) {
        require(index == 1, "mock coin");
        return lpAmount / 1e12;
    }

    /// @notice Return a fixed LP virtual price of one.
    function get_virtual_price() external pure returns (uint256) {
        return 1e18;
    }
}

/// @title Hoodi synthetic Beefy share vault
/// @notice Holds Curve mock LP and has a fixed share price; cannot model Beefy yield or liquidity.
contract HoodiBeefyMock is ERC20, HoodiOnlyMock {
    using SafeERC20 for IERC20;

    address public immutable want;

    constructor(address lp) ERC20("Hoodi test Beefy share", "hmoo") {
        want = lp;
    }

    /// @notice Stake all LP tokens owned by the caller and mint equal test shares.
    function depositAll() external {
        uint256 amount = IERC20(want).balanceOf(msg.sender);
        IERC20(want).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    /// @notice Burn shares and release the same number of held LP tokens.
    function withdraw(uint256 shares) external {
        _burn(msg.sender, shares);
        IERC20(want).safeTransfer(msg.sender, shares);
    }

    /// @notice Fixed one-to-one test share price.
    function getPricePerFullShare() external pure returns (uint256) {
        return 1e18;
    }
}

/// @title Hoodi synthetic Yearn tokenized strategy
/// @notice Direct 1:1 deposits/redemptions; cannot model locked profit or live liquidity.
contract HoodiYearnMock is ERC20, HoodiOnlyMock {
    using SafeERC20 for IERC20;

    address public immutable asset;

    constructor(address underlying, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        asset = underlying;
    }

    /// @notice Match the exact supported mainnet Yearn API version for V2 identity checks.
    function apiVersion() external pure returns (string memory) {
        return "3.0.4";
    }

    /// @notice Return held underlying amount as recognized assets.
    function totalAssets() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /// @notice Preview equal shares for a deposit.
    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /// @notice Value shares one-for-one in underlying units.
    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /// @notice Return all held shares as currently redeemable.
    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    /// @notice Transfer underlying and mint equal test shares.
    function deposit(uint256 assets, address receiver) external returns (uint256) {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, assets);
        return assets;
    }

    /// @notice Burn owned shares and return underlying at zero reported loss.
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss) external returns (uint256) {
        require(maxLoss == 0 && owner == msg.sender, "mock redemption");
        _burn(owner, shares);
        IERC20(asset).safeTransfer(receiver, shares);
        return shares;
    }
}

/// @title Hoodi mock CoW allowance spender
/// @notice Only its paired settlement mock can consume an escrow's exact allowance.
contract HoodiCowRelayerMock is HoodiOnlyMock {
    using SafeERC20 for IERC20;

    address public immutable settlement;

    constructor(address coordinator) {
        settlement = coordinator;
    }

    /// @notice Consume an escrow's sell token with the real ERC20 allowance path.
    function spend(address token, address escrow, uint256 amount) external {
        require(msg.sender == settlement, "mock settlement only");
        IERC20(token).safeTransferFrom(escrow, settlement, amount);
    }
}

/// @title Hoodi-only CoW settlement mock
/// @notice Exercises real Seba intent escrow accounting with synthetic fills; no CoW solver or API is involved.
contract HoodiCowSettlementMock is HoodiOnlyMock {
    address public immutable bold;
    address public immutable solver;
    HoodiCowRelayerMock public immutable relayer;
    bytes32 public immutable domainSeparator;
    mapping(address => mapping(bytes32 => bool)) public preSigned;

    event MockOrderSettled(
        bytes uid, address indexed escrow, address indexed sellToken, uint256 sellAmount, uint256 boldOut
    );

    constructor(address output, address authorizedSolver) {
        bold = output;
        solver = authorizedSolver;
        relayer = new HoodiCowRelayerMock(address(this));
        domainSeparator = keccak256(abi.encode("Hoodi synthetic CoW", block.chainid, address(this)));
    }

    /// @notice Expose the mock relayer identity used by the production intent module.
    function vaultRelayer() external view returns (address) {
        return address(relayer);
    }

    /// @notice Record the caller escrow's canonical presignature flag.
    function setPreSignature(bytes calldata uid, bool signed) external {
        preSigned[msg.sender][keccak256(uid)] = signed;
    }

    /// @notice Simulate one exact unexpired fill; BOLD is synthetic and not market-purchased.
    function settleMockOrder(address escrowAddress, uint256 boldOut) external {
        require(msg.sender == solver, "mock solver only");
        SebaCowOrderEscrow escrow = SebaCowOrderEscrow(escrowAddress);
        ISebaCowIntentModule.Data memory order = escrow.orderData();
        bytes memory uid = escrow.orderUid();
        require(preSigned[escrowAddress][keccak256(uid)] && !escrow.closed(), "mock order inactive");
        require(block.timestamp <= order.validTo && !order.partiallyFillable, "mock order expired");
        require(order.buyToken == bold && order.receiver == escrowAddress && boldOut >= order.buyAmount, "mock output");
        relayer.spend(order.sellToken, escrowAddress, order.sellAmount);
        IHoodiBoldMintable(bold).mint(escrowAddress, boldOut);
        emit MockOrderSettled(uid, escrowAddress, order.sellToken, order.sellAmount, boldOut);
    }
}

/// @title Hoodi-only mock Beefy strategy harvester
/// @notice Legacy backend health/harvest calls only; independent from Seba's Beefy adapter.
contract HoodiBeefyHarvesterMock is HoodiOnlyMock {
    bool public paused;
    uint256 public harvestCount;

    event MockHarvested(uint256 count);

    /// @notice Toggle synthetic pause for backend failure-path tests.
    function setPaused(bool value) external {
        paused = value;
    }

    /// @notice Count a synthetic harvest and emit its observation event.
    function harvest() external {
        require(!paused, "mock paused");
        emit MockHarvested(++harvestCount);
    }
}

/// @title Hoodi-only mock of legacy CoW ETH flow
/// @notice Supports an exact synthetic fill or full refund so V1's unchanged router can be rehearsed.
contract HoodiEthFlowMock is HoodiOnlyMock {
    address public immutable solver;
    uint256 public nextNonce;
    mapping(address => bytes32) public activeUid;
    mapping(bytes32 => IEthFlow.Data) private _orders;

    event MockEthFlowSettled(bytes32 indexed uid, uint256 ethIn, uint256 boldOut);

    constructor(address authorizedSolver) {
        solver = authorizedSolver;
    }

    /// @notice Accept a legacy ETH intent and return a deterministic test UID.
    function createOrder(IEthFlow.Data calldata order) external payable returns (bytes32 uid) {
        require(
            msg.value == order.sellAmount && order.sellAmount != 0 && activeUid[msg.sender] == bytes32(0), "mock order"
        );
        uid = keccak256(abi.encode(block.chainid, address(this), msg.sender, nextNonce++, order));
        _orders[uid] = order;
        activeUid[msg.sender] = uid;
    }

    /// @notice Cancel and return the exact original ETH amount to its router.
    function invalidateOrder(IEthFlow.Data calldata order) external {
        bytes32 uid = activeUid[msg.sender];
        require(uid != bytes32(0) && keccak256(abi.encode(_orders[uid])) == keccak256(abi.encode(order)), "mock order");
        delete activeUid[msg.sender];
        delete _orders[uid];
        (bool ok,) = msg.sender.call{ value: order.sellAmount }("");
        require(ok, "mock refund");
    }

    /// @notice Consume ETH and mint synthetic BOLD at or above the original minimum.
    function settleMockOrder(address router, uint256 boldOut) external {
        require(msg.sender == solver, "mock solver only");
        bytes32 uid = activeUid[router];
        IEthFlow.Data memory order = _orders[uid];
        require(uid != bytes32(0) && block.timestamp <= order.validTo && boldOut >= order.buyAmount, "mock fill");
        delete activeUid[router];
        delete _orders[uid];
        IHoodiBoldMintable(address(order.buyToken)).mint(order.receiver, boldOut);
        (bool ok,) = solver.call{ value: order.sellAmount }("");
        require(ok, "mock ETH transfer");
        emit MockEthFlowSettled(uid, order.sellAmount, boldOut);
    }
}

interface IHoodiMintable {
    function mint(uint256 amount, address receiver) external;
}

interface IHoodiBoldMintable {
    function mint(address receiver, uint256 amount) external;
}
