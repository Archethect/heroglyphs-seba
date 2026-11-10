// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../../manager/ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { CowSettlementMock } from "../CowMocks.sol";
abstract contract ManagerCowTestBase is ManagerTestBase {
    function setUp() public override {
        super.setUp();
        _enable();
        _fund(40 ether);
    }
    function _openSource(uint8 source, uint256 amount) internal returns (uint256 id, address escrow) {
        id = cow.nextOrderId();
        escrow = cow.predictEscrow(id);
        vm.prank(operator);
        manager.openCowOrder(source, amount, 1, uint32(block.timestamp + 60), id, bytes32(id));
    }
}
