// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { YBoldMigrationPreflight } from "script/YBoldMigrationPreflight.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IYearnVault } from "src/vendor/yearn/IYearnVault.sol";
import { ICurveStableSwapNG } from "src/vendor/curve/ICurveStableSwapNG.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IWETH } from "src/vendor/various/IWETH.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldConfigValidator } from "src/YBoldConfigValidator.sol";
import { YieldManager } from "src/YieldManager.sol";
import { YBoldYieldVaultV2Mock } from "tests/mocks/YBoldYieldVaultV2Mock.sol";

contract RejectingEthDepositor {
    function deposit(YieldManager manager) external payable {
        manager.depositFunds{ value: msg.value }();
    }

    function withdraw(YieldManager manager, uint256 id) external {
        manager.retrieveFunds(id);
    }

    receive() external payable {
        revert("REJECTS_ETH_INCLUDING_ZERO");
    }
}

/**
 * @notice Rehearses the current treasury-custody state without minting treasury capital or replaying the old unwind.
 * @dev Pranks prove authorized call mechanics, not the signers' operational availability. Future-oracle refreshes and
 *      external faults are explicitly injected; current treasury liquidation and redeposits use real fork assets.
 */
contract YBoldTreasuryRolloutForkTest is Test {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint256 private constant PIN = 26_248_207;
    address private constant TREASURY = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address private constant ADMIN = 0xf83b11b09EEc073ACE4481b2F4c8357e156714b3;
    address private constant MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address private constant OLD = 0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba;
    address private constant SECOND_USER = address(0xA11CE);
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address private constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant CURVE = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E;
    address private constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address private constant YSYBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address private constant ETH_FEED = 0xc0053f3FBcCD593758258334Dfce24C2A9A673aD;
    address private constant USDC_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    YieldManager private manager;
    YBoldYieldVault private adapter;
    uint256 private firstId;
    uint256 private secondId;
    uint256 private firstPrincipal;
    uint256 private secondPrincipal;
    uint256 private protocolPrincipal;
    uint32 private unlock;
    bool private preflightEnabled;

    /** @notice Only the serialized release-test fixture enables environment-mutating script checks. */
    function rehearseReleasePreflight() external returns (YBoldYieldVault deployed) {
        preflightEnabled = true;
        setUp();
        _rollout();
        return adapter;
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), PIN);
        manager = YieldManager(payable(MANAGER));
    }

    function test_CurrentTreasurySharesLiquidateAndRedepositThroughRealManager() external {
        uint256 ethRecovered = _rollout();
        console2.log("Treasury actual ETH recovered", ethRecovered);
        console2.log("New user principal", firstPrincipal + secondPrincipal);
        console2.log("New protocol principal", protocolPrincipal);
        console2.log("New ysyBOLD shares", adapter.principalShares());

        uint256 protocolBefore = MANAGER.balance;
        vm.prank(ADMIN);
        manager.retrievePrincipalFromYieldVault();
        assertGt(MANAGER.balance, protocolBefore);
        assertEq(manager.principalValue(), 0);

        // A 30-day warp models the existing user lock; refreshing the original prices is fault injection, not future pricing.
        vm.warp(unlock);
        _refreshOracle(ETH_FEED);
        _refreshOracle(USDC_FEED);
        uint256 firstBefore = TREASURY.balance;
        vm.prank(TREASURY);
        manager.retrieveFunds(firstId);
        assertGt(TREASURY.balance, firstBefore);
        uint256 secondBefore = SECOND_USER.balance;
        vm.prank(SECOND_USER);
        manager.retrieveFunds(secondId);
        assertGt(SECOND_USER.balance, secondBefore);
        _assertDeleted(firstId);
        _assertDeleted(secondId);
        assertEq(adapter.principalValue(), 0);
        assertEq(adapter.principalShares(), IERC20(YSYBOLD).balanceOf(address(adapter)));
        // Final healthy retrieval can preserve unharvested yield; it must never consume another ID's principal.
        assertEq(IERC20(USDC).allowance(address(adapter), ROUTER), 0);
        assertEq(IERC20(BOLD).allowance(address(adapter), CURVE), 0);
        uint256 remainingYieldShares = adapter.principalShares();
        assertGt(remainingYieldShares, 0, "expected unlocked live Yearn yield after30days");
        vm.mockCallRevert(YSYBOLD, abi.encodeWithSignature("maxRedeem(address,uint256)"), bytes("FAULT_YEARN"));
        vm.prank(TREASURY);
        adapter.initiateRecovery();
        assertEq(IERC20(YSYBOLD).balanceOf(TREASURY), remainingYieldShares);
        assertEq(adapter.recoveryAccounting().principalSnapshot, 0);
        assertEq(uint256(adapter.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.Settled));
    }

    function test_RealLiquidationFundsOneUniformFullProceedsSettlement() external {
        _recovery(10_000);
    }

    function test_RealLiquidationFundsPartialLossSettlementWithoutFavoringFirstClaim() external {
        _recovery(8_000);
    }

    function test_TotalLossSettlementClearsRealManagerIdsWithoutFakeEthFunding() external {
        _rollout();
        uint256 shares = adapter.principalShares();
        vm.prank(TREASURY);
        adapter.initiateRecovery();
        vm.prank(TREASURY);
        adapter.activateRecoverySettlement(0);
        assertEq(adapter.recoveryAccounting().payoutRateWad, 0);
        vm.warp(unlock);
        vm.prank(TREASURY);
        manager.retrieveFunds(firstId);
        vm.prank(SECOND_USER);
        manager.retrieveFunds(secondId);
        vm.prank(ADMIN);
        manager.retrievePrincipalFromYieldVault();
        _assertDeleted(firstId);
        _assertDeleted(secondId);
        assertEq(adapter.principalValue(), 0);
        assertEq(manager.principalValue(), 0);
        assertEq(address(adapter).balance + TREASURY.balance + SECOND_USER.balance + MANAGER.balance, 0);
        assertEq(IERC20(YSYBOLD).balanceOf(TREASURY), shares);
        assertEq(uint256(adapter.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.Settled));
    }

    function test_RejectingDepositorBlocksOnlyItsOwnZeroPayoutButDelaysFinalSweep() external {
        RejectingEthDepositor rejecting = new RejectingEthDepositor();
        _rollout(address(rejecting));
        vm.prank(TREASURY);
        adapter.initiateRecovery();
        vm.prank(TREASURY);
        adapter.activateRecoverySettlement(0);
        vm.warp(unlock);
        vm.expectRevert(abi.encodeWithSignature("TransferFailed()"));
        rejecting.withdraw(manager, secondId);
        (address owner, , uint256 remaining, ) = manager.deposits(secondId);
        assertEq(owner, address(rejecting));
        assertEq(remaining, secondPrincipal);
        vm.prank(TREASURY);
        manager.retrieveFunds(firstId);
        vm.prank(ADMIN);
        manager.retrievePrincipalFromYieldVault();
        _assertDeleted(firstId);
        assertEq(manager.principalValue(), 0);
        assertEq(adapter.principalValue(), secondPrincipal);
        assertEq(uint256(adapter.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.SettlementActive));
        vm.prank(TREASURY);
        vm.expectRevert();
        adapter.sweepRecoveryExcess();
    }

    function test_CurrentCurveUnusableExitRollsBackThenSharesRecoverWithoutSwaps() external {
        _rollout();
        // Fault injection makes Curve's actual exit unavailable; no claim of naturally imbalanced current liquidity.
        vm.mockCallRevert(
            CURVE,
            abi.encodeWithSignature("exchange(int128,int128,uint256,uint256,address)"),
            bytes("FAULT_CURVE")
        );
        _assertFailedExitAndRecover();
    }

    function test_CurrentSwapVenueFailureRollsBackThenSharesRecover() external {
        _rollout();
        vm.mockCallRevert(ROUTER, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector), bytes("FAULT_ROUTER"));
        _assertFailedExitAndRecover();
    }

    function test_CurrentStaleOracleExitRollsBackThenSharesRecover() external {
        _rollout();
        vm.warp(block.timestamp + adapter.ETH_USD_ORACLE_MAX_AGE() + 1);
        _assertFailedExitAndRecover();
    }

    function test_DonationsAfterRecoveryDoNotChangeSnapshot() external {
        _rollout();
        // Transfer a live share back after custody changes; the separate unit regression tests a pre-recovery donation.
        uint256 shares = adapter.principalShares();
        vm.prank(ADMIN);
        adapter.pause();
        vm.prank(TREASURY);
        adapter.initiateRecovery();
        vm.prank(TREASURY);
        IERC20(YSYBOLD).transfer(address(adapter), 1);
        assertEq(adapter.principalShares(), 0);
        assertEq(adapter.recoveryAccounting().sharesTransferred, shares);
        assertEq(IERC20(YSYBOLD).balanceOf(address(adapter)), 1);
    }

    function test_UpgradeAuthorityIsSeparatedAndPositionSurvivesUpgrade() external {
        _rollout();
        uint256 principal = adapter.principalValue();
        uint256 shares = adapter.principalShares();
        YBoldYieldVaultV2Mock next = new YBoldYieldVaultV2Mock(address(new YBoldConfigValidator()));
        vm.prank(ADMIN);
        vm.expectRevert();
        adapter.upgradeToAndCall(address(next), bytes(""));
        vm.prank(TREASURY);
        adapter.upgradeToAndCall(address(next), abi.encodeCall(YBoldYieldVaultV2Mock.initializeV2, (22)));
        assertEq(YBoldYieldVaultV2Mock(payable(address(adapter))).upgradeMarker(), 22);
        assertEq(adapter.principalValue(), principal);
        assertEq(adapter.principalShares(), shares);
        assertEq(IERC20(YSYBOLD).balanceOf(address(adapter)), shares);
    }

    function _rollout() private returns (uint256 ethRecovered) {
        return _rollout(SECOND_USER);
    }

    function _rollout(address secondDepositor) private returns (uint256 ethRecovered) {
        assertEq(TREASURY.balance, 0, "unexpected starting ETH");
        assertEq(IERC20(YSYBOLD).balanceOf(TREASURY), 156_014_003_721_394_916_792_917);
        for (uint256 id = 1; id <= 9; ++id) _assertDeleted(id);
        _preflight();
        ethRecovered = _liquidateTreasuryShares();
        adapter = _deploy();

        // This is the real protocol-owned residual, not the already-withdrawn nine treasury positions.
        vm.prank(ADMIN);
        manager.setYieldVault(address(adapter));
        assertEq(manager.principalValue(), 0);
        assertGt(MANAGER.balance, 0, "old protocol principal did not exit");
        vm.prank(ADMIN);
        manager.depositPrincipalIntoYieldVault();
        protocolPrincipal = manager.principalValue();

        uint256 secondEth = ethRecovered / 3;
        if (secondDepositor == SECOND_USER) {
            vm.prank(TREASURY);
            (bool sent, ) = SECOND_USER.call{ value: secondEth }("");
            assertTrue(sent);
        }
        vm.prank(TREASURY);
        manager.depositFunds{ value: ethRecovered - secondEth }();
        firstId = manager.depositId();
        (, , firstPrincipal, unlock) = manager.deposits(firstId);
        if (secondDepositor == SECOND_USER) {
            vm.prank(SECOND_USER);
            manager.depositFunds{ value: secondEth }();
        } else {
            vm.prank(TREASURY);
            RejectingEthDepositor(payable(secondDepositor)).deposit{ value: secondEth }(manager);
        }
        secondId = manager.depositId();
        (, , secondPrincipal, ) = manager.deposits(secondId);
        assertEq(adapter.principalValue(), firstPrincipal + secondPrincipal + protocolPrincipal);
        assertEq(adapter.principalShares(), IERC20(YSYBOLD).balanceOf(address(adapter)));
        assertEq(TREASURY.balance, 0);
        assertEq(SECOND_USER.balance, 0);
        console2.log("Residual old shares", IEUSDUSDCBeefyYieldVault(OLD).principalShares());
        console2.log("Residual old principal", IEUSDUSDCBeefyYieldVault(OLD).principalValue());
        _preflight();
    }

    function _assertFailedExitAndRecover() private {
        uint256 principal = adapter.principalValue();
        uint256 shares = adapter.principalShares();
        uint256 protocol = manager.principalValue();
        vm.prank(ADMIN);
        vm.expectRevert();
        manager.retrievePrincipalFromYieldVault();
        assertEq(adapter.principalValue(), principal);
        assertEq(adapter.principalShares(), shares);
        assertEq(manager.principalValue(), protocol);
        vm.prank(TREASURY);
        adapter.initiateRecovery();
        assertEq(IERC20(YSYBOLD).balanceOf(TREASURY), shares);
        assertEq(adapter.recoveryAccounting().principalSnapshot, principal);
        assertEq(adapter.principalShares(), 0);
        assertEq(adapter.claimableYield(), 0);
    }

    function _preflight() private {
        if (!preflightEnabled) return;
        vm.setEnv("YBOLD_VAULT", vm.toString(address(adapter)));
        vm.setEnv("YBOLD_EXPECTED_PROXY", vm.toString(address(adapter)));
        vm.setEnv("YBOLD_MIGRATION_ADMIN", vm.toString(ADMIN));
        vm.setEnv("YBOLD_EXPECTED_DEPOSIT_ID", vm.toString(manager.depositId()));
        vm.setEnv("YBOLD_MAX_DEPOSIT_SCAN", "100");
        vm.setEnv("YBOLD_EXPECTED_OLD_PROTOCOL_VALUE", "3033332133271012792310");
        vm.setEnv("YBOLD_EXPECTED_TREASURY_ETH", "0");
        vm.setEnv("YBOLD_EXPECTED_TREASURY_SHARES", "156014003721394916792917");
        vm.setEnv("YBOLD_MAX_OLD_SHARE_DUST", "121");
        vm.setEnv("YBOLD_MAX_OLD_VALUE_DUST", "150");
        if (address(adapter) != address(0)) {
            address implementation = address(uint160(uint256(vm.load(address(adapter), IMPLEMENTATION_SLOT))));
            vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION", vm.toString(implementation));
            vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH", vm.toString(implementation.codehash));
            vm.setEnv("YBOLD_UPGRADE_AUTHORITY", vm.toString(TREASURY));
            vm.setEnv("YBOLD_RECOVERY_TREASURY", vm.toString(TREASURY));
        }
        new YBoldMigrationPreflight().run();
    }

    function _recovery(uint256 payoutBps) private {
        _rollout();
        uint256 shares = adapter.principalShares();
        uint256 liabilities = adapter.principalValue();
        vm.mockCallRevert(YSYBOLD, abi.encodeWithSignature("maxRedeem(address,uint256)"), bytes("FAULT_YEARN"));
        vm.prank(ADMIN);
        vm.expectRevert();
        manager.retrievePrincipalFromYieldVault();
        vm.prank(TREASURY);
        adapter.initiateRecovery();
        assertEq(IERC20(YSYBOLD).balanceOf(TREASURY), shares);
        assertEq(adapter.recoveryAccounting().principalSnapshot, liabilities);
        vm.clearMockedCalls();

        // Actual treasury liquidation proceeds fund settlement; no vm.deal or token minting supplies the treasury.
        uint256 proceeds = _liquidateTreasuryShares();
        vm.prank(TREASURY);
        adapter.fundRecovery{ value: proceeds }();
        vm.prank(TREASURY);
        adapter.activateRecoverySettlement((proceeds * payoutBps) / 10_000);
        uint256 rate = adapter.recoveryAccounting().payoutRateWad;

        vm.prank(TREASURY);
        vm.expectRevert();
        manager.retrieveFunds(firstId);
        vm.warp(unlock);
        // Recovery settlement must not consult any exit dependency, even with stale or unavailable data.
        vm.mockCallRevert(YSYBOLD, abi.encodeWithSignature("convertToAssets(uint256)"), bytes("FAULT_YEARN"));
        vm.prank(SECOND_USER);
        manager.retrieveFunds(secondId);
        vm.prank(ADMIN);
        manager.retrievePrincipalFromYieldVault();
        vm.prank(TREASURY);
        manager.retrieveFunds(firstId);

        assertEq(SECOND_USER.balance, (secondPrincipal * rate) / 1e18);
        assertEq(MANAGER.balance, (protocolPrincipal * rate) / 1e18);
        assertEq(TREASURY.balance, (firstPrincipal * rate) / 1e18);
        assertEq(adapter.recoveryAccounting().principalSettled, liabilities);
        assertEq(adapter.recoveryAccounting().ethPaid, SECOND_USER.balance + MANAGER.balance + TREASURY.balance);
        assertEq(adapter.principalValue(), 0);
        assertEq(uint256(adapter.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.Settled));
        _assertDeleted(firstId);
        _assertDeleted(secondId);
        vm.prank(TREASURY);
        vm.expectRevert();
        manager.retrieveFunds(firstId);
        vm.prank(TREASURY);
        adapter.sweepRecoveryExcess();
        assertEq(address(adapter).balance, 0);
    }

    function _deploy() private returns (YBoldYieldVault vault) {
        IYBoldYieldVault.InitializationParams memory params = IYBoldYieldVault.InitializationParams({
            admin: ADMIN,
            yieldManager: MANAGER,
            upgradeAuthority: TREASURY,
            recoveryTreasury: TREASURY,
            weth: WETH,
            usdc: USDC,
            bold: BOLD,
            router: ROUTER,
            boldUsdcPool: CURVE,
            yearnBold: YBOLD,
            stakedYearnBold: YSYBOLD,
            ethUsd: ETH_FEED,
            usdcUsd: USDC_FEED
        });
        YBoldYieldVault implementation = new YBoldYieldVault(address(new YBoldConfigValidator()));
        vault = YBoldYieldVault(
            payable(
                address(new ERC1967Proxy(address(implementation), abi.encodeCall(YBoldYieldVault.initialize, (params))))
            )
        );
    }

    function _liquidateTreasuryShares() private returns (uint256 ethOut) {
        uint256 shares = IERC20(YSYBOLD).balanceOf(TREASURY);
        assertGe(IYearnVault(YSYBOLD).maxRedeem(TREASURY, 0), shares, "ysyBOLD unavailable");
        // Real Safe execution enters its proxy before the WETH2300-gas refund; warm the same slot and singleton.
        (bool safeReadable, ) = TREASURY.staticcall(abi.encodeWithSignature("VERSION()"));
        assertTrue(safeReadable);
        vm.startPrank(TREASURY);
        uint256 yAssets = IYearnVault(YSYBOLD).redeem(shares, TREASURY, TREASURY, 0);
        uint256 boldAssets = IYearnVault(YBOLD).redeem(yAssets, TREASURY, TREASURY, 0);
        IERC20(BOLD).approve(CURVE, boldAssets);
        uint256 usdcOut = ICurveStableSwapNG(CURVE).exchange(
            0,
            1,
            boldAssets,
            ((boldAssets / 1e12) * 9_850) / 10_000,
            TREASURY
        );
        IERC20(BOLD).approve(CURVE, 0);
        (, int256 ethPrice, , , ) = AggregatorV3Interface(ETH_FEED).latestRoundData();
        (, int256 usdcPrice, , , ) = AggregatorV3Interface(USDC_FEED).latestRoundData();
        uint256 minWeth = (((usdcOut * uint256(usdcPrice) * 1e12) / uint256(ethPrice)) * 9_950) / 10_000;
        IERC20(USDC).approve(ROUTER, usdcOut);
        ethOut = ISwapRouter(ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: WETH,
                fee: 500,
                recipient: TREASURY,
                deadline: block.timestamp + 15 minutes,
                amountIn: usdcOut,
                amountOutMinimum: minWeth,
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(USDC).approve(ROUTER, 0);
        IWETH(WETH).withdraw(ethOut);
        vm.stopPrank();
        assertEq(IERC20(YSYBOLD).balanceOf(TREASURY), 0);
        assertEq(IERC20(YBOLD).balanceOf(TREASURY), 0);
        assertEq(IERC20(BOLD).balanceOf(TREASURY), 0);
        assertEq(IERC20(USDC).balanceOf(TREASURY), 0);
        assertEq(IERC20(WETH).balanceOf(TREASURY), 0);
    }

    function _assertDeleted(uint256 id) private view {
        (address owner, , uint256 value, ) = manager.deposits(id);
        assertEq(owner, address(0));
        assertEq(value, 0);
    }

    function _refreshOracle(address feed) private {
        (uint80 round, int256 answer, , , ) = AggregatorV3Interface(feed).latestRoundData();
        vm.mockCall(
            feed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(round, answer, block.timestamp, block.timestamp, round)
        );
    }
}
