// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Modifiers } from "tests/utils/modifiers.sol";
import { PYBSeba } from "src/PYBSeba.sol";
import { SebaPool } from "src/SebaPool.sol";
import { YieldManager } from "src/YieldManager.sol";
import { MockSimpleYieldManager } from "../src/mocks/MockSimpleYieldManager.sol";
import { EthToBoldRouter } from "../src/EthToBoldRouter.sol";
import { EUSDUSDCBeefyYieldVault } from "../src/EUSDUSDCBeefyYieldVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISBOLD } from "src/vendor/liquity/ISBOLD.sol";
import { IWETH } from "src/vendor/various/IWETH.sol";
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IQuoter } from "src/vendor/uniswap_v3/IQuoter.sol";
import { ICurvePool } from "src/vendor/curve/ICurvePool.sol";
import { IBeefyVault } from "src/vendor/beefy/IBeefyVault.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";

/* solhint-disable max-states-count */
contract BaseTest is Modifiers {
    uint256 internal mainnetFork;

    SebaPool internal sebaPool;
    PYBSeba internal pybSeba;
    EthToBoldRouter internal ethToBoldRouter;
    YieldManager internal yieldManager;
    EUSDUSDCBeefyYieldVault internal eUsdUsdcBeefyYieldVault;
    MockSimpleYieldManager internal mockSimpleYieldManager;
    IERC20 internal bold;
    ISBOLD internal sBOLD;
    IWETH internal weth;
    IERC20 internal usdc;
    IEthFlow internal ethFlow;
    AggregatorV3Interface internal ethUsdFeed;
    ISwapRouter internal swapRouter;
    IQuoter internal quoter;
    ICurvePool internal curvePool;
    IBeefyVault internal beefy;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC"));
        vm.selectFork(mainnetFork);

        _setupUsers();
        _setupContractsAndMocks();
        _grantRoles();

        setVariables(users, contracts);
    }

    function _setupUsers() internal {
        users.admin = createUser("admin");
        users.automator = createUser("automator");
        users.validator = createUser("validator");
        users.nonValidator = createUser("nonValidator");
        users.yieldManager = createUser("yieldManager");
    }

    function _setupContractsAndMocks() internal {
        vm.startPrank(users.admin);
        mockSimpleYieldManager = new MockSimpleYieldManager();
        bold = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D); // Mainnet BOLD contract
        sBOLD = ISBOLD(0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11); // Mainnet SBOLD contract
        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Mainnet WETH contract
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Mainnet USDC contract
        ethFlow = IEthFlow(0xbA3cB449bD2B4ADddBc894D8697F5170800EAdeC); // Mainnet CowSwap EthFlow contract
        // Mainnet Chainlink ETH/USD contract
        ethUsdFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Mainnet Uniswap SwapRouter contract
        quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6); // Mainnet Uniswap Quoter contract
        curvePool = ICurvePool(0x08BfA22bB3e024CDfEB3eca53c0cb93bF59c4147); // Mainnet USDe/USDC CurvePool contract
        beefy = IBeefyVault(0x1817CFfc44c78d5aED61420bF48Cc273E504B7BE); // Mainnet Beefy contract

        ethToBoldRouter = new EthToBoldRouter(
            address(ethFlow),
            address(bold),
            address(ethUsdFeed),
            users.admin,
            users.yieldManager
        );
        pybSeba = new PYBSeba(users.admin, ERC20(address(sBOLD)));
        sebaPool = new SebaPool(users.admin, users.automator);
        eUsdUsdcBeefyYieldVault = new EUSDUSDCBeefyYieldVault(
            users.admin,
            users.yieldManager,
            address(weth),
            address(usdc),
            address(swapRouter),
            address(quoter),
            address(curvePool),
            address(beefy)
        );
        pybSeba.setSebaPool(address(sebaPool));
        sebaPool.setSebaVault(address(pybSeba));
        vm.stopPrank();

        contracts.sBOLD = address(sBOLD);
        contracts.bold = address(bold);
        contracts.weth = address(weth);
        contracts.usdc = address(usdc);
        contracts.beefy = address(beefy);
        contracts.curvePool = address(curvePool);
        contracts.swapRouter = address(swapRouter);
        contracts.ethUsdFeed = address(ethUsdFeed);
        contracts.quoter = address(quoter);
        contracts.ethFlow = address(ethFlow);
        contracts.sebaPool = address(sebaPool);
        contracts.pybSeba = address(pybSeba);
        contracts.yieldManager = address(yieldManager);
        contracts.mockSimpleYieldManager = address(mockSimpleYieldManager);
        contracts.ethToBoldRouter = address(ethToBoldRouter);
        contracts.eUsdUsdcBeefyYieldVault = address(eUsdUsdcBeefyYieldVault);
    }

    /* solhint-disable no-empty-blocks */
    function _grantRoles() internal {}
    /* solhint-enable no-empty-blocks */
}
/* solhint-enable max-states-count */
