// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SetSlippageBpsTest is BaseTest {
    function test_RevertWhen_NotTheAdmin(address invocator) external {
        vm.assume(invocator != users.admin);
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                invocator,
                eUsdUsdcBeefyYieldVault.ADMIN_ROLE()
            )
        );
        resetPrank(invocator);
        eUsdUsdcBeefyYieldVault.setSlippageBps(0);
    }

    function test_RevertWhen_TheBpsToBeSetIsBiggerThan10Percent() external whenTheAdmin {
        resetPrank(users.admin);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.SlippageTooHigh.selector));
        eUsdUsdcBeefyYieldVault.setSlippageBps(1001);
    }

    function test_WhenTheBpsToBeSetIsNotBiggerThan10Percent() external whenTheAdmin {
        resetPrank(users.admin);

        // it should emit SlippageSet
        vm.expectEmit();
        emit IEUSDUSDCBeefyYieldVault.SlippageSet(1000);
        eUsdUsdcBeefyYieldVault.setSlippageBps(1000);

        // it should set the new slippage bps
        assertEq(eUsdUsdcBeefyYieldVault.slippageBps(), 1000);
    }
}
