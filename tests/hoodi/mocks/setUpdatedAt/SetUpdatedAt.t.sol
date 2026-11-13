// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { HoodiPriceFeedMock } from "src/mocks/hoodi/HoodiExternalMocks.sol";

contract HoodiPriceFeedUpdateTest is Test {
    address internal constant SAFE = address(0x5AFE);

    function setUp() public {
        vm.chainId(560_048);
    }

    function test_RevertWhen_UpdaterIsZero() public {
        vm.expectRevert(HoodiPriceFeedMock.InvalidUpdater.selector);
        new HoodiPriceFeedMock(2000e8, address(0));
    }

    function test_RevertWhen_UnauthorizedCallerChangesReportTime() public {
        HoodiPriceFeedMock feed = new HoodiPriceFeedMock(2000e8, SAFE);
        vm.prank(address(0xBEEF));
        vm.expectRevert(HoodiPriceFeedMock.UnauthorizedUpdater.selector);
        feed.setUpdatedAt(block.timestamp);
    }

    function test_RevertWhen_ReportTimeIsInFuture() public {
        HoodiPriceFeedMock feed = new HoodiPriceFeedMock(2000e8, SAFE);
        vm.prank(SAFE);
        vm.expectRevert(HoodiPriceFeedMock.FutureReportTime.selector);
        feed.setUpdatedAt(block.timestamp + 1);
    }

    function test_When_SafeRefreshesCurrentAndDeliberatelyStaleReport() public {
        vm.warp(4_000);
        HoodiPriceFeedMock feed = new HoodiPriceFeedMock(2000e8, SAFE);
        assertEq(feed.updater(), SAFE);
        assertEq(feed.updatedAt(), 4_000);
        vm.warp(8_000);
        vm.prank(SAFE);
        feed.setUpdatedAt(4_000);
        assertEq(feed.updatedAt(), 4_000);
        vm.prank(SAFE);
        feed.setUpdatedAt(block.timestamp);
        assertEq(feed.updatedAt(), block.timestamp);
    }
}
