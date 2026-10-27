// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { StopperUnitBase } from "../StopperUnitBase.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";

contract StopperRetrievePrincipalTest is StopperUnitBase {
    function testFuzz_principalRetrievalAlwaysReverts(uint256 amount) public {
        vm.expectRevert(LegacyIntakeStopper.IntakeStopped.selector);
        stopper.retrievePrincipal(amount);
    }
}
