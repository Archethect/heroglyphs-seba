// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { VaultBaseTest, VaultMockToken, VaultMockBalances, VaultMockManager } from "../VaultBase.t.sol";
import { RethSupporterVault } from "../../../../src/v2/RethSupporterVault.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";

/// @dev Funded, approved actors and bounded inputs. Expected no-op transitions return rather than discarding reverts.
contract VaultInvariantHandler is Test {
    RethSupporterVault public vault;
    VaultMockToken public token;
    VaultMockBalances public rate;
    VaultMockManager public coordinator;
    address public safe;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401)];
    uint256 public deposits;
    uint256 public withdrawals;
    uint256 public harvests;
    uint256 public repairs;
    uint256 public rateChanges;
    uint256 public recoveries;

    constructor(RethSupporterVault v, VaultMockToken t, VaultMockBalances r, VaultMockManager m, address s) {
        vault = v;
        token = t;
        rate = r;
        coordinator = m;
        safe = s;
    }
    function bootstrap() external {
        enter(0, 10 ether, false);
        enter(1, 20 ether, false);
        enter(0, 15 ether, true);
    }
    function enter(uint256 who, uint256 seed, bool protocol) public {
        if (vault.recoveryState() != IV2SupporterVault.RecoveryState.Normal || !vault.entriesEnabled()) return;
        (, uint256 sd, , ) = vault.accounting(0);
        (, uint256 pd, , ) = vault.accounting(1);
        if (sd != 0 || pd != 0) return;
        uint256 q = bound(seed, 1 ether, 1e24);
        address owner = protocol ? address(coordinator) : actors[who % 3];
        token.mint(owner, q);
        rate.setReport(block.timestamp, block.number);
        vm.startPrank(owner);
        token.approve(address(vault), q);
        if (protocol) vault.depositProtocol(q, 0, block.timestamp);
        else vault.deposit(q, 0, block.timestamp);
        vm.stopPrank();
        deposits++;
    }
    function exit(uint256 seed, bool protocol) public {
        IV2SupporterVault.RecoveryState state = vault.recoveryState();
        if (state != IV2SupporterVault.RecoveryState.Normal && state != IV2SupporterVault.RecoveryState.Settlement)
            return;
        if (protocol) {
            uint256 b = vault.bucket(1).basis;
            if (b == 0) return;
            // Full protocol exit avoids zero-atom ordinary withdrawals; supporter IDs remain independent.
            vm.prank(safe);
            vault.withdrawProtocol(b, 0, block.timestamp);
        } else {
            uint256 boundary = vault.nextPositionId();
            if (boundary <= 1) return;
            uint256 id = 1 + (seed % (boundary - 1));
            IV2SupporterVault.Position memory p = vault.position(id);
            if (p.closed) return;
            if (block.timestamp < p.unlockAt) vm.warp(p.unlockAt);
            vm.prank(p.owner);
            vault.withdraw(id, 0, block.timestamp);
        }
        withdrawals++;
    }
    function changeRate(uint256 seed) public {
        // Synthetic report movements intentionally model losses followed by repairs/growth.
        rate.setRate(bound(seed, 0.5 ether, 2 ether), 1 ether);
        rate.setReport(block.timestamp, block.number);
        rateChanges++;
    }
    function collect(uint8 seed, uint256 maxSeed) public {
        if (vault.recoveryState() != IV2SupporterVault.RecoveryState.Normal || !vault.harvestEnabled()) return;
        uint8 which = seed % 2;
        rate.setReport(block.timestamp, block.number);
        uint256 bBefore = vault.bucket(which).basis;
        vm.prank(safe);
        vault.collectYield(which, bound(maxSeed, 1, 1e24));
        assertEq(vault.bucket(which).basis, bBefore, "harvest debited principal basis");
        harvests++;
    }
    function donateRepair(uint8 seed, uint256 qSeed) public {
        if (vault.recoveryState() != IV2SupporterVault.RecoveryState.Normal) return;
        uint256 q = bound(qSeed, 1 ether, 1e24);
        token.mint(actors[2], q);
        vm.startPrank(actors[2]);
        token.approve(address(vault), q);
        vault.repair(seed % 2, q);
        vm.stopPrank();
        repairs++;
    }
    function pause(bool entry, bool harvest) public {
        if (vault.recoveryState() != IV2SupporterVault.RecoveryState.Normal) return;
        vm.startPrank(safe);
        vault.configureEntry(1, entry);
        vault.configureHarvest(type(uint256).max, harvest);
        vm.stopPrank();
    }
    function recover(uint256 percentage) public {
        if (
            deposits + withdrawals + harvests + repairs + rateChanges < 12 ||
            vault.recoveryState() != IV2SupporterVault.RecoveryState.Normal
        ) return;
        vm.prank(safe);
        vault.beginRecovery(keccak256("invariant custody evidence"));
        for (uint8 i; i < 2; ++i) {
            uint256 q = vault.recoveryBucket(i).exportedTokens;
            if (q != 0) {
                vm.startPrank(safe);
                token.approve(address(vault), q);
                vault.fundRecovery(i, q);
                vm.stopPrank();
            }
        }
        uint256[2] memory caps = vault.recoveryCaps();
        uint256 pct = bound(percentage, 0, 100);
        uint256[2] memory budgets = [(caps[0] * pct) / 100, (caps[1] * pct) / 100];
        vm.prank(safe);
        vault.activateSettlement(budgets, keccak256("invariant final classification"));
        recoveries++;
    }
    function finish() public {
        if (
            vault.recoveryState() != IV2SupporterVault.RecoveryState.Settlement ||
            vault.bucket(0).basis != 0 ||
            vault.bucket(1).basis != 0
        ) return;
        vm.prank(safe);
        vault.finalizeRecovery();
    }
    function assertConservation() external view {
        uint256 known = token.balanceOf(address(vault)) + token.balanceOf(address(coordinator)) + token.balanceOf(safe);
        for (uint256 i; i < 3; ++i) known += token.balanceOf(actors[i]);
        assertEq(known, token.totalSupply(), "token custody escaped the fixed recipients");
        uint256 openBasis;
        uint256 closedBasis;
        for (uint256 i = 1; i < vault.nextPositionId(); ++i) {
            IV2SupporterVault.Position memory entry = vault.position(i);
            if (!entry.closed) openBasis += entry.basis;
            else closedBasis += entry.basis;
        }
        IV2SupporterVault.Bucket memory s = vault.bucket(0);
        IV2SupporterVault.Bucket memory p = vault.bucket(1);
        assertEq(s.basis, openBasis, "supporter basis diverged from open IDs");
        assertEq(s.removedBasis, closedBasis, "closed claim accounting drift");
        assertEq(s.enteredBasis - s.removedBasis, s.basis, "supporter nominal basis drift");
        assertEq(p.enteredBasis - p.removedBasis, p.basis, "protocol nominal basis drift");
        uint256 held = token.balanceOf(address(vault));
        if (vault.recoveryState() == IV2SupporterVault.RecoveryState.Normal) {
            assertEq(held, s.tokens + p.tokens, "ordinary accounted custody drift");
        } else if (vault.recoveryState() != IV2SupporterVault.RecoveryState.Settled) {
            IV2SupporterVault.RecoveryBucket memory rs = vault.recoveryBucket(0);
            IV2SupporterVault.RecoveryBucket memory rp = vault.recoveryBucket(1);
            assertEq(
                held,
                rs.returnedTokens +
                    rs.repairTokens -
                    rs.paidTokens +
                    rp.returnedTokens +
                    rp.repairTokens -
                    rp.paidTokens,
                "settlement custody drift"
            );
            assertLe(rs.paidTokens, rs.budget, "supporter fixed budget overspent");
            assertLe(rp.paidTokens, rp.budget, "protocol fixed budget overspent");
            assertEq(rs.closedBasis, rs.snapshot.basis - s.basis, "supporter recovery claim duplication");
            assertEq(rp.closedBasis, rp.snapshot.basis - p.basis, "protocol recovery claim duplication");
        } else assertEq(held, 0, "terminal custody stranded");
    }
}

