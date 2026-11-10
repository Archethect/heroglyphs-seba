// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
contract CowDirectSetEnabledTest is CowDirectExecutorTestBase {
    function test_setEnabledPreservesDirectOnlyPolicy() public {
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        direct.setEnabled(true);
        vm.prank(address(safe));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        direct.setEnabled(true);
        _enableDirect();
        vm.prank(address(safe));
        direct.setEnabled(false);
        assertFalse(direct.enabled());
    }
}
