// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { YBoldMigrationPreflight } from "script/YBoldMigrationPreflight.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { PYBSeba } from "src/PYBSeba.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldConfigValidator } from "src/YBoldConfigValidator.sol";
import { YieldManager } from "src/YieldManager.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { ICurveStableSwapNG } from "src/vendor/curve/ICurveStableSwapNG.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IYearnVault } from "src/vendor/yearn/IYearnVault.sol";
import { MockYBoldYieldManager } from "tests/mocks/MockYBoldIntegrations.sol";
import { YBoldYieldVaultV2Mock } from "tests/mocks/YBoldYieldVaultV2Mock.sol";

interface IReportableYearnVault {
    function keeper() external view returns (address);
    function profitMaxUnlockTime() external view returns (uint256);
    function report() external returns (uint256 profit, uint256 loss);
}

interface IPythLike {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    function getPriceUnsafe(bytes32 priceId) external view returns (Price memory price);
}

contract YBoldMigrationForkTest is Test {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    struct RecoveryTestState {
        uint256 userDepositId;
        uint256 userAmount;
        uint256 secondDepositId;
        uint256 secondAmount;
        uint256 protocolPrincipal;
        uint256 totalPrincipal;
        uint256 payoutRate;
        uint256 userPaid;
        uint256 secondPaid;
        uint256 protocolPaid;
        uint32 unlockTime;
        uint32 secondUnlockTime;
    }

    uint256 internal constant FRESH_BLOCK = 26_196_493;
    uint256 internal constant HISTORIC_SUCCESS_BLOCK = 25_831_161;

    address internal constant SEBA_POOL = 0xe3B17b4533b339d3CBC26F57199d3fb937129894;
    address internal constant YIELD_MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address internal constant OLD_BEEFY_VAULT = 0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba;
    address internal constant PYB_SEBA = 0x8D06a179486111E556A7C46E49352259B0279CD1;
    address internal constant GOVERNANCE_ADMIN = 0xf83b11b09EEc073ACE4481b2F4c8357e156714b3;
    address internal constant DEPOSITOR_ADMIN = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant AUTOMATOR = 0x8FbBC54D49b23F5b397dfE62AD2Fb0E09Cbe9379;
    address internal constant SECOND_DEPOSITOR = address(0xA11CE);
    // Test-only custody address; this is not an assertion about the live treasury signer.
    address internal constant TREASURY_STAND_IN = address(0xBEEFCAFE);

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address internal constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant BOLD_USDC_POOL = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address internal constant ST_YBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant ETH_USD_FEED = 0xc0053f3FBcCD593758258334Dfce24C2A9A673aD;
    address internal constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant PYTH = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    bytes32 internal constant BOLD_USD_PRICE_ID = 0xd6134dbb0427240f901e3e596d6e63f7d85088f96cd4cd4ae2f89c0819b5d623;

    YieldManager internal manager;
    YBoldYieldVault internal adapter;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), FRESH_BLOCK);
        manager = YieldManager(payable(YIELD_MANAGER));
    }

    function test_LiveYBoldDepositAndRoundTripWithdrawal() external {
        MockYBoldYieldManager isolatedManager = new MockYBoldYieldManager();
        YBoldYieldVault isolatedAdapter = _deploy(address(isolatedManager));
        vm.deal(address(this), 1 ether);

        uint256 value = isolatedManager.deposit{ value: 1 ether }(address(isolatedAdapter));

        assertGt(value, 1000e18);
        assertEq(isolatedAdapter.principalValue(), value);
        assertEq(isolatedAdapter.principalShares(), IERC20(ST_YBOLD).balanceOf(address(isolatedAdapter)));
        uint256 before = address(isolatedManager).balance;

        isolatedManager.retrieve(address(isolatedAdapter), value);

        assertGt(address(isolatedManager).balance - before, 0.98 ether);
        assertEq(isolatedAdapter.principalValue(), 0);
        assertEq(isolatedAdapter.principalShares(), 0);
    }

    function test_OversizedSingleTrancheRevertsWithoutMintingPrincipal() external {
        MockYBoldYieldManager isolatedManager = new MockYBoldYieldManager();
        YBoldYieldVault isolatedAdapter = _deploy(address(isolatedManager));
        // Deliberately synthetic stress input; the full migration test uses only recovered user ETH.
        vm.deal(address(this), 1000 ether);

        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Too little received"));
        isolatedManager.deposit{ value: 1000 ether }(address(isolatedAdapter));

        assertEq(isolatedAdapter.principalValue(), 0);
        assertEq(isolatedAdapter.principalShares(), 0);
        assertEq(IERC20(ST_YBOLD).balanceOf(address(isolatedAdapter)), 0);
    }

    function test_EmergencyPauseWithdrawalAndCoreRescueBlockOnLiveIntegrations() external {
        MockYBoldYieldManager isolatedManager = new MockYBoldYieldManager();
        YBoldYieldVault isolatedAdapter = _deploy(address(isolatedManager));
        vm.deal(address(this), 2 ether);
        uint256 value = isolatedManager.deposit{ value: 1 ether }(address(isolatedAdapter));

        vm.startPrank(GOVERNANCE_ADMIN);
        isolatedAdapter.pause();
        isolatedAdapter.setEmergencyMode(true);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.CoreAsset.selector, ST_YBOLD));
        isolatedAdapter.rescueToken(ST_YBOLD, GOVERNANCE_ADMIN, 1);
        vm.stopPrank();

        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        isolatedManager.deposit{ value: 1 ether }(address(isolatedAdapter));
        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        isolatedManager.claim(address(isolatedAdapter));

        isolatedManager.retrieve(address(isolatedAdapter), value);
        assertGt(address(isolatedManager).balance, 0.98 ether);
        assertEq(isolatedAdapter.principalValue(), 0);
    }

    function test_EmergencyWithdrawalStillFailsClosedOnStaleOracle() external {
        MockYBoldYieldManager isolatedManager = new MockYBoldYieldManager();
        YBoldYieldVault isolatedAdapter = _deploy(address(isolatedManager));
        vm.deal(address(this), 1 ether);
        uint256 value = isolatedManager.deposit{ value: 1 ether }(address(isolatedAdapter));

        vm.prank(GOVERNANCE_ADMIN);
        isolatedAdapter.setEmergencyMode(true);
        (, , , uint256 updatedAt, ) = AggregatorV3Interface(ETH_USD_FEED).latestRoundData();
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.OracleStale.selector, ETH_USD_FEED, updatedAt));
        isolatedManager.retrieve(address(isolatedAdapter), value);
        assertEq(isolatedAdapter.principalValue(), value);
    }

    function test_FaultInjectedCurveImbalanceCanUseFullTreasuryRecovery() external {
        MockYBoldYieldManager isolatedManager = new MockYBoldYieldManager();
        YBoldYieldVault isolatedAdapter = _deploy(address(isolatedManager));
        vm.deal(address(this), 2 ether);
        uint256 value = isolatedManager.deposit{ value: 2 ether }(address(isolatedAdapter));
        uint256 shares = isolatedAdapter.principalShares();
        uint256 treasurySharesBefore = IERC20(ST_YBOLD).balanceOf(GOVERNANCE_ADMIN);

        // Fault injection: the live pool is healthy at this block; this models an unusable BOLD/USDC exit.
        vm.mockCall(
            BOLD_USDC_POOL,
            abi.encodeWithSelector(ICurveStableSwapNG.price_oracle.selector, 0),
            abi.encode(2e18)
        );
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.BoldPegDeviationExceeded.selector, 2e18, 100));
        isolatedManager.retrieve(address(isolatedAdapter), value);

        vm.prank(GOVERNANCE_ADMIN);
        isolatedAdapter.initiateRecovery();
        assertEq(IERC20(ST_YBOLD).balanceOf(GOVERNANCE_ADMIN) - treasurySharesBefore, shares);

        // Synthetic funding proves settlement mechanics, not that treasury can liquidate st-yBOLD at par.
        vm.deal(GOVERNANCE_ADMIN, 2 ether);
        vm.prank(GOVERNANCE_ADMIN);
        isolatedAdapter.fundRecovery{ value: 2 ether }();
        vm.prank(GOVERNANCE_ADMIN);
        isolatedAdapter.activateRecoverySettlement(2 ether);
        uint256 committedEth = isolatedAdapter.recoveryAccounting().settlementEth;

        uint256 before = address(isolatedManager).balance;
        isolatedManager.retrieve(address(isolatedAdapter), value);
        assertEq(address(isolatedManager).balance - before, committedEth);
        assertEq(uint256(isolatedAdapter.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.Settled));
        assertEq(isolatedAdapter.principalValue(), 0);
        assertEq(IERC20(ST_YBOLD).balanceOf(address(isolatedAdapter)), 0);
    }

    function test_FaultInjectedSwapVenueFailureDoesNotBlockShareRecovery() external {
        MockYBoldYieldManager isolatedManager = new MockYBoldYieldManager();
        YBoldYieldVault isolatedAdapter = _deploy(address(isolatedManager));
        vm.deal(address(this), 1 ether);
        uint256 value = isolatedManager.deposit{ value: 1 ether }(address(isolatedAdapter));
        uint256 shares = isolatedAdapter.principalShares();

        // Fault injection: force the live Uniswap router call to fail only after the real deposit succeeded.
        vm.mockCallRevert(
            SWAP_ROUTER,
            abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector),
            abi.encodeWithSignature("Error(string)", "FAULT_INJECTED_ROUTER_UNAVAILABLE")
        );
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "FAULT_INJECTED_ROUTER_UNAVAILABLE"));
        isolatedManager.retrieve(address(isolatedAdapter), value);

        vm.prank(GOVERNANCE_ADMIN);
        isolatedAdapter.initiateRecovery();
        assertEq(IERC20(ST_YBOLD).balanceOf(address(isolatedAdapter)), 0);
        assertGe(IERC20(ST_YBOLD).balanceOf(GOVERNANCE_ADMIN), shares);
    }

    function test_AuthorizedForkUpgradePreservesARealYBoldPosition() external {
        MockYBoldYieldManager isolatedManager = new MockYBoldYieldManager();
        YBoldYieldVault isolatedAdapter = _deploy(address(isolatedManager));
        vm.deal(address(this), 1 ether);
        uint256 value = isolatedManager.deposit{ value: 1 ether }(address(isolatedAdapter));
        uint256 shares = isolatedAdapter.principalShares();
        YBoldYieldVaultV2Mock implementationV2 = new YBoldYieldVaultV2Mock(address(new YBoldConfigValidator()));

        vm.prank(GOVERNANCE_ADMIN);
        isolatedAdapter.upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(YBoldYieldVaultV2Mock.initializeV2, (2026))
        );

        YBoldYieldVaultV2Mock upgraded = YBoldYieldVaultV2Mock(payable(address(isolatedAdapter)));
        assertEq(upgraded.upgradeMarker(), 2026);
        assertEq(upgraded.principalValue(), value);
        assertEq(upgraded.principalShares(), shares);
        assertEq(IERC20(ST_YBOLD).balanceOf(address(upgraded)), shares);
        assertTrue(upgraded.hasRole(upgraded.UPGRADER_ROLE(), GOVERNANCE_ADMIN));
    }

    function test_RealManagerRecoverySettlesUserIdAndProtocolPrincipalAtOnePartialLossRate() external {
        RecoveryTestState memory state;
        adapter = _deploy(YIELD_MANAGER);
        vm.prank(GOVERNANCE_ADMIN);
        manager.retrievePrincipalFromYieldVault();
        assertEq(manager.principalValue(), 0);
        vm.prank(GOVERNANCE_ADMIN);
        manager.setYieldVault(address(adapter));

        vm.deal(DEPOSITOR_ADMIN, 1 ether);
        vm.prank(DEPOSITOR_ADMIN);
        manager.depositFunds{ value: 1 ether }();
        state.userDepositId = manager.depositId();
        (, IYieldManager.Deposit memory userDeposit) = _depositorAndDeposit(state.userDepositId);
        state.userAmount = userDeposit.amount;
        state.unlockTime = userDeposit.unlockTime;

        vm.deal(SECOND_DEPOSITOR, 2 ether);
        vm.prank(SECOND_DEPOSITOR);
        manager.depositFunds{ value: 2 ether }();
        state.secondDepositId = manager.depositId();
        (, IYieldManager.Deposit memory secondDeposit) = _depositorAndDeposit(state.secondDepositId);
        state.secondAmount = secondDeposit.amount;
        state.secondUnlockTime = secondDeposit.unlockTime;

        // Keep the manager's pending conversion reserved and create exactly 1 ETH of test protocol principal.
        vm.deal(YIELD_MANAGER, manager.pendingBoldConversion() + 1 ether);
        vm.prank(GOVERNANCE_ADMIN);
        manager.depositPrincipalIntoYieldVault();
        state.protocolPrincipal = manager.principalValue();
        state.totalPrincipal = state.userAmount + state.secondAmount + state.protocolPrincipal;
        assertEq(adapter.principalValue(), state.totalPrincipal);

        vm.warp(uint256(state.secondUnlockTime) + 1);
        // Fault injection: the real Yearn position exists, but maxRedeem is made unavailable.
        uint256 unavailableShares = IYearnVault(ST_YBOLD).previewWithdraw(state.userAmount);
        vm.mockCall(ST_YBOLD, abi.encodeWithSelector(IYearnVault.maxRedeem.selector), abi.encode(0));
        vm.prank(DEPOSITOR_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.InsufficientLiquidity.selector, ST_YBOLD, unavailableShares, 0)
        );
        manager.retrieveFunds(state.userDepositId);
        (, , uint256 stillClaimable, ) = manager.deposits(state.userDepositId);
        assertEq(stillClaimable, state.userAmount);

        uint256 shares = adapter.principalShares();
        uint256 treasurySharesBefore = IERC20(ST_YBOLD).balanceOf(GOVERNANCE_ADMIN);
        vm.prank(GOVERNANCE_ADMIN);
        adapter.initiateRecovery();
        assertEq(IERC20(ST_YBOLD).balanceOf(GOVERNANCE_ADMIN) - treasurySharesBefore, shares);

        // Synthetic funding isolates fixed-rate settlement from offchain treasury liquidation quality.
        vm.deal(GOVERNANCE_ADMIN, 1.5 ether);
        vm.prank(GOVERNANCE_ADMIN);
        adapter.fundRecovery{ value: 1.5 ether }();
        vm.prank(GOVERNANCE_ADMIN);
        adapter.activateRecoverySettlement(1.5 ether);
        state.payoutRate = adapter.recoveryAccounting().payoutRateWad;

        // The larger second user settles first; the fixed rate makes claim ordering irrelevant.
        uint256 secondBefore = SECOND_DEPOSITOR.balance;
        vm.prank(SECOND_DEPOSITOR);
        manager.retrieveFunds(state.secondDepositId);
        state.secondPaid = SECOND_DEPOSITOR.balance - secondBefore;
        assertEq(state.secondPaid, (state.secondAmount * state.payoutRate) / 1e18);
        (, , uint256 secondDeletedAmount, ) = manager.deposits(state.secondDepositId);
        assertEq(secondDeletedAmount, 0);

        uint256 depositorBefore = DEPOSITOR_ADMIN.balance;
        vm.prank(DEPOSITOR_ADMIN);
        manager.retrieveFunds(state.userDepositId);
        state.userPaid = DEPOSITOR_ADMIN.balance - depositorBefore;
        assertEq(state.userPaid, (state.userAmount * state.payoutRate) / 1e18);
        (, , uint256 deletedAmount, ) = manager.deposits(state.userDepositId);
        assertEq(deletedAmount, 0);
        vm.prank(DEPOSITOR_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IYieldManager.NonExistingDeposit.selector, state.userDepositId));
        manager.retrieveFunds(state.userDepositId);

        uint256 managerBefore = YIELD_MANAGER.balance;
        vm.prank(GOVERNANCE_ADMIN);
        manager.setYieldVault(OLD_BEEFY_VAULT);
        state.protocolPaid = YIELD_MANAGER.balance - managerBefore;
        assertEq(state.protocolPaid, (state.protocolPrincipal * state.payoutRate) / 1e18);

        _assertAndSweepCompletedRecovery(state);
    }

    function _assertAndSweepCompletedRecovery(RecoveryTestState memory state) internal {
        assertEq(manager.principalValue(), 0);
        assertEq(address(manager.yieldVault()), OLD_BEEFY_VAULT);
        assertEq(adapter.principalValue(), 0);
        assertEq(adapter.principalShares(), 0);
        assertEq(IERC20(ST_YBOLD).balanceOf(address(adapter)), 0);
        assertEq(uint256(adapter.recoveryState()), uint256(IYBoldYieldVault.RecoveryState.Settled));

        IYBoldYieldVault.RecoveryAccounting memory accounting = adapter.recoveryAccounting();
        assertEq(accounting.principalSnapshot, state.totalPrincipal);
        assertEq(accounting.principalSettled, state.totalPrincipal);
        assertEq(accounting.ethPaid, state.userPaid + state.secondPaid + state.protocolPaid);
        if (address(adapter).balance != 0) {
            vm.prank(GOVERNANCE_ADMIN);
            adapter.sweepRecoveryExcess();
        }
        assertEq(address(adapter).balance, 0);
    }

    function test_LiveSwitchWithNoProtocolPositionLeavesUserPositionsOnOldVault() external {
        adapter = _deploy(YIELD_MANAGER);
        vm.prank(GOVERNANCE_ADMIN);
        manager.retrievePrincipalFromYieldVault();
        assertEq(manager.principalValue(), 0);

        vm.prank(GOVERNANCE_ADMIN);
        manager.setYieldVault(address(adapter));

        assertEq(address(manager.yieldVault()), address(adapter));
        assertEq(adapter.principalValue(), 0);
        (, IYieldManager.Deposit memory oldUserPosition) = _depositorAndDeposit(1);
        assertEq(address(oldUserPosition.vaultAtDeposit), OLD_BEEFY_VAULT);
        assertGt(oldUserPosition.amount, 0);
    }

    function test_InterruptedUserUnwindCanResumeBeforeStrategySwitch() external {
        _selectHistoricSuccessFork();
        adapter = _deploy(YIELD_MANAGER);
        vm.startPrank(DEPOSITOR_ADMIN);
        for (uint256 id = 1; id <= 4; ++id) {
            manager.retrieveFunds(id);
        }
        vm.stopPrank();

        assertEq(address(manager.yieldVault()), OLD_BEEFY_VAULT);
        for (uint256 id = 1; id <= 4; ++id) {
            (, , uint256 deletedAmount, ) = manager.deposits(id);
            assertEq(deletedAmount, 0);
        }
        for (uint256 id = 5; id <= 9; ++id) {
            (address depositor, IYieldManager.Deposit memory remaining) = _depositorAndDeposit(id);
            assertEq(depositor, DEPOSITOR_ADMIN);
            assertEq(address(remaining.vaultAtDeposit), OLD_BEEFY_VAULT);
            assertGt(remaining.amount, 0);
        }

        vm.startPrank(DEPOSITOR_ADMIN);
        for (uint256 id = 5; id <= 9; ++id) {
            manager.retrieveFunds(id);
        }
        vm.stopPrank();

        vm.startPrank(GOVERNANCE_ADMIN);
        manager.setYieldVault(address(adapter));
        manager.depositPrincipalIntoYieldVault();
        vm.stopPrank();

        assertEq(address(manager.yieldVault()), address(adapter));
        assertEq(adapter.principalValue(), manager.principalValue());
        assertEq(adapter.principalShares(), IERC20(ST_YBOLD).balanceOf(address(adapter)));
    }

    function test_FreshForkBeefyExitAbortsWithoutChangingFailedDepositOrShares() external {
        for (uint256 id = 1; id <= 9; ++id) {
            (address depositor, IYieldManager.Deposit memory beforeDeposit) = _depositorAndDeposit(id);
            uint256 beforeShares = IEUSDUSDCBeefyYieldVault(OLD_BEEFY_VAULT).principalShares();
            uint256 beforePrincipal = manager.principalValue();
            uint256 beforeEth = DEPOSITOR_ADMIN.balance;

            vm.prank(DEPOSITOR_ADMIN);
            try manager.retrieveFunds(id) {
                continue;
            } catch (bytes memory reason) {
                assertEq(reason, abi.encodeWithSignature("Error(string)", "Not enough coins removed"));
                (address afterDepositor, IYieldManager.Deposit memory afterDeposit) = _depositorAndDeposit(id);
                assertEq(afterDepositor, depositor);
                assertEq(afterDeposit.amount, beforeDeposit.amount);
                assertEq(address(afterDeposit.vaultAtDeposit), address(beforeDeposit.vaultAtDeposit));
                assertEq(IEUSDUSDCBeefyYieldVault(OLD_BEEFY_VAULT).principalShares(), beforeShares);
                assertEq(manager.principalValue(), beforePrincipal);
                assertEq(DEPOSITOR_ADMIN.balance, beforeEth);
                console2.log("fresh Beefy exit failed at ID", id);
                return;
            }
        }
        revert("EXPECTED_FRESH_EXIT_FAILURE");
    }

    function test_FullHistoricalBeefyMigrationHarvestPybDeliveryAndPostMigrationWithdrawal() external {
        _selectHistoricSuccessFork();
        assertEq(address(manager.yieldVault()), OLD_BEEFY_VAULT);
        assertEq(manager.depositId(), 9);
        assertEq(manager.pendingBoldConversion(), 0);
        assertEq(manager.activeRouterUid(), bytes32(0));
        assertTrue(manager.yieldFlowActive());
        _runPreflight(address(0), 9);

        uint256 depositorBalanceBefore = DEPOSITOR_ADMIN.balance;
        vm.startPrank(DEPOSITOR_ADMIN);
        for (uint256 id = 1; id <= 9; ++id) {
            (address depositor, IYieldManager.Deposit memory ignored) = _depositorAndDeposit(id);
            ignored;
            assertEq(depositor, DEPOSITOR_ADMIN);
            manager.retrieveFunds(id);
            if (id == 4) _runPreflight(address(0), 5);
        }
        vm.stopPrank();
        uint256 userEthReturned = DEPOSITOR_ADMIN.balance - depositorBalanceBefore;
        assertGt(userEthReturned, 100 ether);
        _runPreflight(address(0), 0);

        // The production route has a distinct ETH custody period before the new adapter is deployed.
        vm.prank(DEPOSITOR_ADMIN);
        (bool sentToTreasury, ) = payable(TREASURY_STAND_IN).call{ value: userEthReturned }("");
        assertTrue(sentToTreasury);
        assertEq(TREASURY_STAND_IN.balance, userEthReturned);
        assertEq(address(manager.yieldVault()), OLD_BEEFY_VAULT);
        assertEq(manager.depositId(), 9);

        adapter = _deploy(YIELD_MANAGER);
        _runPreflight(address(adapter), 0);

        vm.prank(GOVERNANCE_ADMIN);
        manager.setYieldVault(address(adapter));
        assertEq(address(manager.yieldVault()), address(adapter));
        assertEq(manager.principalValue(), 0);
        assertGt(YIELD_MANAGER.balance, 0);
        _runPreflight(address(adapter), 0);

        IEUSDUSDCBeefyYieldVault oldVault = IEUSDUSDCBeefyYieldVault(OLD_BEEFY_VAULT);
        assertLe(oldVault.principalShares(), 120);
        assertLe(oldVault.principalValue(), 150);

        vm.prank(GOVERNANCE_ADMIN);
        manager.depositPrincipalIntoYieldVault();
        uint256 protocolPrincipal = manager.principalValue();
        assertGt(protocolPrincipal, 0);
        _runPreflight(address(adapter), 0);

        // Return only the ETH actually recovered from Beefy; no synthetic user capital is minted.
        vm.prank(TREASURY_STAND_IN);
        (bool releasedToDepositor, ) = payable(DEPOSITOR_ADMIN).call{ value: userEthReturned }("");
        assertTrue(releasedToDepositor);
        assertEq(TREASURY_STAND_IN.balance, 0);

        uint256 firstTrancheEth = userEthReturned / 3;
        uint256 secondTrancheEth = userEthReturned - firstTrancheEth;
        vm.startPrank(DEPOSITOR_ADMIN);
        manager.depositFunds{ value: firstTrancheEth }();
        manager.depositFunds{ value: secondTrancheEth }();
        vm.stopPrank();

        assertEq(manager.depositId(), 11);
        (, IYieldManager.Deposit memory firstTranche) = _depositorAndDeposit(10);
        (, IYieldManager.Deposit memory secondTranche) = _depositorAndDeposit(11);
        assertEq(address(firstTranche.vaultAtDeposit), address(adapter));
        assertEq(address(secondTranche.vaultAtDeposit), address(adapter));
        assertEq(firstTranche.unlockTime, block.timestamp + manager.USER_LOCK_SECS());
        assertEq(secondTranche.unlockTime, block.timestamp + manager.USER_LOCK_SECS());
        assertEq(adapter.principalValue(), protocolPrincipal + firstTranche.amount + secondTranche.amount);
        assertEq(adapter.principalShares(), IERC20(ST_YBOLD).balanceOf(address(adapter)));

        _reportSyntheticStYBoldProfit(10e18);
        vm.warp(block.timestamp + IReportableYearnVault(ST_YBOLD).profitMaxUnlockTime() + 1);
        _mockFreshChainlinkRound(ETH_USD_FEED);
        _mockFreshChainlinkRound(USDC_USD_FEED);
        assertGt(adapter.claimableYield(), 0);

        uint256 pendingBefore = manager.pendingBoldConversion();
        vm.prank(AUTOMATOR);
        manager.distributeYield();
        assertGt(manager.pendingBoldConversion(), pendingBefore);

        uint256 pybAssetsBefore = PYBSeba(PYB_SEBA).totalAssets();
        deal(BOLD, YIELD_MANAGER, IERC20(BOLD).balanceOf(YIELD_MANAGER) + 1e18);
        _mockFreshSBoldOracle();
        vm.prank(AUTOMATOR);
        manager.runBoldConversion(0);
        assertGt(PYBSeba(PYB_SEBA).totalAssets(), pybAssetsBefore);

        vm.warp(uint256(firstTranche.unlockTime) + 1);
        _mockFreshChainlinkRound(ETH_USD_FEED);
        _mockFreshChainlinkRound(USDC_USD_FEED);
        uint256 depositorBeforeWithdrawal = DEPOSITOR_ADMIN.balance;
        vm.prank(DEPOSITOR_ADMIN);
        manager.retrieveFunds(10);
        assertGt(DEPOSITOR_ADMIN.balance, depositorBeforeWithdrawal);

        (, , uint256 deletedAmount, ) = manager.deposits(10);
        assertEq(deletedAmount, 0);
        assertEq(adapter.principalValue(), manager.principalValue() + secondTranche.amount);
        assertEq(adapter.principalShares(), IERC20(ST_YBOLD).balanceOf(address(adapter)));
        _runPreflight(address(adapter), 0);
    }

    function _deploy(address yieldManager) internal returns (YBoldYieldVault deployed) {
        YBoldYieldVault implementation = new YBoldYieldVault(address(new YBoldConfigValidator()));
        IYBoldYieldVault.InitializationParams memory params = IYBoldYieldVault.InitializationParams({
            admin: GOVERNANCE_ADMIN,
            yieldManager: yieldManager,
            upgradeAuthority: GOVERNANCE_ADMIN,
            recoveryTreasury: GOVERNANCE_ADMIN,
            weth: WETH,
            usdc: USDC,
            bold: BOLD,
            router: SWAP_ROUTER,
            boldUsdcPool: BOLD_USDC_POOL,
            yearnBold: YBOLD,
            stakedYearnBold: ST_YBOLD,
            ethUsd: ETH_USD_FEED,
            usdcUsd: USDC_USD_FEED
        });
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(YBoldYieldVault.initialize, (params))
        );
        deployed = YBoldYieldVault(payable(address(proxy)));
    }

    function _selectHistoricSuccessFork() internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), HISTORIC_SUCCESS_BLOCK);
        manager = YieldManager(payable(YIELD_MANAGER));
    }

    function _depositorAndDeposit(
        uint256 id
    ) internal view returns (address depositor, IYieldManager.Deposit memory depositData) {
        (address owner, IYieldVault vaultAtDeposit, uint256 amount, uint32 unlockTime) = manager.deposits(id);
        depositor = owner;
        depositData = IYieldManager.Deposit({
            depositor: owner,
            vaultAtDeposit: vaultAtDeposit,
            amount: amount,
            unlockTime: unlockTime
        });
    }

    function _reportSyntheticStYBoldProfit(uint256 boldAmount) internal {
        deal(BOLD, address(this), IERC20(BOLD).balanceOf(address(this)) + boldAmount);
        IERC20(BOLD).approve(YBOLD, boldAmount);
        uint256 yBoldShares = IYearnVault(YBOLD).deposit(boldAmount, address(this));
        assertTrue(IERC20(YBOLD).transfer(ST_YBOLD, yBoldShares));
        vm.prank(IReportableYearnVault(ST_YBOLD).keeper());
        IReportableYearnVault(ST_YBOLD).report();
    }

    function _mockFreshChainlinkRound(address feed) internal {
        (uint80 roundId, int256 answer, , , ) = AggregatorV3Interface(feed).latestRoundData();
        vm.mockCall(
            feed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, block.timestamp, block.timestamp, roundId)
        );
    }

    function _mockFreshSBoldOracle() internal {
        IPythLike.Price memory price = IPythLike(PYTH).getPriceUnsafe(BOLD_USD_PRICE_ID);
        price.publishTime = block.timestamp;
        vm.mockCall(
            PYTH,
            abi.encodeWithSelector(IPythLike.getPriceUnsafe.selector, BOLD_USD_PRICE_ID),
            abi.encode(price)
        );
    }

    function _runPreflight(address newVault, uint256 expectedOldActive) internal {
        vm.setEnv("YBOLD_VAULT", vm.toString(newVault));
        vm.setEnv("YBOLD_MIGRATION_ADMIN", vm.toString(GOVERNANCE_ADMIN));
        vm.setEnv("YBOLD_EXPECTED_OLD_ACTIVE", vm.toString(expectedOldActive));
        if (newVault != address(0)) {
            address implementation = address(uint160(uint256(vm.load(newVault, IMPLEMENTATION_SLOT))));
            vm.setEnv("YBOLD_EXPECTED_IMPLEMENTATION", vm.toString(implementation));
            vm.setEnv("YBOLD_UPGRADE_AUTHORITY", vm.toString(GOVERNANCE_ADMIN));
            vm.setEnv("YBOLD_RECOVERY_TREASURY", vm.toString(GOVERNANCE_ADMIN));
        }
        new YBoldMigrationPreflight().run();
    }
}
