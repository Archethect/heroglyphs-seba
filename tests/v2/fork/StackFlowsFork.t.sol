// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { StackForkBase } from "./StackForkBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IV2SupporterVault } from "src/interfaces/v2/IV2SupporterVault.sol";

contract StackFlowsForkTest is StackForkBase {
    function _cutoverFixture() internal {
        // Isolated flow fixture ONLY; full legacy/Safe migration is in a different test.
        _enableTestExecution();
        vm.startPrank(SAFE);
        manager.setIntakeEnabled(true);
        pool.setYieldManager(address(manager));
        vm.stopPrank();
    }
    function test_RealPoolSweepInvestBothLegsDonateAndWithdrawProtocolTokens() public {
        _cutoverFixture();
        uint256 inherited = address(pool).balance;
        // Explicit synthetic test reward input, NOT liquidation or treasury recovery proceeds.
        vm.deal(address(pool), inherited + 40 ether);
        pool.sweepRewards();
        uint256 rCash = manager.pendingEth(1);
        uint256 yCash = manager.pendingEth(2);
        uint256 reward = manager.pendingEth(0);
        assertEq(reward, (inherited + 40 ether) / 2);
        vm.startPrank(operator);
        manager.deployProtocolPrincipal(0, rCash, 1, 1, block.timestamp + 60);
        manager.deployProtocolPrincipal(1, yCash, 1, 1, block.timestamp + 60);
        manager.convertEthRewards(reward, 1, block.timestamp + 60);
        manager.convertBoldToSBold(manager.pendingBold(), 1, block.timestamp + 60);
        vm.stopPrank();
        uint256 donation = manager.pendingSBold();
        uint256 beforeDonation = IERC20(address(old.sBOLD())).balanceOf(address(old.sebaVault()));
        vm.prank(operator);
        manager.donateSBold(donation);
        assertEq(IERC20(address(old.sBOLD())).balanceOf(address(old.sebaVault())) - beforeDonation, donation);
        assertGt(rVault.bucket(1).basis, 0);
        assertGt(yVault.bucket(1).basis, 0);
        vm.startPrank(SAFE);
        rVault.withdrawProtocol(rVault.bucket(1).basis, 1, block.timestamp);
        yVault.withdrawProtocol(yVault.bucket(1).basis, 1, block.timestamp);
        vm.stopPrank();
        assertEq(rVault.bucket(1).basis, 0);
        assertEq(yVault.bucket(1).basis, 0);
        _assertManagerCustody();
        assertEq(
            manager.pendingEth(0) +
                manager.pendingEth(1) +
                manager.pendingEth(2) +
                manager.pendingBold() +
                manager.pendingSBold(),
            0
        );
    }
    function test_PublicNativeSupportersExitDespiteAllUnrelatedVenueOutages() public {
        _cutoverFixture();
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        (uint256 a, ) = _nativeDeposit(rVault, alice, 10 ether);
        (uint256 b, ) = _nativeDeposit(yVault, bob, 10_000 ether);
        vm.mockCallRevert(RETH, abi.encodeWithSignature("burn(uint256)"), "injected burn outage");
        vm.mockCallRevert(
            YSY,
            abi.encodeWithSignature("redeem(uint256,address,address,uint256)"),
            "injected Yearn outage"
        );
        vm.mockCallRevert(
            execution.configuration().curvePool,
            abi.encodeWithSignature("exchange(int128,int128,uint256,uint256)"),
            "injected Curve outage"
        );
        vm.mockCallRevert(
            execution.configuration().ethUsdFeed,
            abi.encodeWithSignature("latestRoundData()"),
            "injected oracle outage"
        );
        vm.startPrank(SAFE);
        rVault.configureEntry(1, false);
        rVault.configureHarvest(0, false);
        yVault.configureEntry(1, false);
        yVault.configureHarvest(0, false);
        manager.setExecutionEnabled(false);
        vm.stopPrank();
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        assertGt(rVault.withdraw(a, 1, block.timestamp), 0);
        vm.prank(bob);
        assertGt(yVault.withdraw(b, 1, block.timestamp), 0);
        assertTrue(rVault.position(a).closed);
        assertTrue(yVault.position(b).closed);
        _assertManagerCustody();
    }
    function test_RealRecognizedYieldHarvestAllDonatedWithoutPrincipalDebit() public {
        _cutoverFixture();
        address alice = makeAddr("alice");
        (uint256 id, uint256 basis) = _nativeDeposit(yVault, alice, 100_000 ether);
        // Local time advance exposes only Yearn's ALREADY REPORTED unlocking profits; no fabricated token/rate growth.
        // Keep external sBOLD/Pyth quotes within their real freshness window; a 30-day warp must NOT fabricate fresh oracles.
        vm.warp(block.timestamp + 1 minutes);
        (, , , uint256 available) = yVault.accounting(0);
        assertGt(available, 0);
        vm.prank(operator);
        uint256 collected = yVault.collectYield(0, available);
        assertEq(manager.harvestInventory(1, 0), collected);
        assertEq(yVault.bucket(0).basis, basis);
        vm.prank(operator);
        manager.convertHarvest(1, 0, collected, 1, block.timestamp + 60);
        vm.startPrank(operator);
        manager.convertBoldToSBold(manager.pendingBold(), 1, block.timestamp + 60);
        manager.donateSBold(manager.pendingSBold());
        vm.stopPrank();
        assertEq(manager.harvestInventory(1, 0), 0);
        assertEq(manager.pendingSBold(), 0);
        assertEq(manager.pendingEth(0), 0);
        vm.warp(yVault.position(id).unlockAt);
        vm.prank(alice);
        assertGt(yVault.withdraw(id, 1, block.timestamp), 0);
        assertEq(yVault.bucket(0).basis, 0);
        _assertManagerCustody();
    }
}
