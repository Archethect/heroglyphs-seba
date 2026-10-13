// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseScript } from "script/Base.s.sol";
import { console2 } from "forge-std/src/console2.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";

/**
 * @title DeployYBoldYieldVault
 * @notice Idempotent CREATE2 deployment script for the mainnet yBOLD adapter.
 * @dev Running `forge script` without `--broadcast` performs a dry run. Source verification is enabled by adding
 *      Foundry's standard `--verify` flag only after Gate 2 approval.
 */
contract DeployYBoldYieldVault is BaseScript {
    address internal constant YIELD_MANAGER = 0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address internal constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant BOLD_USDC_POOL = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address internal constant ST_YBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address internal constant ETH_USD_FEED = 0xc0053f3FBcCD593758258334Dfce24C2A9A673aD;
    address internal constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    /**
     * @notice Deploys the configured adapter or validates the existing deterministic deployment.
     * @return deployed Deployed or pre-existing yBOLD adapter.
     */
    function run() external returns (YBoldYieldVault deployed) {
        require(block.chainid == 1, "CHAIN_ID");
        address expectedDeployer = vm.envAddress("YBOLD_EXPECTED_DEPLOYER");
        address admin = vm.envAddress("YBOLD_ADMIN");
        bytes32 salt = vm.envBytes32("YBOLD_VERSION_SALT");
        require(broadcaster == expectedDeployer, "DEPLOYER");
        require(admin != address(0), "ADMIN");

        bytes memory constructorArguments = abi.encode(
            admin,
            YIELD_MANAGER,
            WETH,
            USDC,
            BOLD,
            SWAP_ROUTER,
            BOLD_USDC_POOL,
            YBOLD,
            ST_YBOLD,
            ETH_USD_FEED,
            USDC_USD_FEED
        );
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(YBoldYieldVault).creationCode, constructorArguments));
        address predicted = vm.computeCreate2Address(salt, initCodeHash, CREATE2_FACTORY);

        if (predicted.code.length == 0) {
            vm.startBroadcast(broadcaster);
            deployed = new YBoldYieldVault{ salt: salt }(
                admin,
                YIELD_MANAGER,
                WETH,
                USDC,
                BOLD,
                SWAP_ROUTER,
                BOLD_USDC_POOL,
                YBOLD,
                ST_YBOLD,
                ETH_USD_FEED,
                USDC_USD_FEED
            );
            vm.stopBroadcast();
            require(address(deployed) == predicted, "CREATE2_ADDRESS");
        } else {
            deployed = YBoldYieldVault(payable(predicted));
        }

        _validate(deployed, admin);
        console2.log("YBoldYieldVault", address(deployed));
        console2.log("CREATE2 salt");
        console2.logBytes32(salt);
    }

    function _validate(YBoldYieldVault deployed, address admin) internal view {
        require(address(deployed).code.length > 0, "NO_CODE");
        require(deployed.hasRole(deployed.ADMIN_ROLE(), admin), "ADMIN_ROLE");
        require(deployed.hasRole(deployed.YIELDMANAGER_ROLE(), YIELD_MANAGER), "MANAGER_ROLE");
        require(deployed.WETH() == WETH && deployed.USDC() == USDC && deployed.BOLD() == BOLD, "TOKENS");
        require(address(deployed.yBold()) == YBOLD && address(deployed.stYBold()) == ST_YBOLD, "YEARN");
        require(address(deployed.curvePool()) == BOLD_USDC_POOL, "CURVE");
        require(address(deployed.swapRouter()) == SWAP_ROUTER, "ROUTER");
        require(deployed.wethUsdcSlippageBps() == 50 && deployed.boldUsdcSlippageBps() == 50, "SLIPPAGE");
        require(deployed.maxBoldPegDeviationBps() == 100, "PEG");
        require(deployed.normalYearnMaxLossBps() == 0 && deployed.emergencyYearnMaxLossBps() == 100, "LOSS");
    }
}
