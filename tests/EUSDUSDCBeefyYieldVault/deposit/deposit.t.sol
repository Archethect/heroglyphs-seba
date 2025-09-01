// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { ICurvePool } from "src/vendor/curve/ICurvePool.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DepositTest is BaseTest {
    function test_RevertWhen_NotTheYieldManager(address invocator) external {
        vm.assume(invocator != users.yieldManager);
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                invocator,
                eUsdUsdcBeefyYieldVault.YIELDMANAGER_ROLE()
            )
        );
        resetPrank(invocator);
        eUsdUsdcBeefyYieldVault.deposit();
    }

    function test_RevertWhen_TheValueIsZero() external whenTheYieldManager {
        resetPrank(users.yieldManager);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.NoEthProvided.selector));
        eUsdUsdcBeefyYieldVault.deposit();
    }

    function test_RevertWhen_TheLpMintedIsZero() external whenTheYieldManager whenTheValueIsNotZero {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            contracts.curvePool,
            abi.encodeWithSelector(ICurvePool.add_liquidity.selector),
            abi.encode(0)
        );
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.SlippageExceeded.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_WhenTheLpMintedIsNotZero() external whenTheYieldManager whenTheValueIsNotZero {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        uint256 lpBeforeDeposit = eUsdUsdcBeefyYieldVault.beefy().balanceOf(address(eUsdUsdcBeefyYieldVault));

        // it should emit Deposited
        //vm.expectEmit();
        //emit IEUSDUSDCBeefyYieldVault.Deposited(address(this), 1 ether,0);
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 lpAfterDeposit = eUsdUsdcBeefyYieldVault.beefy().balanceOf(address(eUsdUsdcBeefyYieldVault));
        uint256 pps = beefy.getPricePerFullShare();

        // it should mint new shares
        assertGt(lpAfterDeposit, lpBeforeDeposit);
        // it should increase the principalShares
        assertEq(eUsdUsdcBeefyYieldVault.principalShares(), lpAfterDeposit - lpBeforeDeposit);
        // it should increase the principalValue
        assertEq(eUsdUsdcBeefyYieldVault.principalValue(), (((lpAfterDeposit - lpBeforeDeposit) * pps) / 1e18));
    }
}
