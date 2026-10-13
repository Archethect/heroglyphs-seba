// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import {
    MockAggregator,
    MockCurveStableSwapNG,
    MockSwapRouter,
    MockToken,
    MockWeth,
    MockYBoldYieldManager,
    MockYearnVault
} from "tests/mocks/MockYBoldIntegrations.sol";

abstract contract YBoldYieldVaultTestBase is Test {
    address internal admin = makeAddr("admin");
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
    YBoldYieldVault internal vault;

    function setUp() public virtual {
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

        vault = _deploy(address(manager));
        _fundIntegrations();
    }

    function _deploy(address yieldManager) internal returns (YBoldYieldVault deployed) {
        deployed = new YBoldYieldVault(
            admin,
            yieldManager,
            address(weth),
            address(usdc),
            address(bold),
            address(router),
            address(curve),
            address(yBold),
            address(stYBold),
            address(ethUsdFeed),
            address(usdcUsdFeed)
        );
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
