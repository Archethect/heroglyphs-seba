// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IV2SupporterVault } from "src/interfaces/v2/IV2SupporterVault.sol";
import { IExecutorRocketPool, IExecutorRocketStorage } from "src/vendor/v2/IExecutorProtocols.sol";
import { MockBold } from "src/mocks/MockBold.sol";
import { HoodiYearnMock } from "src/mocks/hoodi/HoodiExternalMocks.sol";
import { HoodiCowSettlementMock } from "src/mocks/hoodi/HoodiExternalMocks.sol";
import { RethSupporterVault } from "src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "src/v2/YsyBoldSupporterVault.sol";
import { SebaPool } from "src/SebaPool.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";

/// @title Public Hoodi V2 Phase 6 fork drills
/// @author Seba contributors
/// @notice Fork-only drills against the exact public Hoodi V2 deployment after both protocol legs were invested.
/// @dev Safe calls below use Foundry impersonation, not a public Safe signature. No public-chain state is changed.
contract HoodiPublicPhase6DrillsForkTest is Test {
    uint256 internal constant FORK_BLOCK = 4_008_210;
    address internal constant SAFE = 0xAc52395a9D706696Cf36125A0664c0C6d2B06B7b;
    address internal constant OWNER = 0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f;
    address internal constant OPERATOR = 0x15d16F4783e41c865C324d39170D00EED1f27770;
    address internal constant REGISTRY = 0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1;
    address internal constant RETH = 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1;
    address internal constant BOLD = 0x640D169b87fbf242042445cc05486146482d3949;
    address internal constant YBOLD = 0xA976F0f1d6C0bD932e6DC7Fa9AF98247a9809Fe6;
    address internal constant YSYBOLD = 0xD87b98E0b8e88A99109c52C477B77853532b3006;
    address internal constant SBOLD = 0x77Fe212C9d06758796a9352Dad6f84ac9E05E8F5;
    address internal constant PYB = 0x0C0CFB723726878E94Ed491f39aA78bf118a88c8;
    SebaPool internal constant POOL = SebaPool(payable(0xB17e95B6f94c2028247be0Ab803f25fd19cfb679));
    YieldManagerV2 internal constant MANAGER = YieldManagerV2(payable(0x989F75ca5Ba3422b4392198cbc45C7Ec1587657A));
    SebaCowIntentModule internal constant COW =
        SebaCowIntentModule(payable(0x3E89da80046Da0CA6A9469E7CE1cEF3039D23343));
    HoodiCowSettlementMock internal constant SETTLEMENT =
        HoodiCowSettlementMock(0xb918903051BE61B6957790912A6e811CaeFB1308);
    RethSupporterVault internal constant RETH_VAULT = RethSupporterVault(0x74AE3c59083EfB2211a29CC32eD8832D3872F52a);
    YsyBoldSupporterVault internal constant YSY_VAULT =
        YsyBoldSupporterVault(0x788433edbDb3F11d03d51A93D877516A0C53D19e);

    address internal alice;
    address internal bob;

    /// @notice Pin the public Hoodi state before any new supporter position existed.
    function setUp() public {
        vm.createSelectFork(vm.envString("HOODI_RPC"), FORK_BLOCK);
        assertEq(block.chainid, 560_048);
        assertEq(uint256(RETH_VAULT.recoveryState()), uint256(IV2SupporterVault.RecoveryState.Normal));
        assertEq(uint256(YSY_VAULT.recoveryState()), uint256(IV2SupporterVault.RecoveryState.Normal));
        assertEq(RETH_VAULT.nextPositionId(), 1);
        assertEq(YSY_VAULT.nextPositionId(), 1);
        alice = makeAddr("phase6-reth-supporter");
        bob = makeAddr("phase6-ysy-supporter");
    }

    /// @notice Both public native-token legs preserve protocol backing and permit exits after the original lock.
    function test_RealRocketMintAndMockYearnSupporterPositionsExitAfterLockDespitePauses() public {
        IV2SupporterVault.Bucket memory rProtocol = RETH_VAULT.bucket(1);
        IV2SupporterVault.Bucket memory yProtocol = YSY_VAULT.bucket(1);
        uint256 rTokens = _mintRethAndDeposit();
        _mintYsyAndDeposit();
        assertEq(RETH_VAULT.bucket(0).tokens, rTokens);
        assertEq(YSY_VAULT.bucket(0).tokens, 10 ether);

        vm.prank(alice);
        vm.expectRevert(IV2SupporterVault.PositionLocked.selector);
        RETH_VAULT.withdraw(1, 1, block.timestamp);
        vm.prank(bob);
        vm.expectRevert(IV2SupporterVault.PositionLocked.selector);
        YSY_VAULT.withdraw(1, 1, block.timestamp);

        uint256 rMinimum = RETH_VAULT.minimumBasis();
        uint256 yMinimum = YSY_VAULT.minimumBasis();
        vm.prank(SAFE);
        RETH_VAULT.configureEntry(rMinimum, false);
        vm.prank(SAFE);
        YSY_VAULT.configureEntry(yMinimum, false);
        vm.warp(block.timestamp + 30 days);

        vm.prank(alice);
        assertGt(RETH_VAULT.withdraw(1, 1, block.timestamp), 0);
        vm.prank(bob);
        assertEq(YSY_VAULT.withdraw(1, 1, block.timestamp), 10 ether);
        assertEq(RETH_VAULT.bucket(0).basis, 0);
        assertEq(YSY_VAULT.bucket(0).basis, 0);
        assertEq(RETH_VAULT.bucket(1).basis, rProtocol.basis);
        assertEq(RETH_VAULT.bucket(1).tokens, rProtocol.tokens);
        assertEq(YSY_VAULT.bucket(1).basis, yProtocol.basis);
        assertEq(YSY_VAULT.bucket(1).tokens, yProtocol.tokens);
        vm.prank(bob);
        vm.expectRevert(IV2SupporterVault.ClosedPosition.selector);
        YSY_VAULT.withdraw(1, 1, block.timestamp);
    }

    /// @notice A Safe-approved half-loss settlement closes supporter and protocol claims in their native token.
    function test_PublicYsyCustodyRecoveryHalfLossPaysSameTokenToBothBuckets() public {
        _mintYsyAndDeposit();
        bytes32 initial = keccak256("phase6-public-fork-custody");
        bytes32 settlement = keccak256("phase6-public-fork-half-loss");
        vm.prank(bob);
        vm.expectRevert(IV2SupporterVault.Unauthorized.selector);
        YSY_VAULT.beginRecovery(initial);

        vm.prank(SAFE);
        YSY_VAULT.beginRecovery(initial);
        assertEq(IERC20(YSYBOLD).balanceOf(SAFE), 1_010 ether);
        assertEq(uint256(YSY_VAULT.recoveryState()), uint256(IV2SupporterVault.RecoveryState.Custody));
        uint256[2] memory halfBudgets = [uint256(5 ether), uint256(500 ether)];
        vm.prank(SAFE);
        vm.expectRevert(IV2SupporterVault.UnfundedSettlement.selector);
        YSY_VAULT.activateSettlement(halfBudgets, settlement);

        vm.startPrank(SAFE);
        IERC20(YSYBOLD).approve(address(YSY_VAULT), 505 ether);
        YSY_VAULT.fundRecovery(0, 5 ether);
        YSY_VAULT.fundRecovery(1, 500 ether);
        YSY_VAULT.activateSettlement(halfBudgets, settlement);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(IV2SupporterVault.PositionLocked.selector);
        YSY_VAULT.withdraw(1, 5 ether, block.timestamp);
        vm.warp(block.timestamp + 30 days);
        vm.prank(bob);
        assertEq(YSY_VAULT.withdraw(1, 5 ether, block.timestamp), 5 ether);
        vm.prank(SAFE);
        assertEq(YSY_VAULT.withdrawProtocol(1_000 ether, 500 ether, block.timestamp), 500 ether);
        assertEq(YSY_VAULT.bucket(0).basis, 0);
        assertEq(YSY_VAULT.bucket(1).basis, 0);
        assertEq(IERC20(YSYBOLD).balanceOf(address(YSY_VAULT)), 0);
        vm.prank(SAFE);
        YSY_VAULT.finalizeRecovery();
        assertEq(uint256(YSY_VAULT.recoveryState()), uint256(IV2SupporterVault.RecoveryState.Settled));
        vm.prank(bob);
        vm.expectRevert(IV2SupporterVault.ClosedPosition.selector);
        YSY_VAULT.withdraw(1, 0, block.timestamp);
    }

    /// @notice An unfilled reward order returns only its original reward ETH inventory after expiry.
    function test_PublicPoolRewardNoFillExpiryReturnsExactAssignedEth() public {
        _sweepSyntheticPoolReward();
        uint256 reward = MANAGER.pendingEth(0);
        assertEq(reward, 0.2 ether);
        uint256 nextId = COW.nextOrderId();
        vm.prank(OPERATOR);
        MANAGER.openCowOrder(0, reward, 390 ether, uint32(block.timestamp + 60), nextId, keccak256("no-fill"));
        ISebaCowIntentModule.Order memory order = COW.order(nextId);
        assertEq(COW.activeOrder(0), nextId);
        assertEq(COW.activeCount(), 1);
        assertEq(MANAGER.pendingEth(0), 0);

        vm.prank(OPERATOR);
        vm.expectRevert(ISebaCowIntentModule.PendingOrder.selector);
        MANAGER.finalizeCowOrder(nextId);
        vm.warp(block.timestamp + 61);
        vm.prank(OPERATOR);
        MANAGER.finalizeCowOrder(nextId);
        assertEq(COW.activeCount(), 0);
        assertEq(MANAGER.pendingEth(0), reward);
        assertEq(MANAGER.pendingEth(1), 0.1 ether);
        assertEq(MANAGER.pendingEth(2), 0.1 ether);
        assertEq(address(MANAGER).balance, 0.4 ether);
        assertEq(IERC20(COW.weth()).balanceOf(order.escrow), 0);
        assertEq(MANAGER.pendingBold(), 0);
        vm.prank(OPERATOR);
        vm.expectRevert(ISebaCowIntentModule.ClosedOrder.selector);
        MANAGER.finalizeCowOrder(nextId);
    }

    /// @notice A mock-filled reward order can donate sBOLD without misclassifying the investment legs.
    function test_PublicPoolRewardSyntheticFillDonatesOnlyRewardShares() public {
        _sweepSyntheticPoolReward();
        uint256 reward = MANAGER.pendingEth(0);
        uint256 nextId = COW.nextOrderId();
        uint256 beforePyb = IERC20(SBOLD).balanceOf(PYB);
        vm.prank(OPERATOR);
        MANAGER.openCowOrder(0, reward, 390 ether, uint32(block.timestamp + 60), nextId, keccak256("reward-fill"));
        address escrow = COW.order(nextId).escrow;
        vm.prank(OWNER);
        SETTLEMENT.settleMockOrder(escrow, 400 ether);
        vm.prank(OPERATOR);
        MANAGER.finalizeCowOrder(nextId);
        assertEq(MANAGER.pendingBold(), 400 ether);
        assertEq(MANAGER.pendingProtocolBold(), 0);
        vm.prank(OPERATOR);
        MANAGER.convertBoldToSBold(400 ether, 400 ether, block.timestamp + 60);
        vm.prank(OPERATOR);
        MANAGER.donateSBold(400 ether);
        assertEq(IERC20(SBOLD).balanceOf(PYB) - beforePyb, 400 ether);
        assertEq(MANAGER.pendingBold(), 0);
        assertEq(MANAGER.pendingSBold(), 0);
        assertEq(MANAGER.pendingEth(1), 0.1 ether);
        assertEq(MANAGER.pendingEth(2), 0.1 ether);
    }

    function _sweepSyntheticPoolReward() internal {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool sent, ) = address(POOL).call{ value: 0.4 ether }("");
        assertTrue(sent);
        POOL.sweepRewards();
        assertEq(address(POOL).balance, 0);
    }

    function _mintRethAndDeposit() internal returns (uint256 tokens) {
        address rocketPool = IExecutorRocketStorage(REGISTRY).getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        IExecutorRocketPool(rocketPool).deposit{ value: 0.05 ether }();
        tokens = IERC20(RETH).balanceOf(alice);
        assertGt(tokens, 0);
        IERC20(RETH).approve(address(RETH_VAULT), tokens);
        (uint256 id, uint256 basis) = RETH_VAULT.deposit(tokens, 0.049 ether, block.timestamp);
        vm.stopPrank();
        assertEq(id, 1);
        assertGe(basis, 0.049 ether);
    }

    function _mintYsyAndDeposit() internal {
        MockBold(BOLD).mint(bob, 10 ether);
        vm.startPrank(bob);
        IERC20(BOLD).approve(YBOLD, 10 ether);
        HoodiYearnMock(YBOLD).deposit(10 ether, bob);
        IERC20(YBOLD).approve(YSYBOLD, 10 ether);
        HoodiYearnMock(YSYBOLD).deposit(10 ether, bob);
        IERC20(YSYBOLD).approve(address(YSY_VAULT), 10 ether);
        (uint256 id, uint256 basis) = YSY_VAULT.deposit(10 ether, 10 ether, block.timestamp);
        vm.stopPrank();
        assertEq(id, 1);
        assertEq(basis, 10 ether);
    }
}
