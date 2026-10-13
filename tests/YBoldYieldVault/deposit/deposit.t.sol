// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";
import { MockAggregator } from "tests/mocks/MockYBoldIntegrations.sol";

contract YBoldDepositTest is YBoldYieldVaultTestBase {
    function test_RevertWhenExistingPrincipalIsUnderwater() external {
        _deposit(1 ether);
        stYBold.simulateLoss(stYBold.totalAssets() / 2);

        vm.expectRevert(IYBoldYieldVault.StrategyUnderwater.selector);
        _deposit(1 ether);
    }

    function test_YearnShareRoundingDustDoesNotBlockNewDeposit() external {
        _deposit(1 ether);
        stYBold.simulateLoss(2);

        uint256 secondValue = _deposit(1 ether);
        assertGt(secondValue, 0);
    }

    function test_AcceptedBoldPegDoesNotContradictSwapMinimum() external {
        curve.setOraclePrice(0.992e18);
        curve.setOutputBps(9920);

        uint256 principal = _deposit(1 ether);
        manager.retrieve(address(vault), principal);
        assertGt(address(manager).balance, 0.98 ether);

        curve.setOutputBps(9849);
        vm.expectRevert(bytes("CURVE_SLIPPAGE"));
        _deposit(1 ether);
    }

    function test_RevertWhenCallerIsNotYieldManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                vault.YIELDMANAGER_ROLE()
            )
        );
        vault.deposit{ value: 1 ether }();
    }

    function test_RevertWhenValueIsZero() external {
        vm.expectRevert(IYBoldYieldVault.NoEthProvided.selector);
        manager.deposit(address(vault));
    }

    function test_RevertWhenPausedOrEmergencyModeIsActive() external {
        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();
        vm.deal(address(this), 2 ether);
        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        manager.deposit{ value: 1 ether }(address(vault));

        vm.startPrank(admin);
        vault.unpause();
        vault.setEmergencyMode(true);
        vm.stopPrank();
        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        manager.deposit{ value: 1 ether }(address(vault));
    }

    function test_RevertWhenEitherYearnVaultIsUnavailable() external {
        yBold.setShutdown(true);
        vm.deal(address(this), 2 ether);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.StrategyUnavailable.selector, address(yBold), 1, 0));
        manager.deposit{ value: 1 ether }(address(vault));

        yBold.setShutdown(false);
        stYBold.setDepositLimit(0);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.StrategyUnavailable.selector, address(stYBold), 1, 0));
        manager.deposit{ value: 1 ether }(address(vault));
    }

    function test_RevertWhenOracleRoundIsInvalidOrStale() external {
        vm.deal(address(this), 3 ether);
        ethUsdFeed.setRound(2, 0, block.timestamp, 2);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.OracleInvalid.selector, address(ethUsdFeed)));
        manager.deposit{ value: 1 ether }(address(vault));

        ethUsdFeed.setRound(2, 2000e8, block.timestamp, 1);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.OracleInvalid.selector, address(ethUsdFeed)));
        manager.deposit{ value: 1 ether }(address(vault));

        uint256 staleTimestamp = block.timestamp - 1 hours - 1;
        ethUsdFeed.setRound(2, 2000e8, staleTimestamp, 2);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.OracleStale.selector, address(ethUsdFeed), staleTimestamp)
        );
        manager.deposit{ value: 1 ether }(address(vault));
    }

    function test_RevertWhenBoldPegIsOutsideLimit() external {
        curve.setOraclePrice(0.98e18);
        vm.deal(address(this), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.BoldPegDeviationExceeded.selector, 0.98e18, uint256(100))
        );
        manager.deposit{ value: 1 ether }(address(vault));
    }

    function test_RevertAtomicallyWhenEitherSwapBreaksItsMinimum() external {
        vm.deal(address(this), 2 ether);
        router.setOutputBps(9900);
        vm.expectRevert(bytes("TOO_LITTLE_RECEIVED"));
        manager.deposit{ value: 1 ether }(address(vault));
        assertEq(vault.principalValue(), 0);

        router.setOutputBps(10_000);
        curve.setOutputBps(9849);
        vm.expectRevert(bytes("CURVE_SLIPPAGE"));
        manager.deposit{ value: 1 ether }(address(vault));
        assertEq(vault.principalValue(), 0);
    }

    function test_RevertWhenPostSwapYearnCapacityIsInsufficient() external {
        yBold.setDepositLimit(1e18);
        vm.deal(address(this), 2 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.StrategyUnavailable.selector, address(yBold), 2000e18, 1e18)
        );
        manager.deposit{ value: 1 ether }(address(vault));

        yBold.setDepositLimit(type(uint256).max);
        stYBold.setDepositLimit(1e18);
        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.StrategyUnavailable.selector, address(stYBold), 2000e18, 1e18)
        );
        manager.deposit{ value: 1 ether }(address(vault));
    }

    function test_RevertWhenConversionReturnsZero() external {
        vm.deal(address(this), 1);
        vm.expectRevert(IYBoldYieldVault.ZeroOutput.selector);
        manager.deposit{ value: 1 }(address(vault));
    }

    function test_RevertWhenYearnMintsNoShares() external {
        yBold.setDepositReturnsZero(true);
        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.NoSharesMinted.selector, address(yBold)));
        manager.deposit{ value: 1 ether }(address(vault));
    }

    function test_RevertWhenOracleScaleWouldOverflow() external {
        MockAggregator overflowingFeed = new MockAggregator(0, type(int256).max);
        YBoldYieldVault overflowVault = new YBoldYieldVault(
            admin,
            address(manager),
            address(weth),
            address(usdc),
            address(bold),
            address(router),
            address(curve),
            address(yBold),
            address(stYBold),
            address(overflowingFeed),
            address(usdcUsdFeed)
        );

        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IYBoldYieldVault.OracleInvalid.selector, address(overflowingFeed)));
        manager.deposit{ value: 1 ether }(address(overflowVault));
    }

    function testFuzz_DepositsEthIntoStYBold(uint96 ethAmount) external {
        ethAmount = uint96(bound(ethAmount, 0.01 ether, 100 ether));

        uint256 value = _deposit(ethAmount);

        uint256 expectedValue = Math.mulDiv(uint256(ethAmount), 2000e6, 1e18) * 1e12;
        assertEq(value, expectedValue);
        assertEq(vault.principalValue(), value);
        assertEq(vault.principalShares(), stYBold.balanceOf(address(vault)));
        assertGt(vault.principalShares(), 0);
        assertEq(IERC20(address(weth)).allowance(address(vault), address(router)), 0);
        assertEq(IERC20(address(usdc)).allowance(address(vault), address(curve)), 0);
        assertEq(IERC20(address(bold)).allowance(address(vault), address(yBold)), 0);
        assertEq(IERC20(address(yBold)).allowance(address(vault), address(stYBold)), 0);
    }
}
