// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SebaV2Executor } from "src/v2/SebaV2Executor.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";

import { ExecutorUnitBase } from "../ExecutorUnitBase.sol";

contract ExecutorConstructorTest is ExecutorUnitBase {
    function test_invalidIdentitiesCannotDeploy() public {
        for (uint256 i; i < 13; ++i) {
            IV2Executor.Config memory c = _config();
            assembly {
                mstore(add(c, mul(i, 32)), 0)
            }
            vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
            new SebaV2Executor(c);
        }
        IV2Executor.Config memory same = _config();
        same.manager = same.treasury;
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2Executor(same);
        same = _config();
        same.weth = same.reth;
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2Executor(same);
        usdc.setDecimals(18);
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2Executor(_config());
    }

    function test_invalidAssetGraphCannotDeploy() public {
        yBold.setAsset(address(reth));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2Executor(_config());
        yBold.setAsset(address(bold));
        ysy.setAsset(address(bold));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2Executor(_config());
        ysy.setAsset(address(yBold));
        curve.setCoins(address(reth), address(usdc));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2Executor(_config());
        curve.setCoins(address(bold), address(reth));
        vm.expectRevert(IV2Executor.InvalidConfiguration.selector);
        new SebaV2Executor(_config());
    }
}
