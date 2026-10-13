// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";

contract YBoldClaimYieldTest is YBoldYieldVaultTestBase {
    function test_RevertWhenCallerIsNotYieldManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), vault.YIELDMANAGER_ROLE()
            )
        );
        vault.claimYield();
    }

    function test_ReturnsWithoutRealizingWhenYieldFlowIsInactive() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        manager.setYieldFlowActive(false);
        uint256 sharesBefore = vault.principalShares();

        manager.claim(address(vault));

        assertEq(vault.principalShares(), sharesBefore);
        assertGt(vault.claimableYield(), 99e18);
        assertEq(address(manager).balance, 0);
    }

    function test_ReturnsWithoutRealizingWhenThereIsNoYieldOrOnlyDust() external {
        _deposit(1 ether);
        manager.claim(address(vault));
        assertEq(address(manager).balance, 0);

        _donateStYBoldYield(1e11);
        manager.claim(address(vault));
        assertEq(address(manager).balance, 0);
        assertGt(vault.claimableYield(), 0);
    }

    function test_ReturnsWhenYieldRoundsToZeroShares() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        stYBold.setConvertToSharesReturnsZero(true);
        uint256 sharesBefore = vault.principalShares();

        manager.claim(address(vault));

        assertEq(vault.principalShares(), sharesBefore);
        assertEq(address(manager).balance, 0);
    }

    function test_RevertWhenPausedOrEmergencyModeIsActive() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        vm.prank(admin);
        vault.pause();
        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        manager.claim(address(vault));

        vm.startPrank(admin);
        vault.unpause();
        vault.setEmergencyMode(true);
        vm.stopPrank();
        vm.expectRevert(IYBoldYieldVault.StrategyNotOperational.selector);
        manager.claim(address(vault));
    }

    function test_RealizesOnlyUnlockedYieldAndKeepsPrincipalAccounting() external {
        uint256 depositedValue = _deposit(1 ether);
        _donateStYBoldYield(100e18);
        uint256 sharesBefore = vault.principalShares();

        manager.claim(address(vault));

        assertEq(vault.principalValue(), depositedValue);
        assertLt(vault.principalShares(), sharesBefore);
        assertLt(vault.claimableYield(), 2);
        assertGt(address(manager).balance, 0.049 ether);
        assertEq(stYBold.lastMaxLoss(), 0);
        assertEq(yBold.lastMaxLoss(), 0);
        assertEq(IERC20(address(yBold)).allowance(address(vault), address(stYBold)), 0);
        assertEq(IERC20(address(bold)).allowance(address(vault), address(curve)), 0);
        assertEq(IERC20(address(usdc)).allowance(address(vault), address(router)), 0);
    }

    function test_ClaimableYieldFloorsAtZeroAfterLoss() external {
        _deposit(1 ether);
        uint256 loss = IERC20(address(yBold)).balanceOf(address(stYBold)) / 2;
        vm.prank(address(stYBold));
        assertTrue(IERC20(address(yBold)).transfer(address(0xBEEF), loss));

        assertEq(vault.claimableYield(), 0);
        manager.claim(address(vault));
        assertEq(address(manager).balance, 0);
    }

    function test_RevertAtomicallyWhenStYBoldLiquidityIsInsufficient() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        uint256 sharesToRedeem = stYBold.convertToShares(vault.claimableYield());
        stYBold.setRedeemLimit(0);
        uint256 sharesBefore = vault.principalShares();

        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.InsufficientLiquidity.selector, address(stYBold), sharesToRedeem, 0)
        );
        manager.claim(address(vault));

        assertEq(vault.principalShares(), sharesBefore);
        assertEq(address(manager).balance, 0);
    }

    function test_RevertAtomicallyWhenYBoldLiquidityIsInsufficient() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        uint256 sharesToRedeem = stYBold.convertToShares(vault.claimableYield());
        uint256 yBoldToRedeem = stYBold.previewRedeem(sharesToRedeem);
        yBold.setRedeemLimit(0);
        uint256 sharesBefore = vault.principalShares();

        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.InsufficientLiquidity.selector, address(yBold), yBoldToRedeem, 0)
        );
        manager.claim(address(vault));

        assertEq(vault.principalShares(), sharesBefore);
        assertEq(address(manager).balance, 0);
    }

    function test_RevertAtomicallyWhenExitPegCheckFails() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        curve.setOraclePrice(1.02e18);
        uint256 sharesBefore = vault.principalShares();

        vm.expectRevert(
            abi.encodeWithSelector(IYBoldYieldVault.BoldPegDeviationExceeded.selector, 1.02e18, uint256(100))
        );
        manager.claim(address(vault));

        assertEq(vault.principalShares(), sharesBefore);
        assertEq(address(manager).balance, 0);
    }

    function test_RevertWhenYearnRedemptionReturnsZero() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        stYBold.setCustomRedeem(true, 0);

        vm.expectRevert(IYBoldYieldVault.ZeroOutput.selector);
        manager.claim(address(vault));
    }

    function test_RevertWhenRedeemedBoldIsBelowUsdcPrecision() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        yBold.setCustomRedeem(true, 1);

        vm.expectRevert(IYBoldYieldVault.ZeroOutput.selector);
        manager.claim(address(vault));
    }

    function test_RevertWhenCurveReturnsZero() external {
        _deposit(1 ether);
        _donateStYBoldYield(100e18);
        curve.setReturnZero(true);

        vm.expectRevert(IYBoldYieldVault.ZeroOutput.selector);
        manager.claim(address(vault));
    }
}
