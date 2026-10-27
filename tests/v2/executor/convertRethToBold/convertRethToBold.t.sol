// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";

contract ExecutorRethConversionTest is ExecutorUnitBase {
    function test_rETHInputIsConsumedExactlyWithoutNativeBurn() public {
        _enable();
        uint256 beforeReth = reth.balanceOf(address(managerActor));
        uint256 beforeBold = bold.balanceOf(address(managerActor));
        uint256 out = _execute(3, 1 ether, 1, block.timestamp);
        assertEq(beforeReth - reth.balanceOf(address(managerActor)), 1 ether);
        assertEq(bold.balanceOf(address(managerActor)) - beforeBold, out);
        assertEq(out, 3600 ether);
    }
}
