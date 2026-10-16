// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldConfigValidator } from "src/YBoldConfigValidator.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import {
    MockAggregator,
    MockAuthority,
    MockCurveStableSwapNG,
    MockSwapRouter,
    MockToken,
    MockWeth,
    MockYBoldYieldManager,
    MockYearnVault
} from "tests/mocks/MockYBoldIntegrations.sol";

abstract contract YBoldYieldVaultTestBase is Test {
    address internal admin;
    address internal upgrader;
    address internal recoveryTreasury;
    address internal stranger = makeAddr("stranger");

    MockWeth internal weth;
    MockToken internal usdc;
    MockToken internal bold;
    MockSwapRouter internal router;
    MockCurveStableSwapNG internal curve;
    MockYearnVault internal yBold;
    MockYearnVault internal stYBold;
    MockAggregator internal ethUsdFeed;
    MockAggregator internal usdcUsdFeed;
    MockYBoldYieldManager internal manager;
    YBoldConfigValidator internal configValidator;
    YBoldYieldVault internal vault;

    function setUp() public virtual {
        admin = address(new MockAuthority());
        upgrader = address(new MockAuthority());
        recoveryTreasury = address(new MockAuthority());
        weth = new MockWeth();
        usdc = new MockToken("USD Coin", "USDC", 6);
        bold = new MockToken("BOLD", "BOLD", 18);
        router = new MockSwapRouter(address(weth), address(usdc));
        curve = new MockCurveStableSwapNG(address(bold), address(usdc));
        yBold = new MockYearnVault(IERC20(address(bold)), "Yearn BOLD", "yBOLD");
        stYBold = new MockYearnVault(IERC20(address(yBold)), "Staked yBOLD", "st-yBOLD");
        ethUsdFeed = new MockAggregator(8, 2000e8);
        usdcUsdFeed = new MockAggregator(8, 1e8);
        manager = new MockYBoldYieldManager();
        configValidator = new YBoldConfigValidator();

        vault = _deploy(address(manager));
        _fundIntegrations();
    }

    function _deploy(address yieldManager) internal returns (YBoldYieldVault deployed) {
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(yieldManager);
        deployed = _deploy(params);
    }

    function _deploy(IYBoldYieldVault.InitializationParams memory params) internal returns (YBoldYieldVault deployed) {
        YBoldYieldVault implementation = new YBoldYieldVault(address(configValidator));
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(YBoldYieldVault.initialize, (params))
        );
        deployed = YBoldYieldVault(payable(address(proxy)));
    }

    function deployProxyForTest(
        IYBoldYieldVault.InitializationParams memory params
    ) external returns (YBoldYieldVault deployed) {
        deployed = _deploy(params);
    }

    function _initializationParams(
        address yieldManager
    ) internal view returns (IYBoldYieldVault.InitializationParams memory params) {
        params = IYBoldYieldVault.InitializationParams({
            admin: admin,
            yieldManager: yieldManager,
            upgradeAuthority: upgrader,
            recoveryTreasury: recoveryTreasury,
            weth: address(weth),
            usdc: address(usdc),
            bold: address(bold),
            router: address(router),
            boldUsdcPool: address(curve),
            yearnBold: address(yBold),
            stakedYearnBold: address(stYBold),
            ethUsd: address(ethUsdFeed),
            usdcUsd: address(usdcUsdFeed)
        });
    }

    function _fundIntegrations() internal {
        usdc.mint(address(router), 20_000_000e6);
        usdc.mint(address(curve), 20_000_000e6);
        bold.mint(address(curve), 20_000_000e18);
        vm.deal(address(router), 10_000 ether);
        vm.prank(address(router));
        weth.deposit{ value: 10_000 ether }();
    }

    function _deposit(uint256 amount) internal returns (uint256 value) {
        vm.deal(address(this), amount);
        value = manager.deposit{ value: amount }(address(vault));
    }

    function _donateStYBoldYield(uint256 amount) internal {
        bold.mint(address(this), amount);
        bold.approve(address(yBold), amount);
        uint256 shares = yBold.deposit(amount, address(this));
        assertTrue(IERC20(address(yBold)).transfer(address(stYBold), shares));
    }
}
