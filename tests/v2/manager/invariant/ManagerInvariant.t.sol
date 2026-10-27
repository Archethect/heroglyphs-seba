// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/src/Test.sol";
import { StdInvariant } from "forge-std/src/StdInvariant.sol";
import {
    ManagerTestBase,
    ManagerPoolMock,
    ManagerTokenMock,
    ManagerVaultMock,
    ManagerSinkMock
} from "../ManagerTestBase.t.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";

/// @notice Unit state-machine: synthetic 1:1 venues prove purpose accounting, NOT market execution.
contract ManagerAccountingHandler is Test {
    YieldManagerV2 public manager;
    ManagerPoolMock public pool;
    ManagerVaultMock[2] public vault;
    address public safe;
    address public operator;
    uint256 public receivedEth;
    uint256 public harvestedTokens;
    uint256 public successfulActions;
    constructor(YieldManagerV2 m, ManagerPoolMock p, ManagerVaultMock r, ManagerVaultMock y, address s, address o) {
        manager = m;
        pool = p;
        vault[0] = r;
        vault[1] = y;
        safe = s;
        operator = o;
    }
    function receiveRewards(uint96 seed) public {
        uint256 amount = bound(seed, 1, 100 ether);
        vm.deal(address(this), amount);
        pool.submit{ value: amount }(manager);
        receivedEth += amount;
        ++successfulActions;
    }
    function weights(uint16 seed) public {
        uint16 r = uint16(bound(seed, 0, 10_000));
        vm.prank(safe);
        manager.setFutureInvestmentWeights(r, 10_000 - r);
        ++successfulActions;
    }
    function invest(uint8 seed, uint96 quantity) public {
        uint8 leg = seed % 2;
        uint256 available = manager.pendingEth(leg + 1);
        if (available == 0) return;
        uint256 amount = bound(quantity, 1, available);
        vm.prank(operator);
        manager.deployProtocolPrincipal(leg, amount, 1, 1, block.timestamp);
        ++successfulActions;
    }
    function reward(uint96 quantity) public {
        uint256 available = manager.pendingEth(0);
        if (available == 0) return;
        vm.prank(operator);
        manager.convertEthRewards(bound(quantity, 1, available), 1, block.timestamp);
        ++successfulActions;
    }
    function harvest(uint8 legSeed, uint8 bucketSeed, uint96 quantity) public {
        uint256 amount = bound(quantity, 1, 100 ether);
        vault[legSeed % 2].harvest(bucketSeed % 2, amount);
        harvestedTokens += amount;
        ++successfulActions;
    }
    function convert(uint8 legSeed, uint8 bucketSeed, uint96 quantity) public {
        uint8 leg = legSeed % 2;
        uint8 bucket = bucketSeed % 2;
        uint256 available = manager.harvestInventory(leg, bucket);
        if (available == 0) return;
        vm.prank(operator);
        manager.convertHarvest(leg, bucket, bound(quantity, 1, available), 1, block.timestamp);
        ++successfulActions;
    }
    function mintSBold(uint96 quantity) public {
        uint256 available = manager.pendingBold();
        if (available == 0) return;
        vm.prank(operator);
        manager.convertBoldToSBold(bound(quantity, 1, available), 1, block.timestamp);
        ++successfulActions;
    }
    function donate(uint96 quantity) public {
        uint256 available = manager.pendingSBold();
        if (available == 0) return;
        vm.prank(operator);
        manager.donateSBold(bound(quantity, 1, available));
        ++successfulActions;
    }
}

contract ManagerInvariantTest is ManagerTestBase {
    ManagerAccountingHandler internal handler;
    function setUp() public override {
        super.setUp();
        _enable();
        handler = new ManagerAccountingHandler(manager, pool, rVault, yVault, address(safe), operator);
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.receiveRewards.selector;
        selectors[1] = handler.weights.selector;
        selectors[2] = handler.invest.selector;
        selectors[3] = handler.reward.selector;
        selectors[4] = handler.harvest.selector;
        selectors[5] = handler.convert.selector;
        selectors[6] = handler.mintSBold.selector;
        selectors[7] = handler.donate.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }
    function invariant_AllPurposeLedgersRemainFullyBackedAndConserved() public view {
        uint256 cash = manager.pendingEth(0) + manager.pendingEth(1) + manager.pendingEth(2);
        assertEq(address(manager).balance, cash);
        uint256 r = manager.harvestInventory(0, 0) + manager.harvestInventory(0, 1);
        uint256 y = manager.harvestInventory(1, 0) + manager.harvestInventory(1, 1);
        assertEq(rethToken.balanceOf(address(manager)), r);
        assertEq(ysyToken.balanceOf(address(manager)), y);
        assertEq(boldToken.balanceOf(address(manager)), manager.pendingBold());
        assertEq(sBoldToken.balanceOf(address(manager)), manager.pendingSBold());
        uint256 completed = rVault.protocolBasis() + yVault.protocolBasis() + sBoldToken.balanceOf(address(sink));
        assertEq(
            cash + r + y + manager.pendingBold() + manager.pendingSBold() + completed,
            handler.receivedEth() + handler.harvestedTokens()
        );
        assertEq(rethToken.balanceOf(address(rVault)), rVault.protocolBasis());
        assertEq(ysyToken.balanceOf(address(yVault)), yVault.protocolBasis());
        assertEq(rethToken.allowance(address(manager), address(execution)), 0);
        assertEq(ysyToken.allowance(address(manager), address(execution)), 0);
        assertEq(rethToken.allowance(address(manager), address(rVault)), 0);
        assertEq(ysyToken.allowance(address(manager), address(yVault)), 0);
        assertEq(boldToken.allowance(address(manager), address(sBoldToken)), 0);
        assertEq(sBoldToken.allowance(address(manager), address(sink)), 0);
    }
    function test_HandlerActuallyTouchesEachAccountingStage() public {
        handler.receiveRewards(uint96(40 ether));
        handler.weights(4000);
        handler.invest(0, 1 ether);
        handler.invest(1, 1 ether);
        handler.reward(1 ether);
        handler.harvest(0, 0, 3 ether);
        handler.harvest(1, 1, 7 ether);
        handler.convert(0, 0, 1 ether);
        handler.convert(1, 1, 1 ether);
        handler.mintSBold(1 ether);
        handler.donate(1 ether);
        assertEq(handler.successfulActions(), 11);
        invariant_AllPurposeLedgersRemainFullyBackedAndConserved();
    }
    function test_NegativeControlDetectsUnbackedInventory() public {
        handler.harvest(0, 0, 3 ether);
        rethToken.burn(address(manager), 1);
        vm.expectRevert();
        this.invariant_AllPurposeLedgersRemainFullyBackedAndConserved();
    }
}
