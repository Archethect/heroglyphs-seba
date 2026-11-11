// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 as SolmateERC20 } from "solmate/src/tokens/ERC20.sol";
import { IHoodiSafe, IHoodiSafeFactory } from "tests/hoodi/safe/constructor/OfficialSafe.t.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";
import { MockUSDC } from "src/mocks/MockUSDC.sol";
import { MockBold } from "src/mocks/MockBold.sol";
import {
    HoodiSBoldMock,
    HoodiPriceFeedMock,
    HoodiUniswapMock,
    HoodiCurveMock,
    HoodiBeefyMock,
    HoodiYearnMock,
    HoodiEthFlowMock,
    HoodiCowSettlementMock,
    HoodiBeefyHarvesterMock
} from "src/mocks/hoodi/HoodiExternalMocks.sol";
import { EthToBoldRouter } from "src/EthToBoldRouter.sol";
import { PYBSeba } from "src/PYBSeba.sol";
import { SebaPool } from "src/SebaPool.sol";
import { YieldManager } from "src/YieldManager.sol";
import { EUSDUSDCBeefyYieldVault } from "src/EUSDUSDCBeefyYieldVault.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";
import { RethSupporterVault } from "src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "src/v2/YsyBoldSupporterVault.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";
import { LegacyProtocolPrincipalHandoff } from "src/v2/LegacyProtocolPrincipalHandoff.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { IExecutorRocketStorage, IExecutorRocketSettings, IExecutorReth } from "src/vendor/v2/IExecutorProtocols.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";

