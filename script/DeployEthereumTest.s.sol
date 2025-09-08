// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IBeefyVault } from "src/vendor/beefy/IBeefyVault.sol";
import { ICurvePool } from "src/vendor/curve/ICurvePool.sol";
import { IQuoter } from "src/vendor/uniswap_v3/IQuoter.sol";
import { ISwapRouter } from "src/vendor/uniswap_v3/ISwapRouter.sol";
import { IWETH } from "src/vendor/various/IWETH.sol";
import { ISBOLD } from "src/vendor/liquity/ISBOLD.sol";
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { Script } from "forge-std/src/Script.sol";
import { YieldManager } from "src/YieldManager.sol";
import {EthToBoldRouter} from "src/EthToBoldRouter.sol";
import {PYBSeba} from "src/PYBSeba.sol";
import {SebaPool} from "src/SebaPool.sol";
import {EUSDUSDCBeefyYieldVault} from "../src/EUSDUSDCBeefyYieldVault.sol";

contract DeployEthereumTest is Script {
    IERC20 internal bold = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D); // Mainnet BOLD contract
    ISBOLD internal sBOLD = ISBOLD(0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11); // Mainnet SBOLD contract
    IWETH internal weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Mainnet WETH contract
    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Mainnet USDC contract
    IEthFlow internal ethFlow = IEthFlow(0xbA3cB449bD2B4ADddBc894D8697F5170800EAdeC); // Mainnet CowSwap EthFlow contract
    AggregatorV3Interface internal ethUsdFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // Mainnet Chainlink ETH/USD contract
    ISwapRouter internal swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Mainnet Uniswap SwapRouter contract
    IQuoter internal quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6); // Mainnet Uniswap Quoter contract
    ICurvePool internal curvePool = ICurvePool(0x08BfA22bB3e024CDfEB3eca53c0cb93bF59c4147); // Mainnet USDe/USDC CurvePool contract
    IBeefyVault internal beefy = IBeefyVault(0x1817CFfc44c78d5aED61420bF48Cc273E504B7BE); // Mainnet Beefy contract
    EthToBoldRouter internal ethToBoldRouter;
    PYBSeba internal pybSeba;
    SebaPool internal sebaPool;
    EUSDUSDCBeefyYieldVault internal eUsdUsdcBeefyYieldVault;
    YieldManager internal yieldManager;

    function run() external {
        //We use a keystore here
        address deployer = msg.sender;
        bytes32 versionSalt = vm.envBytes32("VERSION_SALT_ETHEREUM_TEST");
        vm.startBroadcast(deployer);

        ethToBoldRouter = new EthToBoldRouter{ salt: versionSalt }(address(ethFlow), address(bold), address(ethUsdFeed), deployer, deployer);
        pybSeba = new PYBSeba{ salt: versionSalt }(deployer, ERC20(address(sBOLD)));
        sebaPool = new SebaPool{ salt: versionSalt }(deployer, deployer);
        eUsdUsdcBeefyYieldVault = new EUSDUSDCBeefyYieldVault{ salt: versionSalt }(deployer, deployer, address(weth), address(usdc), address(swapRouter), address(quoter), address(curvePool), address(beefy));
        yieldManager = new YieldManager{ salt: versionSalt }(deployer, deployer, address(sebaPool), address(ethToBoldRouter), address(bold), address(sBOLD), address(pybSeba), address(eUsdUsdcBeefyYieldVault));
        eUsdUsdcBeefyYieldVault.grantRole(eUsdUsdcBeefyYieldVault.YIELDMANAGER_ROLE(), address(yieldManager));
        pybSeba.setSebaPool(address(sebaPool));
        sebaPool.setSebaVault(address(pybSeba));
        sebaPool.setYieldManager(address(yieldManager));
        ethToBoldRouter.grantRole(ethToBoldRouter.YIELD_MANAGER_ROLE(), address(yieldManager));
        vm.stopBroadcast();
    }
}

