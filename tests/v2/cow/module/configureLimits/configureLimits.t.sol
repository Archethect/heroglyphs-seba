// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
import { CowTokenMock, CowSettlementMock } from "../../CowMocks.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { CowModuleTestBase } from "../CowModuleTestBase.sol";

contract CowModuleTestConfigureLimitsTest is CowModuleTestBase {
    function test_AuthoritiesConfigurationAndViews() public {
        vm.expectRevert(I.Unauthorized.selector);
        module.configureLimits(1, 1, 1);
        vm.expectRevert(I.Unauthorized.selector);
        module.setEnabled(false);
        vm.expectRevert(I.Unauthorized.selector);
        module.sweepOrderSurplus(1, address(bold));
        vm.expectRevert(I.Unauthorized.selector);
        vm.prank(safe);
        module.openOrder(0, 1, 1, uint32(block.timestamp + 1), 1, 0);
        vm.expectRevert(I.Unauthorized.selector);
        vm.prank(safe);
        module.closeOrder(1, true);
        (bool ok, ) = address(module).call{ value: 1 }("");
        assertFalse(ok);
        vm.startPrank(safe);
        vm.expectRevert(I.InvalidConfiguration.selector);
        module.configureLimits(1, 1, 1);
        module.setEnabled(false);
        for (uint8 i; i < 5; ++i) {
            vm.expectRevert(I.InvalidConfiguration.selector);
            module.configureLimits(
                i == 0
                    ? 0
                    : i == 1
                        ? type(uint256).max
                        : 1,
                i == 2
                    ? 0
                    : i == 3
                        ? type(uint256).max
                        : 1,
                i == 4 ? 0 : 1
            );
        }
        module.configureLimits(1 ether, 2 ether, 60);
        module.setEnabled(true);
        vm.stopPrank();
        assertTrue(module.enabled());
        assertEq(module.maxWeth(), 1 ether);
        assertEq(module.maxReth(), 2 ether);
        assertEq(module.maxTtl(), 60);
        assertEq(module.manager(), address(this));
        assertEq(module.treasury(), safe);
        assertEq(module.settlement(), address(settlement));
        assertEq(module.relayer(), address(settlement));
        assertEq(module.weth(), address(weth));
        assertEq(module.reth(), address(reth));
        assertEq(module.bold(), address(bold));
        assertEq(module.order(999).escrow, address(0));
        vm.expectRevert(I.InvalidOrder.selector);
        module.orderUid(999);
        vm.expectRevert(I.InvalidOrder.selector);
        module.orderData(999);
        vm.expectRevert(I.ClosedOrder.selector);
        module.closeOrder(999, true);
        vm.prank(safe);
        vm.expectRevert(I.InvalidOrder.selector);
        module.sweepOrderSurplus(999, address(bold));
        SebaCowIntentModule fresh = new SebaCowIntentModule(
            address(this),
            safe,
            address(weth),
            address(reth),
            address(bold),
            address(settlement)
        );
        vm.prank(safe);
        vm.expectRevert(I.InvalidConfiguration.selector);
        fresh.setEnabled(true);
    }
}
