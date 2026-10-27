// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase } from "../ManagerTestBase.t.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ManagerHandoffMock {
    address public destination;
    uint256 public expectedEth;
    uint256 public expiry;
    uint256 public chainId;
    constructor(address target, uint256 amount, uint256 end, uint256 chain) {
        destination = target;
        expectedEth = amount;
        expiry = end;
        chainId = chain;
    }
}
contract ArmLegacyImportTest is ManagerTestBase {
    uint256 internal end;
    function setUp() public override {
        super.setUp();
        end = block.timestamp + 100;
    }
    function _handoff() internal returns (ManagerHandoffMock) {
        return new ManagerHandoffMock(address(manager), 10 ether, block.timestamp + 100, block.chainid);
    }
    function test_OnlyExactCoherentDisabledConfigurationCanArm() public {
        ManagerHandoffMock h = _handoff();
        vm.expectRevert(IYieldManagerV2.Unauthorized.selector);
        manager.armLegacyImport(address(h), 10 ether, end, bytes32(uint256(1)));
        for (uint8 i; i < 4; ++i) {
            ManagerHandoffMock bad = new ManagerHandoffMock(
                i == 0 ? address(pool) : address(manager),
                i == 1 ? 1 : 10 ether,
                i == 2 ? 1 : end,
                i == 3 ? block.chainid + 1 : block.chainid
            );
            vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
            vm.prank(address(safe));
            manager.armLegacyImport(address(bad), 10 ether, end, bytes32(uint256(1)));
        }
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 10 ether, end, bytes32(uint256(1)));
        assertEq(manager.legacyHandoff(), address(h));
        assertEq(manager.legacyWeightVersion(), 1);
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(safe));
        manager.setFutureInvestmentWeights(0, 10_000);
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 10 ether, end, bytes32(uint256(1)));
    }
    function test_ZeroExpiredManifestAndEnabledModesReject() public {
        ManagerHandoffMock h = _handoff();
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 0, end, bytes32(uint256(1)));
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 10 ether, block.timestamp - 1, bytes32(uint256(1)));
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 10 ether, end, bytes32(0));
        _enable();
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 10 ether, end, bytes32(uint256(1)));
        vm.prank(address(safe));
        manager.setIntakeEnabled(false);
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 10 ether, end, bytes32(uint256(1)));
        vm.prank(address(safe));
        manager.recoverBuffers(bytes32(uint256(1)));
        vm.expectRevert(IYieldManagerV2.InvalidImport.selector);
        vm.prank(address(safe));
        manager.armLegacyImport(address(h), 10 ether, end, bytes32(uint256(1)));
    }
}