/// @notice Local fork rehearsal only: fresh Seba contracts, synthetic external venues, no public state changes.
contract HoodiFullRehearsalForkTest is Test {
    address internal constant OWNER = 0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f;
    address internal constant SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address internal constant FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address internal constant MULTISEND = 0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526;
    address internal constant RETH = 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1;
    address internal constant REGISTRY = 0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1;

    IHoodiSafe internal safe;
    MockWETH internal weth;
    MockUSDC internal usdc;
    MockBold internal bold;
    HoodiSBoldMock internal sBold;
    HoodiPriceFeedMock internal ethFeed;
    HoodiPriceFeedMock internal usdFeed;
    HoodiUniswapMock internal uni;
    HoodiCurveMock internal curve;
    HoodiBeefyMock internal beefy;
    HoodiEthFlowMock internal ethFlow;
    EthToBoldRouter internal router;
    EUSDUSDCBeefyYieldVault internal adapter;
    SebaPool internal pool;
    PYBSeba internal pyb;
    YieldManager internal old;
    YieldManagerV2 internal next;
    RethSupporterVault internal rethVault;
    YsyBoldSupporterVault internal ysyVault;
    HoodiYearnMock internal yBold;
    HoodiYearnMock internal ysyBold;
    HoodiCowSettlementMock internal cowSettlement;
    SebaCowIntentModule internal cow;
    SebaV2DirectExecutor internal executor;
    LegacyIntakeStopper internal stopper;
    LegacyProtocolPrincipalHandoff internal handoff;

    function setUp() public {
        vm.createSelectFork(vm.envString("HOODI_RPC"), 3_988_379);
        _deploySafe();
        _deployV1();
        _deployDisabledV2();
    }

    function _deploySafe() internal {
        address[] memory owners = new address[](1);
        owners[0] = OWNER;
        bytes memory initializer = abi.encodeCall(
            IHoodiSafe.setup, (owners, 1, address(0), bytes(""), address(0), address(0), 0, payable(address(0)))
        );
        safe = IHoodiSafe(IHoodiSafeFactory(FACTORY).createProxyWithNonce(SINGLETON, initializer, 0x5EBA));
    }

    function _deployV1() internal {
        weth = new MockWETH();
        usdc = new MockUSDC();
        bold = new MockBold();
        sBold = new HoodiSBoldMock(bold);
        uni = new HoodiUniswapMock(address(weth), address(usdc));
        curve = new HoodiCurveMock(address(usdc));
        beefy = new HoodiBeefyMock(address(curve));
        ethFlow = new HoodiEthFlowMock(OWNER);
        ethFeed = new HoodiPriceFeedMock(2000e8, address(safe));
        usdFeed = new HoodiPriceFeedMock(1e8, address(safe));
        // The legacy backend polls a separate Beefy strategy's paused()/harvest() ABI.
        new HoodiBeefyHarvesterMock();
        router = new EthToBoldRouter(address(ethFlow), address(bold), OWNER, OWNER);
        pyb = new PYBSeba(OWNER, SolmateERC20(address(sBold)));
        pool = new SebaPool(OWNER, OWNER);
        adapter = new EUSDUSDCBeefyYieldVault(
            OWNER,
            OWNER,
            address(weth),
            address(usdc),
            address(uni),
            address(uni),
            address(curve),
            address(beefy),
            address(ethFeed),
            address(usdFeed)
        );
        old = new YieldManager(
            OWNER, OWNER, address(pool), address(router), address(bold), address(sBold), address(pyb), address(adapter)
        );
        vm.startPrank(OWNER);
        adapter.grantRole(adapter.YIELDMANAGER_ROLE(), address(old));
        adapter.revokeRole(adapter.YIELDMANAGER_ROLE(), OWNER);
        pyb.setSebaPool(address(pool));
        pool.setSebaVault(address(pyb));
        pool.setYieldManager(address(old));
        router.grantRole(router.YIELD_MANAGER_ROLE(), address(old));
        router.revokeRole(router.YIELD_MANAGER_ROLE(), OWNER);
        old.grantRole(old.ADMIN_ROLE(), address(safe));
        pool.grantRole(pool.ADMIN_ROLE(), address(safe));
        router.grantRole(router.ADMIN_ROLE(), address(safe));
        adapter.grantRole(adapter.ADMIN_ROLE(), address(safe));
        pyb.grantRole(pyb.ADMIN_ROLE(), address(safe));
        old.revokeRole(old.ADMIN_ROLE(), OWNER);
        pool.revokeRole(pool.ADMIN_ROLE(), OWNER);
        router.revokeRole(router.ADMIN_ROLE(), OWNER);
        adapter.revokeRole(adapter.ADMIN_ROLE(), OWNER);
        pyb.revokeRole(pyb.ADMIN_ROLE(), OWNER);
        vm.stopPrank();
    }

    function _deployDisabledV2() internal {
        yBold = new HoodiYearnMock(address(bold), "Hoodi mock yBOLD", "hyBOLD");
        ysyBold = new HoodiYearnMock(address(yBold), "Hoodi mock ysyBOLD", "hysyBOLD");
        YieldManagerV2 managerImplementation = new YieldManagerV2();
        next = YieldManagerV2(
            payable(address(
                    new ERC1967Proxy(
                        address(managerImplementation),
                        abi.encodeCall(
                            YieldManagerV2.initialize,
                            (IYieldManagerV2.Initialization(
                                    address(safe),
                                    address(0),
                                    address(pool),
                                    address(bold),
                                    address(sBold),
                                    address(pyb),
                                    RETH,
                                    address(ysyBold)
                                ))
                        )
                    )
                ))
        );
        RethSupporterVault rethImplementation = new RethSupporterVault();
        rethVault = RethSupporterVault(
            address(
                new ERC1967Proxy(
                    address(rethImplementation),
                    abi.encodeCall(RethSupporterVault.initialize, (address(safe), address(next), RETH, REGISTRY))
                )
            )
        );
        YsyBoldSupporterVault ysyImplementation = new YsyBoldSupporterVault();
        ysyVault = YsyBoldSupporterVault(
            address(
                new ERC1967Proxy(
                    address(ysyImplementation),
                    abi.encodeCall(
                        YsyBoldSupporterVault.initialize,
                        (address(safe), address(next), address(ysyBold), address(yBold))
                    )
                )
            )
        );
        executor = new SebaV2DirectExecutor(
            IV2Executor.Config(
                address(next),
                address(safe),
                RETH,
                address(weth),
                address(0),
                address(bold),
                address(yBold),
                address(ysyBold),
                address(0),
                address(0),
                address(0),
                address(0),
                REGISTRY
            )
        );
        cowSettlement = new HoodiCowSettlementMock(address(bold), OWNER);
        cow = new SebaCowIntentModule(
            address(next), address(safe), address(weth), RETH, address(bold), address(cowSettlement)
        );
        _safeCall(address(next), abi.encodeCall(YieldManagerV2.bindVaults, (address(rethVault), address(ysyVault))));
        _safeCall(
            address(next),
            abi.encodeCall(YieldManagerV2.configureExecution, (address(executor), 10 ether, 10 ether, 10 ether))
        );
        _safeCall(address(next), abi.encodeCall(YieldManagerV2.configureCowModule, (address(cow))));
        assertFalse(next.intakeEnabled());
        assertFalse(next.executionEnabled());
        assertFalse(cow.enabled());
        assertFalse(executor.enabled());
    }

    function _safeCall(address target, bytes memory data) internal {
        _safeExec(target, data, 0);
    }

    function _safeExec(address target, bytes memory data, uint8 operation) internal {
        bytes32 txHash =
            safe.getTransactionHash(target, 0, data, operation, 0, 0, 0, address(0), address(0), safe.nonce());
        vm.prank(OWNER);
        safe.approveHash(txHash);
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(OWNER))), bytes32(0), uint8(1));
        assertTrue(
            safe.execTransaction(target, 0, data, operation, 0, 0, 0, address(0), payable(address(0)), signature)
        );
    }

    function _call(address target, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), target, uint256(0), uint256(data.length), data);
    }

    function _seedV1ProtocolRewards() internal {
        // Fork-local representative reward capital; no existing Hoodi installation or supporter claim is touched.
        vm.deal(address(pool), 2 ether);
        pool.sweepRewards();
        assertEq(old.pendingBoldConversion(), 1 ether);
        assertGt(old.principalValue(), 0);
        vm.prank(OWNER);
        old.runBoldConversion(1900 ether);
        (,,, bool active,) = router.order();
        assertTrue(active);
        vm.prank(OWNER);
        ethFlow.settleMockOrder(address(router), 1950 ether);
        vm.warp(block.timestamp + old.ROUTER_VALIDITY_SECS() + 1);
        vm.prank(OWNER);
        old.runBoldConversion(0);
        assertEq(old.pendingBoldConversion(), 0);
        assertEq(old.activeRouterUid(), bytes32(0));
        assertEq(IERC20(address(sBold)).balanceOf(address(pyb)), 1950 ether);
        assertEq(old.depositId(), 0);
    }

    function _stageA() internal {
        stopper = new LegacyIntakeStopper();
        _safeExec(
            MULTISEND,
            abi.encodeWithSignature(
                "multiSend(bytes)", _call(address(old), abi.encodeCall(YieldManager.setYieldVault, (address(stopper))))
            ),
            1
        );
        assertEq(old.principalValue(), 0);
        assertEq(address(old.yieldVault()), address(stopper));
        assertEq(address(old).balance, 1 ether);
        assertEq(address(pool.yieldManager()), address(old));
    }

    function _prepareHandoff() internal {
        ILegacyProtocolPrincipalHandoff.Configuration memory c;
        c.oldManager = address(old);
        c.destination = address(next);
        c.treasury = address(safe);
        c.pool = address(pool);
        c.oldVault = address(adapter);
        c.stagingVault = address(stopper);
        c.oldRouter = address(router);
        c.expectedEth = address(old).balance;
        c.expiry = block.timestamp + 15 minutes;
        c.oldPrincipal = old.principalValue();
        c.oldDepositId = old.depositId();
        c.adapterPrincipal = adapter.principalValue();
        c.adapterShares = adapter.principalShares();
        c.actualBeefyShares = IERC20(address(beefy)).balanceOf(address(adapter));
        c.oldIdleEth = address(old).balance;
        c.safeOwnersHash = keccak256(abi.encode(safe.getOwners()));
        c.safeThreshold = safe.getThreshold();
        c.rethBps = next.rethBps();
        c.manifest = keccak256("Hoodi fork-local reviewed test evidence");
        handoff = new LegacyProtocolPrincipalHandoff(c);
    }

    function _stageB(bool correctPointer) internal {
        ILegacyProtocolPrincipalHandoff.Configuration memory c = handoff.configuration();
        bytes memory calls = bytes.concat(
            _call(
                address(next),
                abi.encodeCall(YieldManagerV2.armLegacyImport, (address(handoff), c.expectedEth, c.expiry, c.manifest))
            ),
            _call(address(handoff), abi.encodeCall(LegacyProtocolPrincipalHandoff.assertPreMigration, ()))
        );
        calls = bytes.concat(
            calls,
            _call(address(old), abi.encodeCall(YieldManager.setYieldVault, (address(handoff)))),
            _call(address(old), abi.encodeCall(YieldManager.depositPrincipalIntoYieldVault, ())),
            _call(address(next), abi.encodeCall(YieldManagerV2.setIntakeEnabled, (true))),
            _call(
                address(pool), abi.encodeCall(SebaPool.setYieldManager, (correctPointer ? address(next) : address(old)))
            ),
            _call(address(handoff), abi.encodeCall(LegacyProtocolPrincipalHandoff.assertPostMigration, ()))
        );
        _safeExec(MULTISEND, abi.encodeWithSignature("multiSend(bytes)", calls), 1);
    }

    function test_V1PoolRewardConversionThenRealSafeTwoStageCutover() public {
        _seedV1ProtocolRewards();
        _stageA();
        _prepareHandoff();
        _stageB(true);
        assertEq(address(pool.yieldManager()), address(next));
        assertTrue(handoff.used());
        assertTrue(next.legacyImported());
        assertEq(address(old).balance, 0);
        assertEq(next.pendingEth(0), 0);
        assertEq(next.pendingEth(1), 0.5 ether);
        assertEq(next.pendingEth(2), 0.5 ether);
        assertEq(address(next).balance, 1 ether);
        assertEq(old.depositId(), 0);
        assertFalse(next.executionEnabled());
    }

    function test_StageARequiresFreshSafeControlledOracleReports() public {
        _seedV1ProtocolRewards();
        vm.warp(block.timestamp + adapter.ETH_USD_ORACLE_MAX_AGE() + 1);
        vm.expectRevert();
        this.executeStageA();
        assertEq(address(old.yieldVault()), address(adapter));

        _safeCall(address(ethFeed), abi.encodeCall(HoodiPriceFeedMock.setUpdatedAt, (block.timestamp)));
        _safeCall(address(usdFeed), abi.encodeCall(HoodiPriceFeedMock.setUpdatedAt, (block.timestamp)));
        _stageA();
        assertEq(address(old.yieldVault()), address(stopper));
        assertEq(address(old).balance, 1 ether);
    }

    function test_StageBWrongPointerRollsBackOnlyStageB() public {
        _seedV1ProtocolRewards();
        _stageA();
        _prepareHandoff();
        vm.expectRevert(bytes("GS013"));
        this.executeWrongStageB();
        assertEq(address(pool.yieldManager()), address(old));
        assertEq(address(old.yieldVault()), address(stopper));
        assertEq(address(old).balance, 1 ether);
        assertEq(next.legacyHandoff(), address(0));
        assertFalse(handoff.used());
    }

    function test_OwnerEoaCannotBypassSafeStageAOrStageB() public {
        _seedV1ProtocolRewards();
        LegacyIntakeStopper candidate = new LegacyIntakeStopper();
        vm.prank(OWNER);
        vm.expectRevert();
        old.setYieldVault(address(candidate));
        assertEq(address(old.yieldVault()), address(adapter));
        _stageA();
        _prepareHandoff();
        vm.prank(OWNER);
        vm.expectRevert(ILegacyProtocolPrincipalHandoff.Unauthorized.selector);
        handoff.assertPreMigration();
        ILegacyProtocolPrincipalHandoff.Configuration memory c = handoff.configuration();
        vm.prank(OWNER);
        vm.expectRevert();
        next.armLegacyImport(address(handoff), c.expectedEth, c.expiry, c.manifest);
    }

    function test_AfterCutoverSyntheticCowSettlementCreditsOnlyYsyProtocolLeg() public {
        _seedV1ProtocolRewards();
        _stageA();
        _prepareHandoff();
        _stageB(true);
        _enableTestOnlyExecution();
        uint256 expected = next.pendingEth(2);
        vm.prank(OWNER);
        next.openCowOrder(1, expected, 900 ether, uint32(block.timestamp + 60), 1, bytes32(uint256(1)));
        ISebaCowIntentModule.Order memory order = cow.order(1);
        assertEq(cow.activeCount(), 1);
        assertEq(next.pendingEth(2), 0);
        vm.prank(OWNER);
        cowSettlement.settleMockOrder(order.escrow, 1000 ether);
        vm.prank(OWNER);
        next.finalizeCowOrder(1);
        assertEq(cow.activeCount(), 0);
        assertEq(next.pendingProtocolBold(), 1000 ether);
        assertEq(next.pendingBold(), 0);
        assertEq(next.pendingEth(1), 0.5 ether);
        vm.prank(OWNER);
        next.deployYsyProtocolPrincipal(1000 ether, 1, 1, block.timestamp + 60);
        assertEq(next.pendingProtocolBold(), 0);
        assertEq(ysyVault.bucket(1).tokens, 1000 ether);
        assertEq(ysyVault.bucket(1).basis, 1000 ether);
        assertEq(IERC20(address(ysyBold)).balanceOf(address(ysyVault)), 1000 ether);
    }

    function test_AfterYsySettlementRealRocketMintInvestsRethProtocolLegAndReconcilesCustody() public {
        _seedV1ProtocolRewards();
        _stageA();
        _prepareHandoff();
        _stageB(true);
        _enableTestOnlyExecution();

        uint256 ysyEth = next.pendingEth(2);
        vm.prank(OWNER);
        next.openCowOrder(1, ysyEth, 900 ether, uint32(block.timestamp + 60), 1, bytes32(uint256(1)));
        ISebaCowIntentModule.Order memory order = cow.order(1);
        vm.prank(OWNER);
        cowSettlement.settleMockOrder(order.escrow, 1000 ether);
        vm.prank(OWNER);
        next.finalizeCowOrder(1);
        vm.prank(OWNER);
        next.deployYsyProtocolPrincipal(1000 ether, 1, 1, block.timestamp + 60);

        uint256 rethEth = next.pendingEth(1);
        uint256 fee = IExecutorRocketSettings(_registry("rocketDAOProtocolSettingsDeposit")).getDepositFee();
        uint256 netEth = rethEth - (rethEth * fee) / 1e18;
        uint256 previewTokens = IExecutorReth(RETH).getRethValue(netEth);
        uint256 previewBasis = rethVault.canonicalValue(previewTokens);
        assertGt(previewTokens, 1);
        assertGt(previewBasis, 2);
        _safeCall(address(rethVault), abi.encodeCall(RethSupporterVault.configureReportBounds, (2 days, 20_000)));
        _safeCall(address(rethVault), abi.encodeWithSignature("configureEntry(uint256,bool)", 0.01 ether, true));
        uint256 beforeEth = address(next).balance;
        vm.prank(OWNER);
        next.deployProtocolPrincipal(0, rethEth, previewTokens - 1, previewBasis - 2, block.timestamp + 60);

        uint256 tokens = rethVault.bucket(1).tokens;
        uint256 basis = rethVault.bucket(1).basis;
        assertEq(next.pendingEth(0), 0);
        assertEq(next.pendingEth(1), 0);
        assertEq(next.pendingEth(2), 0);
        assertEq(address(next).balance, beforeEth - rethEth);
        assertEq(address(next).balance, 0);
        assertGt(tokens, 0);
        assertGt(basis, 0);
        assertGe(tokens, previewTokens - 1);
        assertGe(basis, previewBasis - 2);
        assertEq(IERC20(RETH).balanceOf(address(rethVault)), tokens);
        assertEq(IERC20(RETH).balanceOf(address(next)), 0);
        assertEq(IERC20(RETH).balanceOf(address(executor)), 0);
        assertEq(rethVault.canonicalValue(tokens), basis);
        assertEq(ysyVault.bucket(1).tokens, 1000 ether);
        assertEq(ysyVault.bucket(1).basis, 1000 ether);
        assertEq(next.pendingProtocolBold(), 0);
        assertEq(next.pendingBold(), 0);
    }

    function test_SyntheticCowNoFillExpiryRefundAndRejectedSolverOrBadOutput() public {
        _seedV1ProtocolRewards();
        _stageA();
        _prepareHandoff();
        _stageB(true);
        _enableTestOnlyExecution();
        uint256 initial = next.pendingEth(2);
        vm.prank(OWNER);
        next.openCowOrder(1, initial, 900 ether, uint32(block.timestamp + 60), 1, bytes32(uint256(2)));
        ISebaCowIntentModule.Order memory order = cow.order(1);
        vm.prank(address(0xBEEF));
        vm.expectRevert(bytes("mock solver only"));
        cowSettlement.settleMockOrder(order.escrow, 1000 ether);
        vm.prank(OWNER);
        vm.expectRevert(bytes("mock output"));
        cowSettlement.settleMockOrder(order.escrow, 899 ether);
        assertEq(cow.activeCount(), 1);
        vm.warp(block.timestamp + 61);
        vm.prank(OWNER);
        vm.expectRevert(bytes("mock order expired"));
        cowSettlement.settleMockOrder(order.escrow, 1000 ether);
        vm.prank(OWNER);
        next.finalizeCowOrder(1);
        assertEq(cow.activeCount(), 0);
        assertEq(next.pendingEth(2), initial);
        assertEq(next.pendingProtocolBold(), 0);
        vm.prank(OWNER);
        vm.expectRevert(bytes("mock order inactive"));
        cowSettlement.settleMockOrder(order.escrow, 1000 ether);
    }

    function test_PublicNativeSupportersExitAfterSafePausesWithoutDexOrYearnRedemption() public {
        _seedV1ProtocolRewards();
        _stageA();
        _prepareHandoff();
        _stageB(true);
        _safeCall(
            address(rethVault), abi.encodeWithSignature("configureReportBounds(uint256,uint256)", 365 days, 10_000_000)
        );
        _safeCall(address(rethVault), abi.encodeWithSignature("configureEntry(uint256,bool)", 1, true));
        _safeCall(address(ysyVault), abi.encodeWithSignature("configureEntry(uint256,bool)", 1, true));
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        // Fork-local token-storage injection, not a claim that Rocket Pool minted test rETH.
        deal(RETH, alice, 2 ether);
        vm.startPrank(alice);
        IERC20(RETH).approve(address(rethVault), 2 ether);
        (uint256 rId, uint256 rBasis) = rethVault.deposit(2 ether, 1, block.timestamp);
        vm.stopPrank();
        bold.mint(bob, 1000 ether);
        vm.startPrank(bob);
        bold.approve(address(yBold), 1000 ether);
        yBold.deposit(1000 ether, bob);
        yBold.approve(address(ysyBold), 1000 ether);
        ysyBold.deposit(1000 ether, bob);
        ysyBold.approve(address(ysyVault), 1000 ether);
        (uint256 yId, uint256 yBasis) = ysyVault.deposit(1000 ether, 1, block.timestamp);
        vm.stopPrank();
        assertGt(rBasis, 0);
        assertEq(yBasis, 1000 ether);
        _safeCall(address(rethVault), abi.encodeWithSignature("configureEntry(uint256,bool)", 1, false));
        _safeCall(address(ysyVault), abi.encodeWithSignature("configureEntry(uint256,bool)", 1, false));
        _safeCall(address(next), abi.encodeCall(YieldManagerV2.setExecutionEnabled, (false)));
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        assertGt(rethVault.withdraw(rId, 1, block.timestamp), 0);
        vm.prank(bob);
        assertEq(ysyVault.withdraw(yId, 1, block.timestamp), 1000 ether);
        assertGe(IERC20(RETH).balanceOf(alice), 2 ether - 1);
        assertEq(rethVault.bucket(0).basis, 0);
        assertEq(ysyBold.balanceOf(bob), 1000 ether);
    }

    function test_SyntheticRethSurplusHarvestViaCowDonatesSBoldWithoutPrincipalDebit() public {
        _seedV1ProtocolRewards();
        _stageA();
        _prepareHandoff();
        _stageB(true);
        _enableTestOnlyExecution();
        _safeCall(
            address(rethVault), abi.encodeWithSignature("configureReportBounds(uint256,uint256)", 365 days, 10_000_000)
        );
        _safeCall(address(rethVault), abi.encodeWithSignature("configureEntry(uint256,bool)", 1, true));
        _safeCall(address(rethVault), abi.encodeWithSignature("configureHarvest(uint256,bool)", 1 ether, true));
        _safeCall(address(rethVault), abi.encodeWithSignature("setOperator(address,bool)", OWNER, true));
        address alice = makeAddr("alice");
        deal(RETH, alice, 2 ether);
        vm.startPrank(alice);
        IERC20(RETH).approve(address(rethVault), 2 ether);
        (, uint256 basis) = rethVault.deposit(2 ether, 1, block.timestamp);
        vm.stopPrank();
        uint256 prior = IERC20(RETH).balanceOf(address(rethVault));
        // Synthetic surplus injection; real Rocket Pool rate appreciation is not proven by this test.
        deal(RETH, address(rethVault), prior + 0.2 ether);
        _safeCall(
            address(rethVault), abi.encodeWithSignature("recognizeSurplus(uint8,uint256,bool)", 0, 0.2 ether, false)
        );
        vm.prank(OWNER);
        uint256 collected = rethVault.collectYield(0, 0.2 ether);
        assertEq(collected, 0.2 ether);
        assertEq(rethVault.bucket(0).basis, basis);
        assertEq(next.harvestInventory(0, 0), collected);
        vm.prank(OWNER);
        next.openCowOrder(2, collected, 300 ether, uint32(block.timestamp + 60), 1, bytes32(uint256(3)));
        ISebaCowIntentModule.Order memory order = cow.order(1);
        vm.prank(OWNER);
        cowSettlement.settleMockOrder(order.escrow, 400 ether);
        vm.prank(OWNER);
        next.finalizeCowOrder(1);
        assertEq(next.pendingBold(), 400 ether);
        assertEq(next.pendingProtocolBold(), 0);
        uint256 beforeDonation = IERC20(address(sBold)).balanceOf(address(pyb));
        vm.startPrank(OWNER);
        next.convertBoldToSBold(400 ether, 1, block.timestamp + 60);
        next.donateSBold(next.pendingSBold());
        vm.stopPrank();
        assertEq(IERC20(address(sBold)).balanceOf(address(pyb)) - beforeDonation, 400 ether);
        assertEq(next.harvestInventory(0, 0), 0);
        assertEq(rethVault.bucket(0).basis, basis);
    }

    function _registry(string memory name) internal view returns (address) {
        return IExecutorRocketStorage(REGISTRY).getAddress(keccak256(abi.encodePacked("contract.address", name)));
    }

    function _enableTestOnlyExecution() internal {
        IV2Executor.Limits memory limits = IV2Executor.Limits(
            10 ether,
            10 ether,
            2000 ether,
            1e15,
            0,
            0,
            2 days,
            20_000,
            15 minutes,
            0,
            0,
            0,
            0,
            _registry("rocketDepositPool"),
            _registry("rocketNetworkBalances"),
            _registry("rocketDAOProtocolSettingsDeposit")
        );
        _safeCall(address(executor), abi.encodeCall(SebaV2DirectExecutor.configureLimits, (limits)));
        _safeCall(address(executor), abi.encodeCall(SebaV2DirectExecutor.configureBoldLimit, (2000 ether)));
        _safeCall(address(executor), abi.encodeCall(SebaV2DirectExecutor.setEnabled, (true)));
        _safeCall(address(cow), abi.encodeCall(SebaCowIntentModule.configureLimits, (10 ether, 10 ether, uint32(900))));
        _safeCall(address(cow), abi.encodeCall(SebaCowIntentModule.setEnabled, (true)));
        _safeCall(address(ysyVault), abi.encodeWithSignature("configureEntry(uint256,bool)", 1, true));
        _safeCall(address(next), abi.encodeCall(YieldManagerV2.setOperator, (OWNER, true)));
        _safeCall(address(next), abi.encodeCall(YieldManagerV2.setExecutionEnabled, (true)));
    }

    function executeWrongStageB() external {
        require(msg.sender == address(this));
        _stageB(false);
    }

    function executeStageA() external {
        require(msg.sender == address(this));
        _stageA();
    }
}
