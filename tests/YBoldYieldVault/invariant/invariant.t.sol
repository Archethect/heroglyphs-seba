// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldYieldVaultTestBase } from "tests/YBoldYieldVault/Base.t.sol";
import { MockToken, MockYearnVault, MockYBoldYieldManager } from "tests/mocks/MockYBoldIntegrations.sol";

/** @notice Unit-model sequence search; capital, profit, and losses here are synthetic and not liquidation evidence. */
contract YBoldAccountingHandler is Test {
    YBoldYieldVault public immutable vault;
    MockYBoldYieldManager public immutable manager;
    MockToken public immutable bold;
    MockYearnVault public immutable yBold;
    MockYearnVault public immutable stYBold;
    address public immutable treasury;
    uint256[4] public claims;
    uint256 public donatedShares;
    uint256 public fundedEth;
    uint256 public recoveryPaid;
    uint256 public sweptEth;
    uint256 public custodyShares;
    uint256 public normalOperations;

    constructor(
        YBoldYieldVault vault_,
        MockYBoldYieldManager manager_,
        MockToken bold_,
        MockYearnVault yBold_,
        MockYearnVault stYBold_,
        address treasury_
    ) {
        vault = vault_;
        manager = manager_;
        bold = bold_;
        yBold = yBold_;
        stYBold = stYBold_;
        treasury = treasury_;
    }

    function deposit(uint256 actor, uint256 ethAmount) external {
        if (!_normal()) return;
        uint256 principal = vault.principalValue();
        uint256 backing = stYBold.convertToAssets(vault.principalShares());
        if (backing < principal && principal - backing > vault.MAX_ACCOUNTING_DUST()) return;
        ethAmount = bound(ethAmount, 0.01 ether, 1 ether);
        vm.deal(address(this), ethAmount);
        uint256 sharesBefore = vault.principalShares();
        try manager.deposit{ value: ethAmount }(address(vault)) returns (uint256 value) {
            claims[actor % 4] += value;
        } catch (bytes memory reason) {
            // A direct donation to an empty external ERC4626 can round a new share mint to zero.
            // The adapter must reject it atomically, not silently strand the depositor's assets.
            assertEq(reason, abi.encodeWithSelector(IYBoldYieldVault.NoSharesMinted.selector, address(stYBold)));
            assertEq(vault.principalValue(), principal);
            assertEq(vault.principalShares(), sharesBefore);
            assertEq(address(this).balance, ethAmount);
        }
        ++normalOperations;
    }

    function withdraw(uint256 actor) external {
        if (!_normal()) return;
        actor %= 4;
        uint256 amount = claims[actor];
        if (amount == 0) return;
        manager.retrieve(address(vault), amount);
        claims[actor] = 0;
        ++normalOperations;
    }

    function donateShares(uint256 amount) external {
        amount = bound(amount, 1e12, 1e18);
        _mintYBold(amount);
        IERC20(address(yBold)).approve(address(stYBold), amount);
        donatedShares += stYBold.deposit(amount, address(vault));
    }

    function donateProfit(uint256 amount) external {
        if (!_normal()) return;
        amount = bound(amount, 1e18, 1_000e18);
        _mintYBold(amount);
        assertTrue(IERC20(address(yBold)).transfer(address(stYBold), amount));
        ++normalOperations;
    }

    function realizeLoss(uint256 bps) external {
        if (!_normal()) return;
        uint256 amount = Math.mulDiv(IERC20(address(yBold)).balanceOf(address(stYBold)), bound(bps, 1, 100), 10_000);
        if (amount != 0) stYBold.simulateLoss(amount);
        ++normalOperations;
    }

    function harvest() external {
        if (!_normal()) return;
        manager.claim(address(vault));
        ++normalOperations;
    }

    function initiateRecovery() external {
        if (!_normal() || vault.principalShares() == 0 || normalOperations < 4) return;
        custodyShares = vault.principalShares();
        vm.prank(treasury);
        vault.initiateRecovery();
    }

    function fund(uint256 ethAmount) external {
        if (vault.recoveryState() != IYBoldYieldVault.RecoveryState.SharesTransferred) return;
        ethAmount = bound(ethAmount, 1, 5 ether);
        vm.deal(treasury, ethAmount);
        vm.prank(treasury);
        vault.fundRecovery{ value: ethAmount }();
        fundedEth += ethAmount;
    }

    function activate(uint256 settlement) public {
        if (vault.recoveryState() != IYBoldYieldVault.RecoveryState.SharesTransferred) return;
        settlement = bound(settlement, 0, fundedEth);
        if (settlement != 0 && Math.mulDiv(settlement, 1e18, vault.principalValue()) == 0) settlement = 0;
        vm.prank(treasury);
        vault.activateRecoverySettlement(settlement);
    }

    function settle(uint256 actor) public {
        if (vault.recoveryState() != IYBoldYieldVault.RecoveryState.SettlementActive) return;
        actor %= 4;
        uint256 amount = claims[actor];
        if (amount == 0) return;
        uint256 before = address(manager).balance;
        manager.retrieve(address(vault), amount);
        recoveryPaid += address(manager).balance - before;
        claims[actor] = 0;
    }

    function sweep() public {
        if (vault.recoveryState() != IYBoldYieldVault.RecoveryState.Settled) return;
        uint256 ethAmount = address(vault).balance;
        if (ethAmount == 0 && donatedShares == 0) return;
        vm.prank(treasury);
        vault.sweepRecoveryExcess();
        sweptEth += ethAmount;
        custodyShares += donatedShares;
        donatedShares = 0;
    }

    function finishRecovery() external {
        if (_normal() && vault.principalShares() != 0) {
            custodyShares = vault.principalShares();
            vm.prank(treasury);
            vault.initiateRecovery();
        }
        activate(fundedEth);
        for (uint256 actor; actor < 4; ++actor) settle(actor);
        sweep();
    }

    function _normal() private view returns (bool) {
        return vault.recoveryState() == IYBoldYieldVault.RecoveryState.Normal;
    }

    function _mintYBold(uint256 amount) private {
        bold.mint(address(this), amount);
        bold.approve(address(yBold), amount);
        uint256 minted = yBold.deposit(amount, address(this));
        assertEq(minted, amount, "unit model's yBOLD should remain one-to-one");
    }
}

