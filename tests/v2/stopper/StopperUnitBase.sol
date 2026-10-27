// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";

abstract contract StopperUnitBase is Test {
    LegacyIntakeStopper internal stopper;

    function setUp() public {
        stopper = new LegacyIntakeStopper();
        vm.deal(address(this), 1 ether);
    }
}
