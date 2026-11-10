// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../../../manager/ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { CowSettlementMock } from "../../CowMocks.sol";
import { ManagerCowTestBase } from "../ManagerCowTestBase.sol";

contract ManagerCowTestOpenCowOrderTest is ManagerCowTestBase {
    function test_CustodyAndModuleSpendFaultsCannotDebitAnySource() public {
        vm.deal(address(manager), 39 ether);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        manager.openCowOrder(0, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        vm.deal(address(manager), 40 ether);
        CowSpendFaultModule bad = new CowSpendFaultModule(
            address(manager),
            address(safe),
            address(wethToken),
            address(rethToken),
            address(boldToken)
        );
        vm.startPrank(address(safe));
        manager.setExecutionEnabled(false);
        manager.configureCowModule(address(bad));
        manager.setExecutionEnabled(true);
        vm.stopPrank();
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        manager.openCowOrder(0, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        rVault.harvest(0, 1 ether);
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        manager.openCowOrder(2, 1 ether, 1, uint32(block.timestamp + 60), 1, 0);
        assertEq(manager.pendingEth(0), 20 ether);
        assertEq(manager.harvestInventory(0, 0), 1 ether);
    }
    function test_UnauthorizedInvalidAndDeprecatedPathsReject() public {
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.openCowOrder(0, 1, 1, uint32(block.timestamp + 60), 1, 0);
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        vm.prank(operator);
        manager.openCowOrder(4, 1, 1, uint32(block.timestamp + 60), 1, 0);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        vm.prank(operator);
        manager.openCowOrder(2, 1, 1, uint32(block.timestamp + 60), 1, 0);
        vm.expectRevert(IYieldManagerV2.AsyncOrderRequired.selector);
        vm.prank(operator);
        manager.convertEthRewards(1, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.AsyncOrderRequired.selector);
        vm.prank(operator);
        manager.deployProtocolPrincipal(1, 1, 1, 1, block.timestamp);
        vm.expectRevert(IYieldManagerV2.AsyncOrderRequired.selector);
        vm.prank(operator);
        manager.convertHarvest(0, 0, 1, 1, block.timestamp);
    }

    function test_SourceCapsAndSettlementDeltaFaultsCannotAdvanceAccounting() public {
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        manager.openCowOrder(0, 21 ether, 1, uint32(block.timestamp + 60), 1, 0);
        rVault.harvest(0, 2 ether);
        vm.startPrank(address(safe));
        manager.setExecutionEnabled(false);
        manager.configureExecution(address(execution), 100 ether, 1 ether, 100 ether);
        manager.setExecutionEnabled(true);
        vm.stopPrank();
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidAmount.selector);
        manager.openCowOrder(2, 2 ether, 1, uint32(block.timestamp + 60), 1, 0);
        (uint256 id, ) = _openSource(0, 1 ether);
        vm.mockCall(
            address(cow),
            abi.encodeCall(cow.closeOrder, (id, false)),
            abi.encode(uint8(0), 1 ether, true, uint256(0), 1 ether)
        );
        vm.prank(operator);
        vm.expectRevert(IYieldManagerV2.InvalidTokenDelta.selector);
        manager.finalizeCowOrder(id);
        assertEq(manager.pendingBold(), 0);
        assertEq(cow.activeCount(), 1);
        vm.clearMockedCalls();
    }
}

/// @notice Test-only authenticated module faults; this is not an alternate production route.
contract CowSpendFaultModule {
    address public manager;
    address public treasury;
    address public weth;
    address public reth;
    address public bold;
    constructor(address m, address s, address w, address r, address b) {
        manager = m;
        treasury = s;
        weth = w;
        reth = r;
        bold = b;
    }
    function activeCount() external pure returns (uint256) {
        return 0;
    }
    function openOrder(
        uint8 source,
        uint256,
        uint256,
        uint32,
        uint256 id,
        bytes32
    ) external payable returns (uint256, address) {
        if (source < 2) {
            (bool ok, ) = manager.call{ value: 1 }("");
            require(ok);
        }
        return (id, address(this));
    }
}
