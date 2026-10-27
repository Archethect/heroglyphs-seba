// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RethSupporterVault } from "../../../../src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "../../../../src/v2/YsyBoldSupporterVault.sol";
import { IV2SupporterVault } from "../../../../src/interfaces/v2/IV2SupporterVault.sol";
import { VaultMockManager } from "../VaultBase.t.sol";

interface VaultForkRETH {
    function getEthValue(uint256 tokens) external view returns (uint256);
    function getRethValue(uint256 basis) external view returns (uint256);
}
interface VaultForkYearn {
    function convertToAssets(uint256 q) external view returns (uint256);
    function convertToShares(uint256 b) external view returns (uint256);
    function previewWithdraw(uint256 b) external view returns (uint256);
}

/// @dev Real mainnet tokens/canonical accounting. Impersonation and all state mutation occur ONLY on a local fork.
contract VaultNativeForkTest is Test {
    address internal constant SAFE = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address internal constant YSY = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address internal constant REGISTRY = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    RethSupporterVault internal reth;
    YsyBoldSupporterVault internal ysy;
    VaultMockManager internal manager;
    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), vm.envOr("SEBA_V2_FORK_BLOCK", uint256(26_255_470)));
        manager = new VaultMockManager();
        reth = RethSupporterVault(
            address(
                new ERC1967Proxy(
                    address(new RethSupporterVault()),
                    abi.encodeCall(RethSupporterVault.initialize, (SAFE, address(manager), RETH, REGISTRY))
                )
            )
        );
        ysy = YsyBoldSupporterVault(
            address(
                new ERC1967Proxy(
                    address(new YsyBoldSupporterVault()),
                    abi.encodeCall(YsyBoldSupporterVault.initialize, (SAFE, address(manager), YSY, YBOLD))
                )
            )
        );
        // Representative test values, NOT approved production settings.
        vm.startPrank(SAFE);
        reth.configureReportBounds(3 days, 30_000);
        reth.configureEntry(1 ether, true);
        reth.configureHarvest(type(uint256).max, true);
        ysy.configureEntry(1 ether, true);
        ysy.configureHarvest(type(uint256).max, true);
        vm.stopPrank();
    }
    function _entry(IV2SupporterVault vault, uint256 q) private returns (uint256 id, uint256 b) {
        vm.startPrank(SAFE);
        IERC20(vault.asset()).approve(address(vault), q);
        (id, b) = vault.deposit(q, 0, block.timestamp);
        vm.stopPrank();
    }
    function testFork_RealTreasurySizeNativeDepositsCanonicalRoundingAndHealthyExits() external {
        uint256 qr = IERC20(RETH).balanceOf(SAFE);
        uint256 qy = IERC20(YSY).balanceOf(SAFE);
        assertGt(qr, 40 ether);
        assertGt(qy, 100_000 ether);
        (uint256 ir, uint256 br) = _entry(reth, qr);
        (uint256 iy, uint256 by) = _entry(ysy, qy);
        assertEq(br, VaultForkRETH(RETH).getEthValue(qr));
        assertEq(by, VaultForkYearn(YSY).convertToAssets(qy));
        (, , uint256 rr, ) = reth.accounting(0);
        (, , uint256 ry, ) = ysy.accounting(0);
        assertGe(VaultForkRETH(RETH).getEthValue(rr), br);
        assertEq(ry, VaultForkYearn(YSY).previewWithdraw(by));
        vm.warp(block.timestamp + 30 days);
        uint256 rExpected = VaultForkRETH(RETH).getRethValue(br);
        uint256 yExpected = VaultForkYearn(YSY).convertToShares(by);
        vm.startPrank(SAFE);
        uint256 ro = reth.withdraw(ir, rExpected, block.timestamp);
        uint256 yo = ysy.withdraw(iy, yExpected, block.timestamp);
        vm.stopPrank();
        assertEq(ro, rExpected);
        assertEq(yo, yExpected);
        assertEq(IERC20(RETH).balanceOf(SAFE), ro);
        assertEq(IERC20(YSY).balanceOf(SAFE), yo);
        assertEq(reth.bucket(0).basis, 0);
        assertEq(ysy.bucket(0).basis, 0);
        assertEq(IERC20(RETH).balanceOf(address(reth)) + ro, qr);
        assertEq(IERC20(YSY).balanceOf(address(ysy)) + yo, qy);
    }
    function testFork_FaultInjectedRedemptionAndUSDFeedFailuresDoNotBlockRealNativeExits() external {
        (uint256 ir, ) = _entry(reth, 10 ether);
        (uint256 iy, ) = _entry(ysy, 10_000 ether);
        // Explicit fault injection; these calls MUST NOT be on the native exit path.
        vm.mockCallRevert(RETH, abi.encodeWithSignature("burn(uint256)"), "native burn unavailable");
        vm.mockCallRevert(
            YSY,
            abi.encodeWithSignature("redeem(uint256,address,address,uint256)"),
            "Yearn redemption unavailable"
        );
        vm.mockCallRevert(
            YBOLD,
            abi.encodeWithSignature("redeem(uint256,address,address,uint256)"),
            "inner redemption unavailable"
        );
        vm.mockCallRevert(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            abi.encodeWithSignature("latestRoundData()"),
            "USD oracle unavailable"
        );
        manager.configure(true, address(0), "");
        vm.warp(block.timestamp + 30 days);
        vm.startPrank(SAFE);
        assertGt(reth.withdraw(ir, 1, block.timestamp), 0);
        assertGt(ysy.withdraw(iy, 1, block.timestamp), 0);
        vm.stopPrank();
    }
    function testFork_FaultInjectedYearnCanonicalFailureUsesRealSharesForExceptionalRecoveryAndDoesNotBlockReth()
        external
    {
        (uint256 ir, ) = _entry(reth, 10 ether);
        (uint256 iy, uint256 by) = _entry(ysy, 10_000 ether);
        vm.mockCallRevert(YSY, abi.encodeWithSignature("totalAssets()"), "canonical valuation unavailable");
        vm.prank(SAFE);
        ysy.beginRecovery(keccak256("fork custody snapshot"));
        assertEq(IERC20(YSY).balanceOf(address(ysy)), 0);
        uint256 exported = ysy.recoveryBucket(0).exportedTokens;
        assertEq(exported, 10_000 ether);
        uint256[2] memory budgets = [uint256(9_000 ether), uint256(0)];
        vm.startPrank(SAFE);
        IERC20(YSY).approve(address(ysy), exported);
        ysy.fundRecovery(0, exported);
        ysy.activateExceptionalSettlement(budgets, keccak256("fork manual 10pct token haircut"));
        vm.stopPrank();
        vm.warp(block.timestamp + 30 days);
        uint256 before = IERC20(YSY).balanceOf(SAFE);
        vm.startPrank(SAFE);
        assertEq(ysy.withdraw(iy, 9_000 ether, block.timestamp), 9_000 ether);
        assertGt(reth.withdraw(ir, 1, block.timestamp), 0);
        vm.stopPrank();
        assertEq(IERC20(YSY).balanceOf(SAFE) - before, 9_000 ether);
        assertEq(ysy.recoveryBucket(0).closedBasis, by);
        assertEq(ysy.bucket(0).basis, 0);
        vm.prank(SAFE);
        ysy.finalizeRecovery();
        assertEq(manager.received(0), 1_000 ether);
        assertEq(IERC20(YSY).balanceOf(address(ysy)), 0);
    }
}
