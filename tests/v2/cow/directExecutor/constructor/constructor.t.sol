// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ExecutorUnitBase } from "../../../executor/ExecutorUnitBase.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { CowDirectExecutorTestBase } from "../CowDirectExecutorTestBase.sol";

contract CowDirectExecutorTestConstructorTest is CowDirectExecutorTestBase {
    function test_ConstructorValidatesEveryIdentityUnusedVenueAndAssetEdge() public {
        for (uint256 i; i < 13; ++i) {
            IV2Executor.Config memory c = _directConfig();
            bool used = i < 4 || i == 5 || i == 6 || i == 7 || i == 12;
            address value = used ? address(0) : address(safe);
            assembly ("memory-safe") {
                mstore(add(c, mul(i, 32)), value)
            }
            vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
            new SebaV2DirectExecutor(c);
        }
        IV2Executor.Config memory c = _directConfig();
        c.manager = c.treasury;
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2DirectExecutor(c);
        c = _directConfig();
        c.weth = c.reth;
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2DirectExecutor(c);
        reth.setDecimals(6);
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2DirectExecutor(_directConfig());
        reth.setDecimals(18);
        yBold.setAsset(address(reth));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2DirectExecutor(_directConfig());
        yBold.setAsset(address(bold));
        ysy.setAsset(address(bold));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2DirectExecutor(_directConfig());
    }
}
