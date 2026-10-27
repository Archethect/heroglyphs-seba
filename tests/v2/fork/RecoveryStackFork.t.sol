// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { StackForkBase } from "./StackForkBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IV2SupporterVault } from "src/interfaces/v2/IV2SupporterVault.sol";
import { RethSupporterVault } from "src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "src/v2/YsyBoldSupporterVault.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";

/// @notice Same-token real-asset emergency settlement. Simulated losses/outages are explicitly labelled.
contract RecoveryStackForkTest is StackForkBase {
    address internal alice;
    address internal bob;
    uint256[2] internal aliceIds;
    uint256[2] internal bobIds;
    uint256[2] internal closedIds;
    function _seed() internal {
        _enableTestExecution();
        vm.startPrank(SAFE);
        manager.setIntakeEnabled(true);
        pool.setYieldManager(address(manager));
        vm.stopPrank();
        // Synthetic local pool rewards fund PROTOCOL fixture capital only, not a par-liquidation claim.
        vm.deal(address(pool), 4 ether);
        pool.sweepRewards();
        vm.startPrank(operator);
        manager.deployProtocolPrincipal(0, 1 ether, 1, 1, block.timestamp + 60);
        manager.deployProtocolPrincipal(1, 1 ether, 1, 1, block.timestamp + 60);
        vm.stopPrank();
        alice = makeAddr("recovery alice");
        bob = makeAddr("recovery bob");
        address carol = makeAddr("already withdrawn carol");
        (aliceIds[0], ) = _nativeDeposit(rVault, alice, 10 ether);
        (bobIds[0], ) = _nativeDeposit(rVault, bob, 10 ether);
        (aliceIds[1], ) = _nativeDeposit(yVault, alice, 50_000 ether);
        (bobIds[1], ) = _nativeDeposit(yVault, bob, 50_000 ether);
        (closedIds[0], ) = _nativeDeposit(rVault, carol, 1 ether);
        (closedIds[1], ) = _nativeDeposit(yVault, carol, 1_000 ether);
        vm.warp(block.timestamp + 30 days);
        vm.startPrank(carol);
        rVault.withdraw(closedIds[0], 1, block.timestamp);
        yVault.withdraw(closedIds[1], 1, block.timestamp);
        vm.stopPrank();
    }
    function _upgradePreservingLiveStorage() internal {
        bytes32 beforeState = keccak256(
            abi.encode(
                rVault.bucket(0),
                rVault.bucket(1),
                yVault.bucket(0),
                yVault.bucket(1),
                rVault.position(aliceIds[0]),
                yVault.position(bobIds[1])
            )
        );
        address ri = deployCode("RethSupporterVault.sol:RethSupporterVault");
        address yi = deployCode("YsyBoldSupporterVault.sol:YsyBoldSupporterVault");
        address mi = deployCode("YieldManagerV2.sol:YieldManagerV2");
        uint256 pending = manager.pendingEth(0);
        vm.startPrank(SAFE);
        rVault.upgradeToAndCall(ri, "");
        yVault.upgradeToAndCall(yi, "");
        manager.upgradeToAndCall(mi, "");
        vm.stopPrank();
        assertEq(
            keccak256(
                abi.encode(
                    rVault.bucket(0),
                    rVault.bucket(1),
                    yVault.bucket(0),
                    yVault.bucket(1),
                    rVault.position(aliceIds[0]),
                    yVault.position(bobIds[1])
                )
            ),
            beforeState
        );
        assertEq(manager.pendingEth(0), pending);
        assertEq(manager.treasury(), SAFE);
    }
    function _recoverAndFund(bool partialLoss) internal {
        // Fault-injected venue failures. Native custody export MUST NOT redeem, swap, burn or require USD feeds.
        vm.mockCallRevert(RETH, abi.encodeWithSignature("burn(uint256)"), "injected native burn outage");
        vm.mockCallRevert(
            YSY,
            abi.encodeWithSignature("redeem(uint256,address,address,uint256)"),
            "injected Yearn redemption outage"
        );
        vm.mockCallRevert(
            execution.configuration().curvePool,
            abi.encodeWithSignature("exchange(int128,int128,uint256,uint256)"),
            "injected unusable Curve"
        );
        vm.mockCallRevert(
            execution.configuration().ethUsdFeed,
            abi.encodeWithSignature("latestRoundData()"),
            "injected stale USD feed"
        );
        vm.startPrank(SAFE);
        rVault.beginRecovery(keccak256("rETH initial published snapshot"));
        yVault.beginRecovery(keccak256("ysy initial published snapshot"));
        vm.stopPrank();
        assertFalse(rVault.entriesEnabled());
        assertFalse(yVault.harvestEnabled());
        for (uint8 leg; leg < 2; ++leg) {
            IV2SupporterVault v = leg == 0 ? IV2SupporterVault(address(rVault)) : IV2SupporterVault(address(yVault));
            uint256[2] memory caps = leg == 0 ? rVault.recoveryCaps() : yVault.recoveryCaps();
            uint256[2] memory budgets;
            vm.startPrank(SAFE);
            IERC20(v.asset()).approve(address(v), type(uint256).max);
            for (uint8 bucket; bucket < 2; ++bucket) {
                uint256 exported = v.recoveryBucket(bucket).exportedTokens;
                uint256 returned = partialLoss ? (exported * 9) / 10 : exported;
                budgets[bucket] = partialLoss ? (caps[bucket] * 9) / 10 : caps[bucket];
                // Withholding 10% is an explicit synthetic treasury-loss scenario, NOT observed mainnet liquidation loss.
                v.fundRecovery(bucket, returned);
            }
            v.activateSettlement(budgets, keccak256(abi.encode("final public budget", leg, partialLoss)));
            vm.stopPrank();
        }
    }
    function _settle(bool reverse) internal returns (uint256[4] memory payouts) {
        for (uint8 leg; leg < 2; ++leg) {
            IV2SupporterVault v = leg == 0 ? IV2SupporterVault(address(rVault)) : IV2SupporterVault(address(yVault));
            uint256 aid = aliceIds[leg];
            uint256 bid = bobIds[leg];
            uint256 aExpected = (v.recoveryBucket(0).budget * v.position(aid).basis) /
                v.recoveryBucket(0).snapshot.basis;
            uint256 bExpected = (v.recoveryBucket(0).budget * v.position(bid).basis) /
                v.recoveryBucket(0).snapshot.basis;
            if (reverse) {
                vm.prank(bob);
                payouts[leg * 2 + 1] = v.withdraw(bid, 1, block.timestamp);
                vm.prank(alice);
                payouts[leg * 2] = v.withdraw(aid, 1, block.timestamp);
            } else {
                vm.prank(alice);
                payouts[leg * 2] = v.withdraw(aid, 1, block.timestamp);
                vm.prank(bob);
                payouts[leg * 2 + 1] = v.withdraw(bid, 1, block.timestamp);
            }
            assertEq(payouts[leg * 2], aExpected);
            assertEq(payouts[leg * 2 + 1], bExpected);
            vm.expectRevert(IV2SupporterVault.ClosedPosition.selector);
            vm.prank(alice);
            v.withdraw(aid, 0, block.timestamp);
            vm.expectRevert(IV2SupporterVault.ClosedPosition.selector);
            vm.prank(makeAddr("already withdrawn carol"));
            v.withdraw(closedIds[leg], 0, block.timestamp);
            uint256 principal = v.bucket(1).basis;
            vm.prank(SAFE);
            v.withdrawProtocol(principal, 0, block.timestamp);
            assertEq(v.bucket(0).basis + v.bucket(1).basis, 0);
            assertEq(v.recoveryBucket(0).closedBasis, v.recoveryBucket(0).snapshot.basis);
            assertEq(v.recoveryBucket(1).closedBasis, v.recoveryBucket(1).snapshot.basis);
            vm.prank(SAFE);
            v.finalizeRecovery();
            assertEq(IERC20(v.asset()).balanceOf(address(v)), 0);
        }
    }
    function test_RealNativeFullBudgetRecoveryAfterAuthorizedUpgrades() public {
        _seed();
        _upgradePreservingLiveStorage();
        _recoverAndFund(false);
        _settle(false);
        _assertManagerCustody();
    }
    function test_ExplicitTenPercentTokenLossFixedBudgetsIndependentOfUserOrder() public {
        _seed();
        _recoverAndFund(true);
        uint256 snapshot = vm.snapshot();
        uint256[4] memory first = _settle(false);
        assertTrue(vm.revertTo(snapshot));
        uint256[4] memory reversed = _settle(true);
        assertEq(keccak256(abi.encode(first)), keccak256(abi.encode(reversed)));
        _assertManagerCustody();
    }
    function test_ManagerRetirementDoesNotBlockLeafSettlementOrTerminalYieldReconciliation() public {
        _seed();
        _recoverAndFund(false);
        vm.prank(SAFE);
        manager.recoverBuffers(keccak256("manager buffer retirement"));
        _settle(false);
        _assertManagerCustody();
        uint256 carry = manager.harvestInventory(0, 0) +
            manager.harvestInventory(0, 1) +
            manager.harvestInventory(1, 0) +
            manager.harvestInventory(1, 1);
        assertGt(carry, 0);
        vm.prank(SAFE);
        manager.recoverBuffers(keccak256("new terminal carry reconciliation"));
        assertEq(
            manager.harvestInventory(0, 0) +
                manager.harvestInventory(0, 1) +
                manager.harvestInventory(1, 0) +
                manager.harvestInventory(1, 1),
            0
        );
    }
}
