// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerCowTestBase } from "../ManagerCowTestBase.sol";
contract CowManagerUpgradeStateTest is ManagerCowTestBase {
    function test_LiveOrderAndSettledPrincipalStorageSurviveAuthorizedUpgrade() public {
        (uint256 first, address principal) = _openSource(1, 1 ether);
        cowSettlement.fill(principal, address(wethToken), address(boldToken), 1 ether, 10 ether);
        vm.prank(operator);
        manager.finalizeCowOrder(first);
        (uint256 second, address reward) = _openSource(0, 2 ether);
        bytes32 beforeState = keccak256(
            abi.encode(
                address(manager.cowModule()),
                manager.pendingProtocolBold(),
                manager.pendingEth(0),
                manager.pendingEth(2),
                cow.order(second),
                cow.activeCount(),
                cow.orderUid(second)
            )
        );
        address next = deployCode("YieldManagerV2.sol:YieldManagerV2");
        vm.prank(address(safe));
        manager.upgradeToAndCall(next, "");
        assertEq(
            keccak256(
                abi.encode(
                    address(manager.cowModule()),
                    manager.pendingProtocolBold(),
                    manager.pendingEth(0),
                    manager.pendingEth(2),
                    cow.order(second),
                    cow.activeCount(),
                    cow.orderUid(second)
                )
            ),
            beforeState
        );
        cowSettlement.fill(reward, address(wethToken), address(boldToken), 2 ether, 3 ether);
        vm.prank(operator);
        manager.finalizeCowOrder(second);
        assertEq(manager.pendingProtocolBold(), 10 ether);
        assertEq(manager.pendingBold(), 3 ether);
        assertEq(cow.activeCount(), 0);
    }
}
