// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { StopperUnitBase } from "../StopperUnitBase.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";

contract StopperClaimYieldTest is StopperUnitBase {
    function test_claimYieldAlwaysReverts() public {
        vm.expectRevert(LegacyIntakeStopper.IntakeStopped.selector);
        stopper.claimYield();
    }
}
