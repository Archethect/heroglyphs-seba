// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ActivateYieldFlowTest is BaseTest {
    function test_RevertWhen_NotTheAutomatorRole(address caller) external {
        vm.assume(caller != users.automator);

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                boostPool.AUTOMATOR_ROLE()
            )
        );
        resetPrank(caller);
        yieldManager.activateYieldFlow();
    }

    function test_WhenTheAutomatorRole() external {
        resetPrank(contracts.yieldManager);
        vm.deal(contracts.yieldManager, 1 ether);
        yieldManager.depositFunds{ value: 1 ether }();
        apxETH.setPricePerShare(1.2 ether);

        resetPrank(users.automator);

        // it should emit FundsDeposited
        vm.expectEmit();
        emit IYieldManager.FundsDeposited(0, contracts.yieldManager, 0.198 ether);
        // it should emit YieldFlowActivated
        emit IYieldManager.YieldFlowActivated();
        yieldManager.activateYieldFlow();

        // it should add the pending interest to the yield manager deposit amount
        (, uint128 amount, ) = yieldManager.deposits(0);
        assertEq(amount, 1.188 ether, "amount is not correct");
    }
}*/
