// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SebaV2Executor } from "src/v2/SebaV2Executor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { IExecutorRocketStorage, IExecutorYearn } from "src/vendor/v2/IExecutorProtocols.sol";
import { ExecutorActor } from "../ExecutorMocks.sol";

/// @notice Component integration only, NOT full manager/vault/migration E2E.
/// @dev Real deployed protocol calls; local manager harness/impersonation and synthetic ETH funding are explicit.
contract ExecutorRoutesForkTest is Test {
    uint256 internal constant PIN = 26_255_470;
    address internal constant SAFE = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address internal constant YSY = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant REGISTRY = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    SebaV2Executor internal executor;
    address internal managerHarness;
    uint256[6] internal initialDust;
    uint256 internal initialEth;

    function setUp() public {
        uint256 selectedPin = vm.envOr("SEBA_V2_EXECUTOR_FORK_BLOCK", PIN);
        if (vm.envOr("SEBA_V2_FRESH_FORK", false)) vm.createSelectFork(vm.envString("MAINNET_RPC"));
        else vm.createSelectFork(vm.envString("MAINNET_RPC"), selectedPin);
        emit log_named_uint("Executor fork snapshot block", block.number);
        emit log_named_bytes32("Executor fork parent hash", blockhash(block.number - 1));
        managerHarness = address(new ExecutorActor());
        executor = new SebaV2Executor(
            IV2Executor.Config({
                manager: managerHarness,
                treasury: SAFE,
                reth: RETH,
                weth: WETH,
                usdc: USDC,
                bold: BOLD,
                yBold: YBOLD,
                ysyBold: YSY,
                swapRouter: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
                curvePool: 0xEFc6516323FbD28e80B85A497B65A86243a54B3E,
                ethUsdFeed: 0xc0053f3FBcCD593758258334Dfce24C2A9A673aD,
                usdcUsdFeed: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
                rocketStorage: REGISTRY
            })
        );
        // TEST FIXTURE ONLY: these values are not an approved production risk-parameter pack.
        IV2Executor.Limits memory l = IV2Executor.Limits({
            maxEth: 200 ether,
            maxReth: 100 ether,
            maxYsy: 300_000 ether,
            maxMintFeeWad: 1e15,
            ethMaxAge: 3600,
            usdcMaxAge: 82800,
            reportMaxAge: 2 days,
            reportMaxBlockLag: 20_000,
            maxDeadline: 15 minutes,
            slippageBps: 50,
            pegBps: 100,
            wethUsdcFee: 500,
            rethWethFee: 100,
            depositPool: _registry("rocketDepositPool"),
            networkBalances: _registry("rocketNetworkBalances"),
            depositSettings: _registry("rocketDAOProtocolSettingsDeposit")
        });
        vm.startPrank(SAFE);
        executor.configureLimits(l);
        executor.setEnabled(true);
        vm.stopPrank();
        vm.deal(managerHarness, 200 ether); // Synthetic input, not a treasury liquidation/recovery outcome.
        vm.startPrank(managerHarness);
        IERC20(RETH).approve(address(executor), type(uint256).max);
        IERC20(YSY).approve(address(executor), type(uint256).max);
        vm.stopPrank();
        address[6] memory tokens = [RETH, WETH, USDC, BOLD, YBOLD, YSY];
        for (uint256 i; i < tokens.length; ++i) initialDust[i] = IERC20(tokens[i]).balanceOf(address(executor));
        initialEth = address(executor).balance;
    }

    function _registry(string memory name) internal view returns (address) {
        return IExecutorRocketStorage(REGISTRY).getAddress(keccak256(abi.encodePacked("contract.address", name)));
    }
    function _nativeInput(address token, uint256 amount) internal {
        vm.prank(SAFE);
        IERC20(token).transfer(managerHarness, amount);
    }
    function _assertEmpty() internal view {
        address[6] memory tokens = [RETH, WETH, USDC, BOLD, YBOLD, YSY];
        for (uint256 i; i < tokens.length; ++i)
            assertEq(IERC20(tokens[i]).balanceOf(address(executor)), initialDust[i], vm.toString(tokens[i]));
        assertEq(address(executor).balance, initialEth);
    }

    function test_realRocketPoolMintAndForwardInSameBlock() public {
        vm.prank(managerHarness);
        uint256 out = executor.investReth{ value: 1 ether }(1, block.timestamp + 60);
        assertGt(out, 0);
        assertEq(IERC20(RETH).balanceOf(managerHarness), out);
        _assertEmpty();
    }
    function test_researchOnlyPilotLimitsAllFiveRealRoutes() public {
        // Unapproved candidate, not a production default or maximum-safe-capacity claim.
        IV2Executor.Limits memory pilot = executor.limits();
        pilot.maxEth = 1 ether;
        pilot.maxReth = 1 ether;
        pilot.maxYsy = 1000 ether;
        pilot.usdcMaxAge = 25 hours;
        pilot.maxDeadline = 5 minutes;
        vm.startPrank(SAFE);
        executor.setEnabled(false);
        executor.configureLimits(pilot);
        executor.setEnabled(true);
        vm.stopPrank();
        _nativeInput(RETH, 1 ether);
        _nativeInput(YSY, 1000 ether);
        vm.startPrank(managerHarness);
        uint256 r = executor.investReth{ value: 1 ether }(1, block.timestamp + 60);
        uint256 b = executor.convertEthToBold{ value: 1 ether }(1, block.timestamp + 60);
        uint256 y = executor.investYsyBold{ value: 1 ether }(1, block.timestamp + 60);
        uint256 rb = executor.convertRethToBold(1 ether, 1, block.timestamp + 60);
        uint256 yb = executor.convertYsyToBold(1000 ether, 1, block.timestamp + 60);
        vm.stopPrank();
        assertGt(r, 0);
        assertGt(b, 0);
        assertGt(y, 0);
        assertGt(rb, 0);
        assertGt(yb, 0);
        _assertEmpty();
        emit log_named_uint("Pilot 1 ETH / rETH atoms", r);
        emit log_named_uint("Pilot 1 ETH / BOLD atoms", b);
        emit log_named_uint("Pilot 1 ETH / ysyBOLD atoms", y);
        emit log_named_uint("Pilot 1 rETH / BOLD atoms", rb);
        emit log_named_uint("Pilot 1000 ysyBOLD / BOLD atoms", yb);
    }
    function test_realEthToBoldAtOneAndHundredEth() public {
        vm.startPrank(managerHarness);
        uint256 first = executor.convertEthToBold{ value: 1 ether }(1, block.timestamp + 60);
        uint256 large = executor.convertEthToBold{ value: 100 ether }(1, block.timestamp + 60);
        vm.stopPrank();
        assertGt(first, 0);
        assertGt(large, first);
        _assertEmpty();
        emit log_named_uint("1 ETH input / actual BOLD atoms", first);
        emit log_named_uint("100 ETH input / actual BOLD atoms", large);
    }
    function test_realEthToYsyBoldAtOneAndSeventyEth() public {
        vm.startPrank(managerHarness);
        uint256 first = executor.investYsyBold{ value: 1 ether }(1, block.timestamp + 60);
        uint256 large = executor.investYsyBold{ value: 70 ether }(1, block.timestamp + 60);
        vm.stopPrank();
        assertGt(first, 0);
        assertGt(large, first);
        _assertEmpty();
        emit log_named_uint("1 ETH input / actual ysyBOLD atoms", first);
        emit log_named_uint("70 ETH input / actual ysyBOLD atoms", large);
    }
    function test_realRethDonationConversionAtTreasurySize() public {
        uint256 amount = IERC20(RETH).balanceOf(SAFE);
        _nativeInput(RETH, amount);
        vm.prank(managerHarness);
        uint256 out = executor.convertRethToBold(amount, 1, block.timestamp + 60);
        assertGt(out, 0);
        assertEq(IERC20(RETH).balanceOf(managerHarness), 0);
        _assertEmpty();
        emit log_named_uint("Treasury rETH atoms input", amount);
        emit log_named_uint("Actual BOLD atoms output", out);
    }
    function test_realYsyDonationRedemptionAtTreasurySizeWithZeroLoss() public {
        uint256 amount = IERC20(YSY).balanceOf(SAFE);
        _nativeInput(YSY, amount);
        uint256 yBoldExpected = IExecutorYearn(YSY).convertToAssets(amount);
        uint256 boldExpected = IExecutorYearn(YBOLD).convertToAssets(yBoldExpected);
        vm.prank(managerHarness);
        uint256 out = executor.convertYsyToBold(amount, boldExpected, block.timestamp + 60);
        assertEq(out, boldExpected);
        assertEq(IERC20(YSY).balanceOf(managerHarness), 0);
        _assertEmpty();
        emit log_named_uint("Treasury ysyBOLD atoms input", amount);
        emit log_named_uint("Actual BOLD atoms output", out);
    }
    function test_faultInjectedStaleUsdDoesNotBlockDirectYsyRoute() public {
        // FAULT INJECTION, not an observation that mainnet feeds were stale.
        vm.mockCall(
            0xc0053f3FBcCD593758258334Dfce24C2A9A673aD,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(uint80(1), int256(1), uint256(1), uint256(1), uint80(1))
        );
        _nativeInput(YSY, 1000 ether);
        vm.prank(managerHarness);
        assertGt(executor.convertYsyToBold(1000 ether, 1, block.timestamp + 60), 0);
        vm.prank(managerHarness);
        vm.expectRevert(IV2Executor.StaleOracle.selector);
        executor.convertEthToBold{ value: 1 ether }(1, block.timestamp + 60);
        _assertEmpty();
    }

    function test_faultInjectedUnusableCurveDoesNotBlockDirectYsyRoute() public {
        vm.mockCallRevert(
            executor.configuration().curvePool,
            abi.encodeWithSignature("exchange(int128,int128,uint256,uint256)"),
            abi.encodeWithSignature("Error(string)", "test-only unavailable Curve")
        );
        _nativeInput(YSY, 1000 ether);
        vm.prank(managerHarness);
        assertGt(executor.convertYsyToBold(1000 ether, 1, block.timestamp + 60), 0);
        vm.prank(managerHarness);
        vm.expectRevert(bytes("test-only unavailable Curve"));
        executor.convertEthToBold{ value: 1 ether }(1, block.timestamp + 60);
        _assertEmpty();
    }

    function test_faultInjectedUnavailableYearnDoesNotBlockRocketMint() public {
        vm.mockCallRevert(
            YSY,
            abi.encodeWithSignature("redeem(uint256,address,address,uint256)"),
            abi.encodeWithSignature("Error(string)", "test-only unavailable Yearn")
        );
        _nativeInput(YSY, 1000 ether);
        vm.prank(managerHarness);
        vm.expectRevert(bytes("test-only unavailable Yearn"));
        executor.convertYsyToBold(1000 ether, 1, block.timestamp + 60);
        vm.prank(managerHarness);
        assertGt(executor.investReth{ value: 1 ether }(1, block.timestamp + 60), 0);
        _assertEmpty();
    }
}
