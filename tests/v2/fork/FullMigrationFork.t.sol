// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { StackForkBase } from "./StackForkBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LegacyProtocolPrincipalHandoff } from "src/v2/LegacyProtocolPrincipalHandoff.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";
import { YieldManager } from "src/YieldManager.sol";
import { SebaPool } from "src/SebaPool.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";

interface IMigrationAdapter {
    function principalValue() external view returns (uint256);
    function principalShares() external view returns (uint256);
    function beefy() external view returns (address);
}
interface IMigrationSafe {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function nonce() external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
    function getTransactionHash(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce_
    ) external view returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool);
}

contract FullMigrationForkTest is StackForkBase {
    address internal constant MULTISEND = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
    LegacyProtocolPrincipalHandoff internal handoff;
    LegacyIntakeStopper internal stopper;
    uint256 internal quotedEth;
    function _prepareHandoff() internal {
        _prepareHandoffWithRouterEthCap(0);
    }
    function _prepareHandoffWithRouterEthCap(uint256 approvedCap) internal {
        IMigrationAdapter adapter = IMigrationAdapter(address(old.yieldVault()));
        // Stage A is a SEPARATE real Safe transaction: exit first, stop legacy intake, retain ETH in old manager.
        stopper = new LegacyIntakeStopper();
        assertTrue(
            _safeTransaction(
                abi.encodeWithSignature(
                    "multiSend(bytes)",
                    _call(address(old), abi.encodeCall(YieldManager.setYieldVault, (address(stopper))))
                )
            )
        );
        assertEq(old.principalValue(), 0);
        assertEq(address(old.yieldVault()), address(stopper));
        quotedEth = address(old).balance;
        ILegacyProtocolPrincipalHandoff.Configuration memory c;
        c.oldManager = address(old);
        c.destination = address(manager);
        c.treasury = SAFE;
        c.pool = address(pool);
        c.oldVault = address(adapter);
        c.stagingVault = address(stopper);
        c.oldRouter = address(old.router());
        c.expectedEth = quotedEth;
        c.expiry = block.timestamp + 15 minutes;
        c.oldPrincipal = old.principalValue();
        c.oldDepositId = old.depositId();
        c.adapterPrincipal = adapter.principalValue();
        c.adapterShares = adapter.principalShares();
        c.actualBeefyShares = IERC20(adapter.beefy()).balanceOf(address(adapter));
        c.oldIdleEth = address(old).balance;
        c.safeOwnersHash = keccak256(abi.encode(IMigrationSafe(SAFE).getOwners()));
        c.safeThreshold = IMigrationSafe(SAFE).getThreshold();
        c.rethBps = manager.rethBps();
        c.manifest = keccak256("local fork reviewed exact migration manifest");
        c.maximumRouterEth = approvedCap;
        handoff = new LegacyProtocolPrincipalHandoff(c);
        assertEq(manager.legacyHandoff(), address(0)); // No irreversible standalone arm before signatures are ready.
    }
    function _call(address target, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), target, uint256(0), uint256(data.length), data);
    }
    function _batch(bool correctPostPointer) internal view returns (bytes memory data) {
        ILegacyProtocolPrincipalHandoff.Configuration memory c = handoff.configuration();
        bytes memory calls = bytes.concat(
            _call(
                address(manager),
                abi.encodeCall(manager.armLegacyImport, (address(handoff), c.expectedEth, c.expiry, c.manifest))
            ),
            _call(address(handoff), abi.encodeCall(handoff.assertPreMigration, ()))
        );
        calls = bytes.concat(
            calls,
            _call(address(old), abi.encodeCall(YieldManager.setYieldVault, (address(handoff)))),
            _call(address(old), abi.encodeCall(YieldManager.depositPrincipalIntoYieldVault, ()))
        );
        calls = bytes.concat(
            calls,
            _call(address(manager), abi.encodeCall(YieldManagerV2.setIntakeEnabled, (true))),
            _call(
                address(pool),
                abi.encodeCall(SebaPool.setYieldManager, (correctPostPointer ? address(manager) : address(old)))
            ),
            _call(address(handoff), abi.encodeCall(handoff.assertPostMigration, ()))
        );
        return abi.encodeWithSignature("multiSend(bytes)", calls);
    }
    function _safeTransaction(bytes memory data) internal returns (bool) {
        // Verified against Safe's official deployment registry; no custom proxy/executor.
        assertEq(MULTISEND.codehash, 0xa9865ac2d9c7a1591619b188c4d88167b50df6cc0c5327fcbd1c8c75f7c066ad);
        IMigrationSafe safe = IMigrationSafe(SAFE);
        assertEq(safe.getThreshold(), 3);
        address[] memory owners = safe.getOwners();
        for (uint256 i; i < owners.length; ++i)
            for (uint256 j = i + 1; j < owners.length; ++j)
                if (owners[j] < owners[i]) (owners[i], owners[j]) = (owners[j], owners[i]);
        bytes32 txHash = safe.getTransactionHash(MULTISEND, 0, data, 1, 0, 0, 0, address(0), address(0), safe.nonce());
        bytes memory signatures;
        for (uint256 i; i < 3; ++i) {
            // LOCAL IMPERSONATION, not real owner signatures/production approval.
            vm.prank(owners[i]);
            safe.approveHash(txHash);
            signatures = bytes.concat(
                signatures,
                abi.encodePacked(bytes32(uint256(uint160(owners[i]))), bytes32(0), uint8(1))
            );
        }
        return safe.execTransaction(MULTISEND, 0, data, 1, 0, 0, 0, address(0), payable(address(0)), signatures);
    }
    function test_RealThreeOfSevenSafeTwoStageExitThenAtomicImportAndBothProtocolCredits() public {
        _prepareHandoff();
        uint256 expected = handoff.expectedEth();
        uint256 unassigned = address(manager).balance;
        assertGt(expected, 1 ether);
        assertTrue(_safeTransaction(_batch(true)));
        assertEq(address(pool.yieldManager()), address(manager));
        assertEq(old.principalValue(), 0);
        assertEq(address(old.yieldVault()), address(handoff));
        assertEq(address(old).balance, 0);
        assertTrue(handoff.used());
        assertTrue(manager.legacyImported());
        assertEq(manager.pendingEth(0), 0);
        assertEq(manager.pendingEth(1) + manager.pendingEth(2), expected);
        assertEq(address(manager).balance, expected + unassigned);
        assertEq(IMigrationSafe(SAFE).getThreshold(), 3);
        _enableTestExecution();
        vm.startPrank(operator);
        manager.deployProtocolPrincipal(0, manager.pendingEth(1), 1, 1, block.timestamp + 60);
        manager.deployProtocolPrincipal(1, manager.pendingEth(2), 1, 1, block.timestamp + 60);
        vm.stopPrank();
        assertGt(rVault.bucket(1).basis, 0);
        assertGt(yVault.bucket(1).basis, 0);
        assertEq(manager.pendingEth(1) + manager.pendingEth(2), 0);
        _assertManagerCustody();
        emit log_named_uint("Actual legacy ETH wei imported, NO synthetic capital", expected);
        emit log_named_uint("rETH protocol basis ETH wei", rVault.bucket(1).basis);
        emit log_named_uint("ysyBOLD protocol basis yBOLD atoms", yVault.bucket(1).basis);
        emit log_named_uint(
            "Legacy adapter native principal residue",
            IMigrationAdapter(handoff.configuration().oldVault).principalValue()
        );
        emit log_named_uint(
            "Legacy adapter share residue",
            IMigrationAdapter(handoff.configuration().oldVault).principalShares()
        );
    }
    function test_WrongFinalPointerRollsBackStageBButPreservesAlreadyExitedEthAndStopper() public {
        _prepareHandoff();
        uint256 oldPV = old.principalValue();
        address vault = address(old.yieldVault());
        uint256 unassigned = address(manager).balance;
        uint256 parkedEth = address(old).balance;
        // Stage B rolls back, including its arming. It DOES NOT undo the already executed Stage A exit.
        vm.expectRevert(bytes("GS013"));
        this.executeWrongPointerForTest();
        assertEq(address(pool.yieldManager()), address(old));
        assertEq(address(old.yieldVault()), vault);
        assertEq(old.principalValue(), oldPV);
        assertFalse(manager.legacyImported());
        assertFalse(handoff.used());
        assertEq(address(manager).balance, unassigned);
        assertEq(manager.legacyHandoff(), address(0));
        assertEq(address(old).balance, parkedEth);
    }
    function test_RealSafeStageBAllowsApprovedInjectedRouterDustButLeavesItUnmigrated() public {
        _prepareHandoffWithRouterEthCap(1);
        // Fault injection on the real mainnet fork: no real account or router balance is changed.
        vm.deal(address(old.router()), 1);
        assertTrue(_safeTransaction(_batch(true)));
        assertEq(address(pool.yieldManager()), address(manager));
        assertTrue(handoff.used());
        assertEq(address(old).balance, 0);
        assertEq(address(old.router()).balance, 1);
        assertEq(manager.pendingEth(1) + manager.pendingEth(2), quotedEth);
    }
    function test_RealSafeStageBRejectsInjectedRouterDustAboveApprovedCap() public {
        _prepareHandoffWithRouterEthCap(1);
        vm.deal(address(old.router()), 2); // Fork-local fault injection, not actual mainnet surplus.
        uint256 parkedEth = address(old).balance;
        vm.expectRevert(bytes("GS013"));
        this.executeCorrectForTest();
        assertEq(address(pool.yieldManager()), address(old));
        assertEq(address(old).balance, parkedEth);
        assertEq(address(old.yieldVault()), address(stopper));
        assertFalse(handoff.used());
        assertFalse(manager.legacyImported());
    }
    function test_StageABlocksNewLegacyDepositsAndPermissionlessSweepsUntilStageB() public {
        _prepareHandoff();
        uint256 parkedEth = address(old).balance;
        uint256 oldId = old.depositId();
        vm.deal(address(this), 1 ether);
        vm.expectRevert(LegacyIntakeStopper.IntakeStopped.selector);
        old.depositFunds{ value: 1 ether }();
        vm.deal(address(pool), 1 ether); // Synthetic input only for this deliberately reverting test.
        vm.expectRevert(LegacyIntakeStopper.IntakeStopped.selector);
        pool.sweepRewards();
        assertEq(address(old).balance, parkedEth);
        assertEq(old.depositId(), oldId);
        assertEq(address(pool).balance, 1 ether);
        assertEq(
            address(manager).balance - manager.pendingEth(0) - manager.pendingEth(1) - manager.pendingEth(2),
            address(manager).balance
        );
    }
    function executeWrongPointerForTest() external {
        require(msg.sender == address(this));
        _safeTransaction(_batch(false));
    }
    function executeCorrectForTest() external {
        require(msg.sender == address(this));
        _safeTransaction(_batch(true));
    }
}