contract VaultStatefulInvariantTest is VaultBaseTest {
    VaultInvariantHandler internal handler;
    function setUp() public override {
        super.setUp();
        handler = new VaultInvariantHandler(vault, token, balances, coordinator, address(safe));
        handler.bootstrap();
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.enter.selector;
        selectors[1] = handler.exit.selector;
        selectors[2] = handler.changeRate.selector;
        selectors[3] = handler.collect.selector;
        selectors[4] = handler.donateRepair.selector;
        selectors[5] = handler.pause.selector;
        selectors[6] = handler.recover.selector;
        selectors[7] = handler.finish.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }
    function invariant_CustodyBasisAndFixedBudgetsReconcileAcrossMixedActions() external view {
        handler.assertConservation();
    }
    function test_NegativeControl_TheSameInvariantDetectsAnInjectedCustodyLeak() external {
        handler.assertConservation();
        token.burn(address(vault), 1);
        vm.expectRevert();
        handler.assertConservation();
    }
    function test_HandlerReachesRealMixedTransitionsInsteadOfOnlyNoOps() external {
        handler.changeRate(2 ether);
        handler.collect(0, 1 ether);
        handler.exit(0, false);
        handler.donateRepair(0, 1 ether);
        handler.pause(false, false);
        handler.pause(true, true);
        handler.enter(2, 3 ether, false);
        handler.changeRate(1 ether);
        handler.donateRepair(1, 5 ether);
        handler.changeRate(2 ether);
        handler.collect(1, 1 ether);
        handler.recover(80);
        assertGt(handler.deposits(), 3);
        assertGt(handler.harvests(), 0);
        assertGt(handler.withdrawals(), 0);
        assertGt(handler.repairs(), 0);
        assertEq(handler.recoveries(), 1);
        handler.assertConservation();
        assertEq(uint256(vault.recoveryState()), 2);
    }
}
