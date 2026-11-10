// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { HoodiOnlyMock, HoodiPriceFeedMock } from "src/mocks/hoodi/HoodiExternalMocks.sol";

contract HoodiMockChainGateTest is Test {
    function test_RevertWhen_NotHoodi() public {
        vm.chainId(1);
        vm.expectRevert(HoodiOnlyMock.HoodiOnly.selector);
        new HoodiPriceFeedMock(2000e8);
    }

    function test_WhenHoodi() public {
        vm.chainId(560_048);
        HoodiPriceFeedMock feed = new HoodiPriceFeedMock(2000e8);
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        assertEq(answer, 2000e8);
        assertEq(updatedAt, block.timestamp);
    }
}
