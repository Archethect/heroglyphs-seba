// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
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
    function test_RevertWhenConfigValidatorIsInvalid() external {
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        new YBoldYieldVault(address(0));

        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.InvalidContract.selector, stranger));
        new YBoldYieldVault(stranger);
    }

    function test_InitializesValidatedConfigurationAndSeparatedRoles() external view {
        assertTrue(vault.hasRole(vault.ADMIN_ROLE(), admin));
        assertTrue(vault.hasRole(vault.YIELDMANAGER_ROLE(), address(manager)));
        assertTrue(vault.hasRole(vault.UPGRADER_ROLE(), upgrader));
        assertTrue(vault.hasRole(vault.RECOVERY_ROLE(), recoveryTreasury));
        assertFalse(vault.hasRole(vault.UPGRADER_ROLE(), admin));
        assertEq(vault.getRoleAdmin(vault.ADMIN_ROLE()), vault.ADMIN_ROLE());
        assertEq(vault.getRoleAdmin(vault.YIELDMANAGER_ROLE()), vault.UPGRADER_ROLE());
        assertEq(vault.getRoleAdmin(vault.UPGRADER_ROLE()), vault.UPGRADER_ROLE());
        assertEq(vault.getRoleAdmin(vault.RECOVERY_ROLE()), vault.UPGRADER_ROLE());
        assertEq(vault.WETH(), address(weth));
        assertEq(vault.USDC(), address(usdc));
        assertEq(vault.BOLD(), address(bold));
        assertEq(address(vault.yBold()), address(yBold));
        assertEq(address(vault.stYBold()), address(stYBold));
        assertEq(vault.recoveryTreasury(), recoveryTreasury);
        assertEq(vault.wethUsdcSlippageBps(), 50);
        assertEq(vault.boldUsdcSlippageBps(), 50);
        assertEq(vault.maxBoldPegDeviationBps(), 100);
        assertEq(vault.normalYearnMaxLossBps(), 0);
        assertEq(vault.emergencyYearnMaxLossBps(), 100);
    }

    function test_RevertWhenImplementationIsInitialized() external {
        YBoldYieldVault implementation = new YBoldYieldVault(address(configValidator));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(_initializationParams(address(manager)));
    }

    function test_RevertWhenProxyIsReinitialized() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(_initializationParams(address(manager)));
    }

    function test_RevertWhenRequiredAuthorityIsZero() external {
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(address(manager));
        params.admin = address(0);
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        this.deployProxyForTest(params);

        params = _initializationParams(address(manager));
        params.yieldManager = address(0);
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        this.deployProxyForTest(params);

        params = _initializationParams(address(manager));
        params.upgradeAuthority = address(0);
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        this.deployProxyForTest(params);

        params = _initializationParams(address(manager));
        params.recoveryTreasury = address(0);
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        this.deployProxyForTest(params);
    }

    function test_RevertWhenAuthorityOrDependencyHasNoCode() external {
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(address(manager));
        params.upgradeAuthority = stranger;
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.InvalidContract.selector, stranger));
        this.deployProxyForTest(params);

        params = _initializationParams(address(manager));
        params.weth = stranger;
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.InvalidContract.selector, stranger));
        this.deployProxyForTest(params);
    }

    function test_RevertWhenDependencyIsZero() external {
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(address(manager));
        params.weth = address(0);
        vm.expectRevert(IYBoldYieldVault.InvalidAddress.selector);
        this.deployProxyForTest(params);
    }

    function test_RevertWhenTokenDecimalsAreWrong() external {
        MockToken wrongWeth = new MockToken("Wrong WETH", "WWETH", 17);
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(address(manager));
        params.weth = address(wrongWeth);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.InvalidDecimals.selector, address(wrongWeth), uint8(18), uint8(17))
        );
        this.deployProxyForTest(params);
    }

    function test_RevertWhenCurveCoinOrderIsWrong() external {
        MockCurveStableSwapNG reversedCurve = new MockCurveStableSwapNG(address(usdc), address(bold));
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(address(manager));
        params.boldUsdcPool = address(reversedCurve);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidAsset.selector,
                address(reversedCurve),
                address(bold),
                address(usdc)
            )
        );
        this.deployProxyForTest(params);
    }

    function test_RevertWhenYBoldAssetIsWrong() external {
        MockToken wrongAsset = new MockToken("Wrong Asset", "WRONG", 18);
        MockYearnVault wrongYBold = new MockYearnVault(IERC20(address(wrongAsset)), "Wrong", "WRONG");
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(address(manager));
        params.yearnBold = address(wrongYBold);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidAsset.selector,
                address(wrongYBold),
                address(bold),
                address(wrongAsset)
            )
        );
        this.deployProxyForTest(params);
    }

    function test_RevertWhenStYBoldAssetIsWrong() external {
        MockYearnVault wrongStYBold = new MockYearnVault(IERC20(address(bold)), "Wrong", "WRONG");
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(address(manager));
        params.stakedYearnBold = address(wrongStYBold);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidAsset.selector,
                address(wrongStYBold),
                address(yBold),
                address(bold)
            )
        );
        this.deployProxyForTest(params);
    }

    function test_RevertWhenEitherOracleDecimalsExceed18() external {
        MockAggregator invalidFeed = new MockAggregator(19, 1e18);
        IYBoldYieldVault.InitializationParams memory params = _initializationParams(address(manager));
        params.ethUsd = address(invalidFeed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidDecimals.selector,
                address(invalidFeed),
                uint8(18),
                uint8(19)
            )
        );
        this.deployProxyForTest(params);

        params = _initializationParams(address(manager));
        params.usdcUsd = address(invalidFeed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYBoldYieldVault.InvalidDecimals.selector,
                address(invalidFeed),
                uint8(18),
                uint8(19)
            )
        );
        this.deployProxyForTest(params);
    }
}
