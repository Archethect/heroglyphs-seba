// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
contract CowDirectInvestYsyBoldTest is CowDirectExecutorTestBase {
    function test_investYsyBoldPreservesDirectOnlyPolicy() public {
        vm.expectRevert(SebaV2DirectExecutor.AsyncOrderRequired.selector);
        direct.investYsyBold(1, block.timestamp);
    }
}
