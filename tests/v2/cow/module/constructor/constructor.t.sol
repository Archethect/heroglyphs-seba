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

contract CowModuleTestConstructorTest is CowModuleTestBase {
    function test_ConstructorRejectsEachInvalidIdentityAndTokenGraph() public {
        for (uint8 i; i < 6; ++i) {
            vm.expectRevert();
            new SebaCowIntentModule(
                i == 0 ? address(0) : address(this),
                i == 1 ? address(0) : safe,
                address(weth),
                i == 2 ? address(weth) : address(reth),
                i == 3
                    ? address(weth)
                    : i == 4
                        ? address(reth)
                        : address(bold),
                i == 5 ? address(0) : address(settlement)
            );
        }
        weth.setDecimals(6);
        vm.expectRevert();
        new SebaCowIntentModule(address(this), safe, address(weth), address(reth), address(bold), address(settlement));
        weth.setDecimals(18);
        reth.setDecimals(6);
        vm.expectRevert();
        new SebaCowIntentModule(address(this), safe, address(weth), address(reth), address(bold), address(settlement));
        reth.setDecimals(18);
        bold.setDecimals(6);
        vm.expectRevert();
        new SebaCowIntentModule(address(this), safe, address(weth), address(reth), address(bold), address(settlement));
        bold.setDecimals(18);
        settlement.setRelayer(address(1));
        vm.expectRevert(I.InvalidConfiguration.selector);
        new SebaCowIntentModule(address(this), safe, address(weth), address(reth), address(bold), address(settlement));
        settlement.setRelayer(address(0));
        settlement.setDomain(0);
        vm.expectRevert(I.InvalidConfiguration.selector);
        new SebaCowIntentModule(address(this), safe, address(weth), address(reth), address(bold), address(settlement));
    }
}
