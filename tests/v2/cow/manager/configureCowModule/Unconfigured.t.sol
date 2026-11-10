// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../../../manager/ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { CowSettlementMock } from "../../CowMocks.sol";

contract CowUnconfiguredManagerTest is ManagerTestBase {
    function test_UnboundModuleAndZeroWethCannotBeUsed() public {
        _bind();
        vm.startPrank(address(safe));
        manager.configureExecution(address(execution), 100 ether, 100 ether, 100 ether);
        manager.setExecutionEnabled(true);
        manager.setIntakeEnabled(true);
        vm.stopPrank();
        _fund(1 ether);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        manager.openCowOrder(0, 1, 1, uint32(block.timestamp + 1), 1, 0);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        manager.finalizeCowOrder(1);
    }
}
