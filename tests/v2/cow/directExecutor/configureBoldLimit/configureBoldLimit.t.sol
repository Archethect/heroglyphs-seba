// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
contract CowDirectConfigureBoldLimitTest is CowDirectExecutorTestBase {
    function test_configureBoldLimitPreservesDirectOnlyPolicy() public {
        vm.expectRevert(IV2Executor.Unauthorized.selector);
        direct.configureBoldLimit(1);
        vm.startPrank(address(safe));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        direct.configureBoldLimit(0);
        direct.configureBoldLimit(7);
        vm.stopPrank();
        assertEq(direct.maximumBold(), 7);
    }
}
