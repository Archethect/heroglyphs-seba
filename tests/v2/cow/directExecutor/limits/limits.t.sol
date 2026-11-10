// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
contract CowDirectLimitsTest is CowDirectExecutorTestBase {
    function test_limitsPreservesDirectOnlyPolicy() public {
        IV2Executor.Limits memory empty;
        assertEq(abi.encode(direct.limits()), abi.encode(empty));
        _enableDirect();
        assertEq(abi.encode(direct.limits()), abi.encode(_directLimits()));
    }
}
