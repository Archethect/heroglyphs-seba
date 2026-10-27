// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
contract SetFutureInvestmentWeightsTest is ManagerTestBase {
    function test_SafeOnlyAndMustSumExactlyToTenThousand() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.setFutureInvestmentWeights(5000, 5000);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(address(safe));
        manager.setFutureInvestmentWeights(1, 1);
        vm.prank(address(safe));
        manager.setFutureInvestmentWeights(10_000, 0);
        assertEq(manager.rethBps(), 10_000);
        assertEq(manager.ysyBoldBps(), 0);
        assertEq(manager.weightVersion(), 2);
    }
}
