// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";
import { RethSupporterVault } from "src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "src/v2/YsyBoldSupporterVault.sol";
import { SebaV2Executor } from "src/v2/SebaV2Executor.sol";
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
    SebaV2Executor internal execution;
    address internal operator;
    function setUp() public virtual {
        if (vm.envOr("SEBA_V2_FRESH_FORK", false)) vm.createSelectFork(vm.envString("MAINNET_RPC"));
        else vm.createSelectFork(vm.envString("MAINNET_RPC"), vm.envOr("SEBA_V2_FORK_BLOCK", uint256(26_255_470)));
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
        execution = new SebaV2Executor(
            IV2Executor.Config(
                address(manager),
                SAFE,
                RETH,
                WETH,
                USDC,
                BOLD,
                YBOLD,
                YSY,
                0xE592427A0AEce92De3Edee1F18E0157C05861564,
                0xEFc6516323FbD28e80B85A497B65A86243a54B3E,
                0xc0053f3FBcCD593758258334Dfce24C2A9A673aD,
                0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
                REGISTRY
            )
        );
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
            3600,
            82800,
            2 days,
            20_000,
            15 minutes,
            50,
            100,
            500,
            100,
            _registry("rocketDepositPool"),
            _registry("rocketNetworkBalances"),
            _registry("rocketDAOProtocolSettingsDeposit")
        );
        vm.startPrank(SAFE);
        execution.configureLimits(l);
        execution.setEnabled(true);
        rVault.configureReportBounds(2 days, 20_000);
        rVault.configureEntry(1, true);
        rVault.configureHarvest(100 ether, true);
        rVault.setOperator(operator, true);
        yVault.configureEntry(1, true);
        yVault.configureHarvest(300_000 ether, true);
        yVault.setOperator(operator, true);
        manager.configureExecution(address(execution), 200 ether, 100 ether, 300_000 ether);
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
        assertGe(IERC20(BOLD).balanceOf(address(manager)), manager.pendingBold());
        assertGe(IERC20(address(old.sBOLD())).balanceOf(address(manager)), manager.pendingSBold());
    }
}
