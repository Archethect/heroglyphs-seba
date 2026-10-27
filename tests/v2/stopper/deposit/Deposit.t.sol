// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { StopperUnitBase } from "../StopperUnitBase.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";

contract StopperDepositTest is StopperUnitBase {
    function test_zeroAndNonzeroDepositsAlwaysRevertWithoutKeepingEth() public {
        for (uint256 value; value < 2; ++value) {
            vm.expectRevert(LegacyIntakeStopper.IntakeStopped.selector);
            stopper.deposit{ value: value }();
            assertEq(address(stopper).balance, 0);
        }
    }

    function test_noReceiveFallbackOrArbitraryExecutionSurface() public {
        (bool ok, ) = address(stopper).call{ value: 1 }("");
        assertFalse(ok);
        (ok, ) = address(stopper).call(abi.encodeWithSignature("sweep(address)", address(this)));
        assertFalse(ok);
        assertEq(address(stopper).balance, 0);
    }
}
