// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
contract CowModulePredictEscrowTest is CowModuleTestBase {
    function test_predictEscrowPreservesTypedLifecycle() public {
        address predicted = module.predictEscrow(1);
        assertEq(predicted.code.length, 0);
        (, address created) = _open(0, 1 ether);
        assertEq(created, predicted);
        assertTrue(module.predictEscrow(2) != created);
    }
}
