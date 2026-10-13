// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { YBoldMigrationPreflight } from "script/YBoldMigrationPreflight.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";
import { PYBSeba } from "src/PYBSeba.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YieldManager } from "src/YieldManager.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { IYearnVault } from "src/vendor/yearn/IYearnVault.sol";
import { MockYBoldYieldManager } from "tests/mocks/MockYBoldIntegrations.sol";

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
    uint256 internal constant PINNED_BLOCK = 25_831_161;

    address internal constant SEBA_POOL = 0xe3B17b4533b339d3CBC26F57199d3fb937129894;
    address internal constant YIELD_MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address internal constant OLD_BEEFY_VAULT = 0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba;
    address internal constant PYB_SEBA = 0x8D06a179486111E556A7C46E49352259B0279CD1;
    address internal constant GOVERNANCE_ADMIN = 0xf83b11b09EEc073ACE4481b2F4c8357e156714b3;
    address internal constant DEPOSITOR_ADMIN = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant AUTOMATOR = 0x8FbBC54D49b23F5b397dfE62AD2Fb0E09Cbe9379;

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
        vm.createSelectFork(vm.envString("MAINNET_RPC"), PINNED_BLOCK);
        manager = YieldManager(payable(YIELD_MANAGER));
        adapter = _deploy(YIELD_MANAGER);
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

    function test_LiveSwitchWithNoProtocolPositionLeavesUserPositionsOnOldVault() external {
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
        vm.startPrank(DEPOSITOR_ADMIN);
        for (uint256 id = 1; id <= 4; ++id) {
            manager.retrieveFunds(id);
        }
        vm.stopPrank();

        assertEq(address(manager.yieldVault()), OLD_BEEFY_VAULT);
        for (uint256 id = 1; id <= 4; ++id) {
            (,, uint256 deletedAmount,) = manager.deposits(id);
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

    function test_FullLiveBeefyMigrationHarvestPybDeliveryAndPostMigrationWithdrawal() external {
        assertEq(address(manager.yieldVault()), OLD_BEEFY_VAULT);
        assertEq(manager.depositId(), 9);
        assertEq(manager.pendingBoldConversion(), 0);
        assertEq(manager.activeRouterUid(), bytes32(0));
        assertTrue(manager.yieldFlowActive());
        _runPreflight();

        uint256 depositorBalanceBefore = DEPOSITOR_ADMIN.balance;
        vm.startPrank(DEPOSITOR_ADMIN);
        for (uint256 id = 1; id <= 9; ++id) {
            (address depositor, IYieldManager.Deposit memory ignored) = _depositorAndDeposit(id);
            ignored;
            assertEq(depositor, DEPOSITOR_ADMIN);
            manager.retrieveFunds(id);
        }
        vm.stopPrank();
        uint256 userEthReturned = DEPOSITOR_ADMIN.balance - depositorBalanceBefore;
        assertGt(userEthReturned, 100 ether);

        vm.prank(GOVERNANCE_ADMIN);
        manager.setYieldVault(address(adapter));
        assertEq(address(manager.yieldVault()), address(adapter));
        assertEq(manager.principalValue(), 0);

        IEUSDUSDCBeefyYieldVault oldVault = IEUSDUSDCBeefyYieldVault(OLD_BEEFY_VAULT);
        assertLe(oldVault.principalShares(), 120);
        assertLe(oldVault.principalValue(), 150);

        vm.prank(GOVERNANCE_ADMIN);
        manager.depositPrincipalIntoYieldVault();
        uint256 protocolPrincipal = manager.principalValue();
        assertGt(protocolPrincipal, 0);

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

        (,, uint256 deletedAmount,) = manager.deposits(10);
        assertEq(deletedAmount, 0);
        assertEq(adapter.principalValue(), manager.principalValue() + secondTranche.amount);
        assertEq(adapter.principalShares(), IERC20(ST_YBOLD).balanceOf(address(adapter)));
        _runPreflight();
    }

    function _deploy(address yieldManager) internal returns (YBoldYieldVault deployed) {
        deployed = new YBoldYieldVault(
            GOVERNANCE_ADMIN,
            yieldManager,
            WETH,
            USDC,
            BOLD,
            SWAP_ROUTER,
            BOLD_USDC_POOL,
            YBOLD,
            ST_YBOLD,
            ETH_USD_FEED,
            USDC_USD_FEED
        );
    }

    function _depositorAndDeposit(uint256 id)
        internal
        view
        returns (address depositor, IYieldManager.Deposit memory depositData)
    {
        (address owner, IYieldVault vaultAtDeposit, uint256 amount, uint32 unlockTime) = manager.deposits(id);
        depositor = owner;
        depositData = IYieldManager.Deposit({
            depositor: owner, vaultAtDeposit: vaultAtDeposit, amount: amount, unlockTime: unlockTime
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
        (uint80 roundId, int256 answer,,,) = AggregatorV3Interface(feed).latestRoundData();
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
            PYTH, abi.encodeWithSelector(IPythLike.getPriceUnsafe.selector, BOLD_USD_PRICE_ID), abi.encode(price)
        );
    }

    function _runPreflight() internal {
        vm.setEnv("YBOLD_VAULT", vm.toString(address(adapter)));
        vm.setEnv("YBOLD_MIGRATION_ADMIN", vm.toString(GOVERNANCE_ADMIN));
        new YBoldMigrationPreflight().run();
    }
}
