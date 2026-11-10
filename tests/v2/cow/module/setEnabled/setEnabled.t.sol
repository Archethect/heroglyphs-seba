// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowModuleTestBase } from "../CowModuleTestBase.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
contract CowModuleSetEnabledTest is CowModuleTestBase {
    function test_setEnabledPreservesTypedLifecycle() public {
        vm.prank(safe);
        module.setEnabled(false);
        assertFalse(module.enabled());
        vm.prank(safe);
        module.setEnabled(true);
        assertTrue(module.enabled());
    }
}
