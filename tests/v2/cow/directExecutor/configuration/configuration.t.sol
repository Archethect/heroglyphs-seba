// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
contract CowDirectConfigurationTest is CowDirectExecutorTestBase {
    function test_configurationPreservesDirectOnlyPolicy() public {
        assertEq(abi.encode(direct.configuration()), abi.encode(_directConfig()));
    }
}
