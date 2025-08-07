// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*import { BaseTest } from "tests/Base.t.sol";
import {ISebaYieldVault} from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";

contract DistributeSharesTest is BaseTest {
    function test_RevertWhen_TheCallerIsNotBoostpool(address caller) external {
        vm.assume(caller != contracts.boostPool);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ISebaYieldVault.NotBoostPool.selector, caller));
        resetPrank(caller);
        pybapxEth.distributeShares(caller, 1 ether);
    }

    function test_WhenTheCallerIsBoostpool() external {
        resetPrank(contracts.boostPool);

        // it should emit SharesDistributed
        vm.expectEmit();
        emit ISebaYieldVault.SharesDistributed(users.validator, 1 ether);
        pybapxEth.distributeShares(users.validator, 1 ether);

        // it should mint new shares to the receiver
        assertEq(pybapxEth.balanceOf(users.validator), 1 ether, "shares balance of the receiver should be 1 ether");
        // it should increase the supplyCap with shares
        assertEq(pybapxEth.supplyCap(), 1 ether, "total supplyCap should be 1 ether");
    }
}*/
