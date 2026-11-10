// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../../../manager/ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { CowSettlementMock } from "../../CowMocks.sol";
import { ManagerCowTestBase } from "../ManagerCowTestBase.sol";

contract ManagerCowTestConfigureCowModuleTest is ManagerCowTestBase {
    function test_ModuleBindingRequiresSafePausedReciprocalIdentitiesAndNoActiveOrders() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.configureCowModule(address(cow));
        vm.prank(address(safe));
        vm.expectRevert(IYieldManagerV2.ActiveCowOrders.selector);
        manager.configureCowModule(address(cow));
        (uint256 id, ) = _openSource(0, 1 ether);
        vm.prank(address(safe));
        manager.setExecutionEnabled(false);
        vm.prank(address(safe));
        vm.expectRevert(IYieldManagerV2.ActiveCowOrders.selector);
        manager.configureCowModule(address(cow));
        vm.prank(address(safe));
        manager.finalizeCowOrder(id);
        vm.prank(address(safe));
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        manager.configureCowModule(address(0));
        bytes4[6] memory selectors = [
            ISebaCowIntentModule.manager.selector,
            ISebaCowIntentModule.treasury.selector,
            ISebaCowIntentModule.reth.selector,
            ISebaCowIntentModule.bold.selector,
            ISebaCowIntentModule.weth.selector,
            ISebaCowIntentModule.manager.selector
        ];
        for (uint8 i; i < selectors.length; ++i) {
            vm.mockCall(address(cow), abi.encodeWithSelector(selectors[i]), abi.encode(address(pool)));
            vm.prank(address(safe));
            vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
            manager.configureCowModule(address(cow));
            vm.clearMockedCalls();
        }
        vm.prank(address(safe));
        manager.configureCowModule(address(cow));
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
        vm.prank(address(safe));
        vm.expectRevert(IYieldManagerV2.ActiveCowOrders.selector);
        manager.configureCowModule(address(cow));
    }
}