contract YBoldAccountingInvariantTest is YBoldYieldVaultTestBase {
    YBoldAccountingHandler private handler;

    function setUp() public override {
        super.setUp();
        handler = new YBoldAccountingHandler(vault, manager, bold, yBold, stYBold, recoveryTreasury);
        // Seed independent liability buckets, then search deposits, exits, profit/loss, donations, and recovery order.
        for (uint256 actor; actor < 4; ++actor) handler.deposit(actor, 1 ether);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.donateShares.selector;
        selectors[3] = handler.donateProfit.selector;
        selectors[4] = handler.realizeLoss.selector;
        selectors[5] = handler.harvest.selector;
        selectors[6] = handler.initiateRecovery.selector;
        selectors[7] = handler.fund.selector;
        selectors[8] = handler.activate.selector;
        selectors[9] = handler.settle.selector;
        selectors[10] = handler.sweep.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    function invariant_LiabilitiesAndAllShareCustodyConserve() public view {
        uint256 liabilities;
        for (uint256 actor; actor < 4; ++actor) liabilities += handler.claims(actor);
        assertEq(vault.principalValue(), liabilities, "manager claims drifted from adapter book value");
        assertEq(stYBold.balanceOf(address(vault)), vault.principalShares() + handler.donatedShares());
        assertEq(stYBold.balanceOf(recoveryTreasury), handler.custodyShares());
    }

    function invariant_RecoveryFundingCannotBeLostOrOverspent() public view {
        assertEq(handler.fundedEth(), address(vault).balance + handler.recoveryPaid() + handler.sweptEth());
        if (vault.recoveryState() != IYBoldYieldVault.RecoveryState.Normal) {
            IYBoldYieldVault.RecoveryAccounting memory recovery = vault.recoveryAccounting();
            assertEq(recovery.principalSnapshot, vault.principalValue() + recovery.principalSettled);
            assertEq(recovery.ethPaid, handler.recoveryPaid());
            assertLe(recovery.ethPaid, recovery.settlementEth);
            assertEq(vault.claimableYield(), 0);
        }
    }

    function afterInvariant() public {
        handler.finishRecovery();
        invariant_LiabilitiesAndAllShareCustodyConserve();
        invariant_RecoveryFundingCannotBeLostOrOverspent();
        assertEq(vault.principalValue(), 0);
        assertEq(address(vault).balance, 0);
    }
}
