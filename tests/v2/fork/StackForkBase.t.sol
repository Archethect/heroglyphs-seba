// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";
import { RethSupporterVault } from "src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "src/v2/YsyBoldSupporterVault.sol";
import { SebaV2DirectExecutor } from "src/v2/SebaV2DirectExecutor.sol";
import { SebaCowIntentModule } from "src/v2/cow/SebaCowIntentModule.sol";
import { ISebaCowIntentModule } from "src/interfaces/v2/ISebaCowIntentModule.sol";
import { YieldManager } from "src/YieldManager.sol";
import { SebaPool } from "src/SebaPool.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";
import { IV2SupporterVault } from "src/interfaces/v2/IV2SupporterVault.sol";
import { IExecutorRocketStorage } from "src/vendor/v2/IExecutorProtocols.sol";

/// @notice Real deployed assets and venues; all fixture deployments/impersonation are local fork only.
abstract contract StackForkBase is Test {
    address internal constant SAFE = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address internal constant YSY = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant REGISTRY = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    YieldManager internal old;
    SebaPool internal pool;
    YieldManagerV2 internal manager;
    RethSupporterVault internal rVault;
    YsyBoldSupporterVault internal yVault;
    SebaV2DirectExecutor internal execution;
    SebaCowIntentModule internal cow;
    address internal constant COW = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant SOLVER = 0x5ed864e8f37DCB4f79c5172A815D1B3a9147eaaB;
    address internal operator;
    function setUp() public virtual {
        if (vm.envOr("SEBA_V2_FRESH_FORK", false)) vm.createSelectFork(vm.envString("MAINNET_RPC"));
        else vm.createSelectFork(vm.envString("MAINNET_RPC"), vm.envOr("SEBA_V2_FORK_BLOCK", uint256(26_384_004)));
        emit log_named_uint("Fork snapshot block", block.number);
        emit log_named_bytes32("Fork parent hash", blockhash(block.number - 1));
        operator = makeAddr("local bounded V2 operator");
        old = YieldManager(payable(0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269));
        pool = SebaPool(payable(0xe3B17b4533b339d3CBC26F57199d3fb937129894));
        YieldManagerV2 implementation = YieldManagerV2(payable(deployCode("YieldManagerV2.sol:YieldManagerV2")));
        IYieldManagerV2.Initialization memory c = IYieldManagerV2.Initialization(
            SAFE,
            operator,
            address(pool),
            BOLD,
            address(old.sBOLD()),
            address(old.sebaVault()),
            RETH,
            YSY
        );
        manager = YieldManagerV2(
            payable(address(new ERC1967Proxy(address(implementation), abi.encodeCall(implementation.initialize, (c)))))
        );
        address ri = deployCode("RethSupporterVault.sol:RethSupporterVault");
        rVault = RethSupporterVault(
            address(
                new ERC1967Proxy(
                    ri,
                    abi.encodeCall(RethSupporterVault.initialize, (SAFE, address(manager), RETH, REGISTRY))
                )
            )
        );
        address yi = deployCode("YsyBoldSupporterVault.sol:YsyBoldSupporterVault");
        yVault = YsyBoldSupporterVault(
            address(
                new ERC1967Proxy(
                    yi,
                    abi.encodeCall(YsyBoldSupporterVault.initialize, (SAFE, address(manager), YSY, YBOLD))
                )
            )
        );
        execution = new SebaV2DirectExecutor(
            IV2Executor.Config(
                address(manager),
                SAFE,
                RETH,
                WETH,
                address(0),
                BOLD,
                YBOLD,
                YSY,
                address(0),
                address(0),
                address(0),
                address(0),
                REGISTRY
            )
        );
        cow = new SebaCowIntentModule(address(manager), SAFE, WETH, RETH, BOLD, COW);
        vm.prank(SAFE);
        manager.bindVaults(address(rVault), address(yVault));
    }
    function _registry(string memory name) internal view returns (address) {
        return IExecutorRocketStorage(REGISTRY).getAddress(keccak256(abi.encodePacked("contract.address", name)));
    }
    function _enableTestExecution() internal {
        // TEST-ONLY risk configuration, not a production-approved parameter pack.
        IV2Executor.Limits memory l = IV2Executor.Limits(
            200 ether,
            100 ether,
            300_000 ether,
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
        vm.startPrank(SAFE);
        execution.configureLimits(l);
        execution.configureBoldLimit(1_000_000 ether);
        execution.setEnabled(true);
        rVault.configureReportBounds(2 days, 20_000);
        rVault.configureEntry(1, true);
        rVault.configureHarvest(100 ether, true);
        rVault.setOperator(operator, true);
        yVault.configureEntry(1, true);
        yVault.configureHarvest(300_000 ether, true);
        yVault.setOperator(operator, true);
        manager.configureExecution(address(execution), 200 ether, 100 ether, 300_000 ether);
        manager.configureCowModule(address(cow));
        cow.configureLimits(200 ether, 100 ether, 900);
        cow.setEnabled(true);
        manager.setExecutionEnabled(true);
        vm.stopPrank();
    }
    function _nativeDeposit(
        IV2SupporterVault vault,
        address owner,
        uint256 q
    ) internal returns (uint256 id, uint256 basis) {
        vm.startPrank(SAFE);
        IERC20(vault.asset()).transfer(owner, q);
        vm.stopPrank();
        vm.startPrank(owner);
        IERC20(vault.asset()).approve(address(vault), q);
        (id, basis) = vault.deposit(q, 1, block.timestamp);
        vm.stopPrank();
    }
    function _assertManagerCustody() internal view {
        assertGe(address(manager).balance, manager.pendingEth(0) + manager.pendingEth(1) + manager.pendingEth(2));
        assertGe(
            IERC20(RETH).balanceOf(address(manager)),
            manager.harvestInventory(0, 0) + manager.harvestInventory(0, 1)
        );
        assertGe(
            IERC20(YSY).balanceOf(address(manager)),
            manager.harvestInventory(1, 0) + manager.harvestInventory(1, 1)
        );
        assertGe(IERC20(BOLD).balanceOf(address(manager)), manager.pendingBold() + manager.pendingProtocolBold());
        assertGe(IERC20(address(old.sBOLD())).balanceOf(address(manager)), manager.pendingSBold());
    }
    /// @dev REAL GPv2 settlement/allowlisted solver impersonation, SYNTHETIC BOLD liquidity; not a live market fill.
    function _cowSwap(uint8 source, uint256 amount) internal returns (uint256 output) {
        uint256 id = cow.nextOrderId();
        vm.prank(operator);
        manager.openCowOrder(source, amount, 1, uint32(block.timestamp + 60), id, bytes32(id));
        output = amount * 2000;
        _settleCow(id, output, 96, amount);
        vm.prank(operator);
        manager.finalizeCowOrder(id);
    }
    function _settleCow(uint256 id, uint256 output, uint256 flags, uint256 executed) internal {
        ISebaCowIntentModule.Data memory o = cow.orderData(id);
        address auth = ICowForkSettlement(COW).authenticator();
        assertTrue(ICowForkAuthentication(auth).isSolver(SOLVER));
        // Explicit synthetic settlement inventory, NOT proof of real quote/fill viability.
        deal(BOLD, COW, IERC20(BOLD).balanceOf(COW) + output);
        address[] memory tokens = new address[](2);
        tokens[0] = o.sellToken;
        tokens[1] = BOLD;
        uint256[] memory prices = new uint256[](2);
        prices[0] = output;
        prices[1] = o.sellAmount;
        ICowForkSettlement.Trade[] memory trades = new ICowForkSettlement.Trade[](1);
        trades[0] = ICowForkSettlement.Trade(
            0,
            1,
            o.receiver,
            o.sellAmount,
            o.buyAmount,
            o.validTo,
            o.appData,
            0,
            flags,
            executed,
            abi.encodePacked(o.receiver)
        );
        ICowForkSettlement.Interaction[][3] memory interactions;
        for (uint256 i; i < 3; ++i) interactions[i] = new ICowForkSettlement.Interaction[](0);
        vm.prank(SOLVER);
        ICowForkSettlement(COW).settle(tokens, prices, trades, interactions);
    }
}

interface ICowForkAuthentication {
    function isSolver(address) external view returns (bool);
}
interface ICowForkSettlement {
    struct Trade {
        uint256 sellTokenIndex;
        uint256 buyTokenIndex;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        uint256 flags;
        uint256 executedAmount;
        bytes signature;
    }
    struct Interaction {
        address target;
        uint256 value;
        bytes callData;
    }
    function authenticator() external view returns (address);
    function filledAmount(bytes calldata) external view returns (uint256);
    function freeFilledAmountStorage(bytes[] calldata) external;
    function settle(address[] calldata, uint256[] calldata, Trade[] calldata, Interaction[][3] calldata) external;
}
