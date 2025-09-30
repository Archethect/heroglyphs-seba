// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IPYBSeba } from "src/interfaces/IPYBSeba.sol";

contract DistributeSharesTest is BaseTest {
    function test_RevertWhen_TheCallerIsNotBoostpool(address caller) external {
        vm.assume(caller != contracts.sebaPool);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPYBSeba.NotSebaPool.selector, caller));
        resetPrank(caller);
        pybSeba.distributeShares(caller, 1 ether);
    }

    function test_WhenTheCallerIsBoostpool() external {
        resetPrank(contracts.sebaPool);

        // it should emit SharesDistributed
        vm.expectEmit();
        emit IPYBSeba.SharesDistributed(users.validator, 1 ether);
        pybSeba.distributeShares(users.validator, 1 ether);

        // it should mint new shares to the receiver
        assertEq(pybSeba.balanceOf(users.validator), 1 ether, "shares balance of the receiver should be 1 ether");
        // it should increase the supply with 1 ethers in shares
        assertEq(pybSeba.totalSupply(), 1.000000000000000001 ether, "total supply should be 1.000000000000000001 ether");
    }
}
