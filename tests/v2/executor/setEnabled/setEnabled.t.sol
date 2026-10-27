// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";

contract ExecutorEnableTest is ExecutorUnitBase {
    function test_disableDoesNotReconfigureOrMoveClassifiedFunds() public {
        _enable();
        uint256 managerBefore = reth.balanceOf(address(managerActor));
        vm.prank(address(safe));
        executor.setEnabled(false);
        _expect(0, IV2Executor.ExecutionDisabled.selector);
        assertEq(reth.balanceOf(address(managerActor)), managerBefore);
        vm.prank(address(safe));
        executor.setEnabled(true);
        assertGt(_execute(0, 1 ether, 1, block.timestamp), 0);
    }
}
