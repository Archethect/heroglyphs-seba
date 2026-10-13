// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";
import {
    MockAggregator,
    MockCurveStableSwapNG,
    MockToken,
    MockYearnVault
} from "tests/mocks/MockYBoldIntegrations.sol";

contract YBoldConstructorTest is YBoldYieldVaultTestBase {
    function test_InitializesValidatedConfigurationAndRoles() external view {
        assertTrue(vault.hasRole(vault.ADMIN_ROLE(), admin));
        assertTrue(vault.hasRole(vault.YIELDMANAGER_ROLE(), address(manager)));
        assertEq(vault.getRoleAdmin(vault.ADMIN_ROLE()), vault.ADMIN_ROLE());
        assertEq(vault.getRoleAdmin(vault.YIELDMANAGER_ROLE()), vault.ADMIN_ROLE());
        assertEq(vault.WETH(), address(weth));
        assertEq(vault.USDC(), address(usdc));
        assertEq(vault.BOLD(), address(bold));
        assertEq(address(vault.yBold()), address(yBold));
        assertEq(address(vault.stYBold()), address(stYBold));
        assertEq(vault.wethUsdcSlippageBps(), 50);
        assertEq(vault.boldUsdcSlippageBps(), 50);
        assertEq(vault.maxBoldPegDeviationBps(), 100);
        assertEq(vault.normalYearnMaxLossBps(), 0);
        assertEq(vault.emergencyYearnMaxLossBps(), 100);
    }

    function test_RevertWhenAdminIsZero() external {
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        new YBoldYieldVault(
            address(0),
            address(manager),
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

    function test_RevertWhenYieldManagerIsZero() external {
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        new YBoldYieldVault(
            admin,
            address(0),
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

    function test_RevertWhenDependencyHasNoCode() external {
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.InvalidContract.selector, stranger));
        new YBoldYieldVault(
            admin,
            stranger,
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

    function test_RevertWhenDependencyIsZero() external {
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        new YBoldYieldVault(
            admin,
            address(manager),
            address(0),
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

    function test_RevertWhenTokenDecimalsAreWrong() external {
        MockToken wrongWeth = new MockToken("Wrong WETH", "WWETH", 17);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.InvalidDecimals.selector, address(wrongWeth), uint8(18), uint8(17))
        );
        new YBoldYieldVault(
            admin,
            address(manager),
            address(wrongWeth),
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

    function test_RevertWhenCurveCoinOrderIsWrong() external {
        MockCurveStableSwapNG reversedCurve = new MockCurveStableSwapNG(address(usdc), address(bold));
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidAsset.selector, address(reversedCurve), address(bold), address(usdc)
            )
        );
        new YBoldYieldVault(
            admin,
            address(manager),
            address(weth),
            address(usdc),
            address(bold),
            address(router),
            address(reversedCurve),
            address(yBold),
            address(stYBold),
            address(ethUsdFeed),
            address(usdcUsdFeed)
        );
    }

    function test_RevertWhenYBoldAssetIsWrong() external {
        MockToken wrongAsset = new MockToken("Wrong Asset", "WRONG", 18);
        MockYearnVault wrongYBold = new MockYearnVault(IERC20(address(wrongAsset)), "Wrong", "WRONG");
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidAsset.selector, address(wrongYBold), address(bold), address(wrongAsset)
            )
        );
        new YBoldYieldVault(
            admin,
            address(manager),
            address(weth),
            address(usdc),
            address(bold),
            address(router),
            address(curve),
            address(wrongYBold),
            address(stYBold),
            address(ethUsdFeed),
            address(usdcUsdFeed)
        );
    }

    function test_RevertWhenStYBoldAssetIsWrong() external {
        MockYearnVault wrongStYBold = new MockYearnVault(IERC20(address(bold)), "Wrong", "WRONG");
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidAsset.selector, address(wrongStYBold), address(yBold), address(bold)
            )
        );
        new YBoldYieldVault(
            admin,
            address(manager),
            address(weth),
            address(usdc),
            address(bold),
            address(router),
            address(curve),
            address(yBold),
            address(wrongStYBold),
            address(ethUsdFeed),
            address(usdcUsdFeed)
        );
    }

    function test_RevertWhenOracleDecimalsExceed18() external {
        MockAggregator invalidFeed = new MockAggregator(19, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidDecimals.selector, address(invalidFeed), uint8(18), uint8(19)
            )
        );
        new YBoldYieldVault(
            admin,
            address(manager),
            address(weth),
            address(usdc),
            address(bold),
            address(router),
            address(curve),
            address(yBold),
            address(stYBold),
            address(invalidFeed),
            address(usdcUsdFeed)
        );
    }

    function test_RevertWhenUsdcOracleDecimalsExceed18() external {
        MockAggregator invalidFeed = new MockAggregator(19, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidDecimals.selector, address(invalidFeed), uint8(18), uint8(19)
            )
        );
        new YBoldYieldVault(
            admin,
            address(manager),
            address(weth),
            address(usdc),
            address(bold),
            address(router),
            address(curve),
            address(yBold),
            address(stYBold),
            address(ethUsdFeed),
            address(invalidFeed)
        );
    }
}
