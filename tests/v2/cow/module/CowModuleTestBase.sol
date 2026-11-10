// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { SebaCowOrderEscrow } from "src/v2/cow/SebaCowOrderEscrow.sol";
import { CowTokenMock, CowSettlementMock } from "../CowMocks.sol";
import { ISebaCowIntentModule as I } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

abstract contract CowModuleTestBase is Test {
    CowTokenMock internal weth;
    CowTokenMock internal reth;
    CowTokenMock internal bold;
    CowSettlementMock internal settlement;
    SebaCowIntentModule internal module;
    address internal safe = address(0xBEEF);
    bool internal rejectEth;
    receive() external payable {
        require(!rejectEth, "reject ETH");
    }
    function setUp() public {
        vm.warp(1_000_000);
        vm.etch(safe, hex"00");
        weth = new CowTokenMock();
        reth = new CowTokenMock();
        bold = new CowTokenMock();
        settlement = new CowSettlementMock();
        module = new SebaCowIntentModule(
            address(this),
            safe,
            address(weth),
            address(reth),
            address(bold),
            address(settlement)
        );
        vm.startPrank(safe);
        module.configureLimits(100 ether, 100 ether, 900);
        module.setEnabled(true);
        vm.stopPrank();
        vm.deal(address(this), 1_000 ether);
        reth.mint(address(this), 1_000 ether);
        reth.approve(address(module), 1_000 ether);
    }
    function _open(uint8 source, uint256 amount) internal returns (uint256 id, address escrow) {
        id = module.nextOrderId();
        escrow = module.predictEscrow(id);
        (uint256 actual, address created) = module.openOrder{ value: source < 2 ? amount : 0 }(
            source,
            amount,
            amount,
            uint32(block.timestamp + 60),
            id,
            bytes32(id)
        );
        assertEq(actual, id);
        assertEq(created, escrow);
    }
}
