// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/src/Test.sol";
import { YieldManager } from "src/YieldManager.sol";
import { LegacyProtocolPrincipalHandoff } from "src/v2/LegacyProtocolPrincipalHandoff.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";
import { ExecutorToken, ExecutorActor } from "../executor/ExecutorMocks.sol";
import {
    HandoffSafeMock,
    HandoffPoolMock,
    HandoffRouterMock,
    HandoffAdapterMock,
    HandoffDestinationMock
} from "./HandoffMocks.sol";

abstract contract HandoffUnitBase is Test {
    HandoffSafeMock internal safe;
    HandoffPoolMock internal pool;
    HandoffRouterMock internal router;
    HandoffAdapterMock internal adapter;
    HandoffDestinationMock internal destination;
    ExecutorToken internal bold;
    ExecutorToken internal sbold;
    ExecutorActor internal pyb;
    YieldManager internal old;
    LegacyProtocolPrincipalHandoff internal handoff;
    LegacyIntakeStopper internal stopper;
    uint256 internal constant ETH_BUDGET = 5 ether;
    bytes32 internal constant MANIFEST = keccak256("synthetic unit migration; actual chain tested separately");

    function setUp() public virtual {
        vm.warp(100_000);
        safe = new HandoffSafeMock();
        pool = new HandoffPoolMock();
        router = new HandoffRouterMock();
        adapter = new HandoffAdapterMock();
        bold = new ExecutorToken(18);
        sbold = new ExecutorToken(18);
        pyb = new ExecutorActor();
        old = new YieldManager(
            address(safe),
            address(this),
            address(pool),
            address(router),
            address(bold),
            address(sbold),
            address(pyb),
            address(adapter)
        );
        pool.setYieldManager(address(old));
        // Real legacy admin deposit path; synthetic ETH/adapter are explicitly confined to unit control-flow tests.
        vm.deal(address(old), 10 ether);
        vm.prank(address(safe));
        old.depositPrincipalIntoYieldVault();
        address user = address(0x1234);
        vm.deal(user, 2 ether);
        vm.prank(user);
        old.depositFunds{ value: 2 ether }();
        vm.warp(block.timestamp + 30 days);
        vm.prank(user);
        old.retrieveFunds(1);
        adapter.seedResidue();
        // Stage A is a separate successful transaction: exit first, then approve the now-known ETH budget.
        stopper = new LegacyIntakeStopper();
        vm.prank(address(safe));
        old.setYieldVault(address(stopper));
        destination = new HandoffDestinationMock(
            address(safe),
            address(pool),
            address(bold),
            address(sbold),
            address(pyb)
        );
        handoff = new LegacyProtocolPrincipalHandoff(_configuration());
        _arm(handoff);
        vm.deal(address(this), 100 ether);
    }
    function _configuration() internal view returns (ILegacyProtocolPrincipalHandoff.Configuration memory c) {
        c = ILegacyProtocolPrincipalHandoff.Configuration({
            oldManager: address(old),
            destination: address(destination),
            treasury: address(safe),
            pool: address(pool),
            oldVault: address(adapter),
            stagingVault: address(stopper),
            oldRouter: address(router),
            expectedEth: ETH_BUDGET,
            expiry: block.timestamp + 1 days,
            oldPrincipal: old.principalValue(),
            oldDepositId: old.depositId(),
            adapterPrincipal: adapter.principalValue(),
            adapterShares: adapter.principalShares(),
            actualBeefyShares: adapter.beefy().balanceOf(address(adapter)),
            oldIdleEth: address(old).balance,
            safeOwnersHash: keccak256(abi.encode(safe.getOwners())),
            safeThreshold: safe.getThreshold(),
            rethBps: 5000,
            manifest: MANIFEST,
            maximumRouterEth: 0,
            maximumOldBold: 0,
            maximumOldSBold: 0,
            maximumRouterBold: 0
        });
    }
    function _arm(LegacyProtocolPrincipalHandoff h) internal {
        destination.arm(address(h), h.expectedEth(), h.expiry(), MANIFEST);
    }
    function _pre() internal {
        vm.prank(address(safe));
        handoff.assertPreMigration();
    }
    function _switch() internal {
        vm.prank(address(safe));
        old.setYieldVault(address(handoff));
    }
    function _import() internal {
        vm.prank(address(safe));
        old.depositPrincipalIntoYieldVault();
    }
    function _finalPointers() internal {
        destination.setMode(true, false, false, true);
        pool.setYieldManager(address(destination));
    }
    function _post() internal {
        vm.prank(address(safe));
        handoff.assertPostMigration();
    }
    function _expectPre(bytes4 error) internal {
        vm.expectRevert(error);
        _pre();
    }
    function _mock(address target, string memory signature, bytes memory output) internal {
        vm.mockCall(target, abi.encodeWithSignature(signature), output);
    }
}
