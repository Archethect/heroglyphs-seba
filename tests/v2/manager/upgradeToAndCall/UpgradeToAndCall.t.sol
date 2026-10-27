// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

/// @custom:oz-upgrades-from YieldManagerV2
/// @custom:oz-upgrades-unsafe-allow missing-initializer
/// @dev Test-only no-new-state upgrade: intentionally retains the existing initialized storage without reinitializing.
contract ManagerCompatibleUpgrade is YieldManagerV2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}
contract ManagerUpgradeTest is ManagerTestBase {
    function test_OnlySafeUpgradesAndEveryExistingBalanceAndIdentitySurvives() public {
        _enable();
        _fund(40 ether);
        rVault.harvest(0, 3);
        yVault.harvest(1, 7);
        ManagerCompatibleUpgrade next = ManagerCompatibleUpgrade(
            payable(deployCode("UpgradeToAndCall.t.sol:ManagerCompatibleUpgrade"))
        );
        bytes32 digest = _stateDigest();
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        vm.prank(operator);
        manager.upgradeToAndCall(address(next), "");
        vm.prank(address(safe));
        manager.upgradeToAndCall(address(next), "");
        assertEq(ManagerCompatibleUpgrade(payable(address(manager))).version(), 2);
        assertEq(_stateDigest(), digest);
        vm.expectRevert();
        manager.initialize(_configuration());
        vm.expectRevert();
        next.initialize(_configuration());
        vm.prank(operator);
        manager.deployProtocolPrincipal(0, 1 ether, 1, 1, block.timestamp);
        assertEq(rVault.protocolBasis(), 1 ether);
    }
    function _stateDigest() internal view returns (bytes32) {
        bytes32 identities = keccak256(
            abi.encode(
                manager.treasury(),
                manager.sebaPool(),
                manager.vaults(0),
                manager.vaults(1),
                manager.yBold(),
                manager.weth(),
                manager.usdc()
            )
        );
        bytes32 accounting = keccak256(
            abi.encode(
                manager.pendingEth(0),
                manager.pendingEth(1),
                manager.pendingEth(2),
                manager.harvestInventory(0, 0),
                manager.harvestInventory(1, 1)
            )
        );
        bytes32 policy = keccak256(
            abi.encode(
                manager.operators(operator),
                manager.rethBps(),
                manager.ysyBoldBps(),
                manager.weightVersion(),
                address(manager.executor()),
                manager.maximumEth(),
                manager.maximumYieldTokens(0),
                manager.maximumYieldTokens(1),
                manager.intakeEnabled(),
                manager.executionEnabled()
            )
        );
        return keccak256(abi.encode(identities, accounting, policy));
    }
}
