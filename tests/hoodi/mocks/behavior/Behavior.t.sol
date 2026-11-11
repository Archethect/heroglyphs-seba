// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";
import { MockUSDC } from "src/mocks/MockUSDC.sol";
import { MockBold } from "src/mocks/MockBold.sol";
import {
    HoodiPriceFeedMock,
    HoodiUniswapMock,
    HoodiCurveMock,
    HoodiBeefyMock,
    HoodiYearnMock,
    HoodiEthFlowMock,
    HoodiCowRelayerMock,
    HoodiCowSettlementMock,
    HoodiBeefyHarvesterMock,
    HoodiSBoldMock
} from "src/mocks/hoodi/HoodiExternalMocks.sol";

contract RejectEth {
    receive() external payable {
        revert("reject ETH");
    }

    function settle(HoodiEthFlowMock flow, address router, uint256 output) external {
        flow.settleMockOrder(router, output);
    }

    function create(HoodiEthFlowMock flow, IEthFlow.Data calldata order) external {
        flow.createOrder{ value: order.sellAmount }(order);
    }

    function invalidate(HoodiEthFlowMock flow, IEthFlow.Data calldata order) external {
        flow.invalidateOrder(order);
    }
}

contract HoodiMocksBehaviorTest is Test {
    MockWETH internal weth;
    MockUSDC internal usdc;
    MockBold internal bold;
    HoodiUniswapMock internal uni;
    HoodiCurveMock internal curve;
    HoodiBeefyMock internal beefy;
    HoodiYearnMock internal yearn;
    HoodiEthFlowMock internal ethFlow;
    HoodiBeefyHarvesterMock internal harvester;

    receive() external payable { }

    function setUp() public {
        vm.chainId(560_048);
        weth = new MockWETH();
        usdc = new MockUSDC();
        bold = new MockBold();
        uni = new HoodiUniswapMock(address(weth), address(usdc));
        curve = new HoodiCurveMock(address(usdc));
        beefy = new HoodiBeefyMock(address(curve));
        yearn = new HoodiYearnMock(address(bold), "mock", "m");
        ethFlow = new HoodiEthFlowMock(address(this));
        harvester = new HoodiBeefyHarvesterMock();
    }

    function test_FeedAndHarvesterViewsPauseAndFailures() public {
        HoodiPriceFeedMock feed = new HoodiPriceFeedMock(2000e8, address(this));
        assertEq(feed.decimals(), 8);
        vm.warp(18);
        feed.setUpdatedAt(17);
        (, int256 answer, uint256 started, uint256 updated,) = feed.latestRoundData();
        assertEq(answer, 2000e8);
        assertEq(started, 17);
        assertEq(updated, 17);
        assertFalse(harvester.paused());
        harvester.harvest();
        assertEq(harvester.harvestCount(), 1);
        harvester.setPaused(true);
        vm.expectRevert(bytes("mock paused"));
        harvester.harvest();
        harvester.setPaused(false);
        harvester.harvest();
        assertEq(harvester.harvestCount(), 2);
    }

    function test_UniswapBothDirectionsAndBadPairParameterMinimum() public {
        vm.deal(address(this), 1 ether);
        weth.deposit{ value: 1 ether }();
        assertEq(uni.weth(), address(weth));
        assertEq(uni.usdc(), address(usdc));
        assertEq(uni.quoteExactInputSingle(address(weth), address(usdc), 500, 1 ether, 0), 2000e6);
        assertEq(uni.quoteExactInputSingle(address(usdc), address(weth), 500, 2000e6, 0), 1 ether);
        vm.expectRevert(bytes("mock parameters"));
        uni.quoteExactInputSingle(address(weth), address(usdc), 3000, 1 ether, 0);
        vm.expectRevert(bytes("mock parameters"));
        uni.quoteExactInputSingle(address(weth), address(usdc), 500, 1 ether, 1);
        vm.expectRevert(bytes("mock pair"));
        uni.quoteExactInputSingle(address(weth), address(bold), 500, 1 ether, 0);
        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams(
            address(weth), address(usdc), 500, address(this), block.timestamp, 1 ether, 2000e6, 0
        );
        weth.approve(address(uni), 1 ether);
        vm.expectRevert(bytes("mock parameters"));
        p.deadline = block.timestamp - 1;
        uni.exactInputSingle(p);
        p.deadline = block.timestamp;
        p.amountOutMinimum = 2000e6 + 1;
        vm.expectRevert(bytes("mock minimum"));
        uni.exactInputSingle(p);
        p.amountOutMinimum = 2000e6;
        assertEq(uni.exactInputSingle(p), 2000e6);
        assertEq(usdc.balanceOf(address(this)), 2000e6);
        usdc.approve(address(uni), 2000e6);
        p.tokenIn = address(usdc);
        p.tokenOut = address(weth);
        p.amountIn = 2000e6;
        p.amountOutMinimum = 1 ether;
        assertEq(uni.exactInputSingle(p), 1 ether);
        assertEq(weth.balanceOf(address(this)), 1 ether);
    }

    function test_CurveAndBeefyViewsSuccessAndInvalidInputs() public {
        usdc.mint(2000e6, address(this));
        usdc.approve(address(curve), 2000e6);
        uint256[] memory amounts = new uint256[](2);
        amounts[1] = 2000e6;
        assertEq(curve.usdc(), address(usdc));
        assertEq(curve.get_virtual_price(), 1e18);
        assertEq(curve.calc_token_amount(amounts, true), 2000 ether);
        assertEq(curve.calc_withdraw_one_coin(2000 ether, 1), 2000e6);
        vm.expectRevert(bytes("mock coin"));
        curve.calc_withdraw_one_coin(2000 ether, 0);
        uint256[] memory wrong = new uint256[](1);
        vm.expectRevert(bytes("mock amounts"));
        curve.calc_token_amount(wrong, true);
        vm.expectRevert(bytes("mock amounts"));
        curve.add_liquidity(wrong, 0);
        amounts[0] = 1;
        vm.expectRevert(bytes("mock amounts"));
        curve.add_liquidity(amounts, 0);
        amounts[0] = 0;
        vm.expectRevert(bytes("mock minimum"));
        curve.add_liquidity(amounts, 2000 ether + 1);
        assertEq(curve.add_liquidity(amounts, 2000 ether), 2000 ether);
        assertEq(curve.balanceOf(address(this)), 2000 ether);
        assertEq(beefy.want(), address(curve));
        curve.approve(address(beefy), 2000 ether);
        beefy.depositAll();
        assertEq(beefy.balanceOf(address(this)), 2000 ether);
        assertEq(beefy.getPricePerFullShare(), 1e18);
        beefy.withdraw(2000 ether);
        vm.expectRevert(bytes("mock coin"));
        curve.remove_liquidity_one_coin(2000 ether, 0, 0);
        vm.expectRevert(bytes("mock minimum"));
        curve.remove_liquidity_one_coin(2000 ether, 1, 2000e6 + 1);
        assertEq(curve.remove_liquidity_one_coin(2000 ether, 1, 2000e6), 2000e6);
        assertEq(usdc.balanceOf(address(this)), 2000e6);
    }

    function test_YearnAndSBoldDirectTokenOperations() public {
        assertEq(yearn.asset(), address(bold));
        assertEq(yearn.apiVersion(), "3.0.4");
        assertEq(yearn.previewDeposit(100), 100);
        assertEq(yearn.convertToAssets(100), 100);
        assertEq(yearn.maxRedeem(address(this)), 0);
        bold.mint(address(this), 100);
        bold.approve(address(yearn), 100);
        assertEq(yearn.deposit(100, address(this)), 100);
        assertEq(yearn.totalAssets(), 100);
        assertEq(yearn.maxRedeem(address(this)), 100);
        vm.expectRevert(bytes("mock redemption"));
        yearn.redeem(100, address(this), address(this), 1);
        vm.expectRevert(bytes("mock redemption"));
        yearn.redeem(100, address(this), address(0xBEEF), 0);
        assertEq(yearn.redeem(100, address(this), address(this), 0), 100);
        assertEq(yearn.totalAssets(), 0);
        HoodiSBoldMock shares = new HoodiSBoldMock(bold);
        assertEq(shares.previewDeposit(100), 100);
        bold.approve(address(shares), 100);
        assertEq(shares.deposit(100, address(this)), 100);
        assertEq(shares.balanceOf(address(this)), 100);
        assertEq(shares.withdraw(100, address(this), address(this)), 100);
    }

    function _order(uint256 amount, uint256 minimum) internal view returns (IEthFlow.Data memory) {
        return IEthFlow.Data({
            buyToken: IERC20(address(bold)),
            receiver: address(this),
            sellAmount: amount,
            buyAmount: minimum,
            appData: bytes32(uint256(1)),
            feeAmount: 0,
            validTo: uint32(block.timestamp + 60),
            partiallyFillable: false,
            quoteId: 0
        });
    }

    function test_EthFlowCreateRefundFillAndFailureBranches() public {
        vm.deal(address(this), 3 ether);
        IEthFlow.Data memory order = _order(1 ether, 1900 ether);
        vm.expectRevert(bytes("mock order"));
        ethFlow.createOrder{ value: 0 }(order);
        order.sellAmount = 0;
        vm.expectRevert(bytes("mock order"));
        ethFlow.createOrder{ value: 0 }(order);
        order.sellAmount = 1 ether;
        bytes32 uid = ethFlow.createOrder{ value: 1 ether }(order);
        assertEq(ethFlow.activeUid(address(this)), uid);
        vm.expectRevert(bytes("mock order"));
        ethFlow.createOrder{ value: 1 ether }(order);
        IEthFlow.Data memory wrong = _order(1 ether, 1900 ether);
        wrong.buyAmount = 1;
        vm.expectRevert(bytes("mock order"));
        ethFlow.invalidateOrder(wrong);
        ethFlow.invalidateOrder(order);
        assertEq(ethFlow.activeUid(address(this)), bytes32(0));
        vm.expectRevert(bytes("mock order"));
        ethFlow.invalidateOrder(order);
        ethFlow.createOrder{ value: 1 ether }(order);
        vm.prank(address(0xBEEF));
        vm.expectRevert(bytes("mock solver only"));
        ethFlow.settleMockOrder(address(this), 1950 ether);
        vm.expectRevert(bytes("mock fill"));
        ethFlow.settleMockOrder(address(this), 1899 ether);
        vm.warp(block.timestamp + 61);
        vm.expectRevert(bytes("mock fill"));
        ethFlow.settleMockOrder(address(this), 1950 ether);
        vm.warp(block.timestamp - 61);
        ethFlow.settleMockOrder(address(this), 1950 ether);
        assertEq(bold.balanceOf(address(this)), 1950 ether);
        assertEq(ethFlow.activeUid(address(this)), bytes32(0));
    }

    function test_EthFlowRejectingSolverCannotConsumeOrder() public {
        RejectEth rejecting = new RejectEth();
        HoodiEthFlowMock flow = new HoodiEthFlowMock(address(rejecting));
        vm.deal(address(this), 1 ether);
        IEthFlow.Data memory order = _order(1 ether, 1900 ether);
        flow.createOrder{ value: 1 ether }(order);
        vm.expectRevert(bytes("mock ETH transfer"));
        rejecting.settle(flow, address(this), 1950 ether);
        assertTrue(flow.activeUid(address(this)) != bytes32(0));
    }

    function test_EthFlowRejectingRouterCannotReceiveRefund() public {
        RejectEth rejecting = new RejectEth();
        IEthFlow.Data memory order = _order(1 ether, 1900 ether);
        vm.deal(address(rejecting), 1 ether);
        rejecting.create(ethFlow, order);
        bytes32 uid = ethFlow.activeUid(address(rejecting));
        assertTrue(uid != bytes32(0));
        vm.expectRevert(bytes("mock refund"));
        rejecting.invalidate(ethFlow, order);
        assertEq(ethFlow.activeUid(address(rejecting)), uid);
    }

    function test_CowRelayerAndSettlementUnauthorizedViews() public {
        HoodiCowSettlementMock settlement = new HoodiCowSettlementMock(address(bold), address(this));
        assertTrue(settlement.domainSeparator() != bytes32(0));
        address relayer = settlement.vaultRelayer();
        assertTrue(relayer.code.length > 0);
        vm.expectRevert(bytes("mock settlement only"));
        HoodiCowRelayerMock(relayer).spend(address(bold), address(this), 1);
        bytes memory uid = hex"1234";
        settlement.setPreSignature(uid, true);
        assertTrue(settlement.preSigned(address(this), keccak256(uid)));
        settlement.setPreSignature(uid, false);
        assertFalse(settlement.preSigned(address(this), keccak256(uid)));
        vm.prank(address(0xBEEF));
        vm.expectRevert(bytes("mock solver only"));
        settlement.settleMockOrder(address(0), 1);
    }
}
