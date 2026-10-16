// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IYBoldConfigValidator } from "src/interfaces/IYBoldConfigValidator.sol";
import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { ICurveStableSwapNG } from "src/vendor/curve/ICurveStableSwapNG.sol";
import { IYearnVault } from "src/vendor/yearn/IYearnVault.sol";

/**
 * @title YBoldConfigValidator
 * @notice Stateless validation split out of the adapter's runtime bytecode and used only during initialization.
 */
contract YBoldConfigValidator is IYBoldConfigValidator {
    /// @inheritdoc IYBoldConfigValidator
    function validate(IYBoldYieldVault.InitializationParams calldata params) external view {
        _requireContract(params.admin);
        _requireContract(params.yieldManager);
        _requireContract(params.upgradeAuthority);
        _requireContract(params.recoveryTreasury);
        _requireContract(params.weth);
        _requireContract(params.usdc);
        _requireContract(params.bold);
        _requireContract(params.router);
        _requireContract(params.boldUsdcPool);
        _requireContract(params.yearnBold);
        _requireContract(params.stakedYearnBold);
        _requireContract(params.ethUsd);
        _requireContract(params.usdcUsd);

        _requireDecimals(params.weth, 18);
        _requireDecimals(params.usdc, 6);
        _requireDecimals(params.bold, 18);
        _requireDecimals(params.yearnBold, 18);
        _requireDecimals(params.stakedYearnBold, 18);

        ICurveStableSwapNG pool = ICurveStableSwapNG(params.boldUsdcPool);
        _requireAsset(params.boldUsdcPool, params.bold, pool.coins(0));
        _requireAsset(params.boldUsdcPool, params.usdc, pool.coins(1));
        _requireAsset(params.yearnBold, params.bold, IYearnVault(params.yearnBold).asset());
        _requireAsset(params.stakedYearnBold, params.yearnBold, IYearnVault(params.stakedYearnBold).asset());

        uint8 ethDecimals = AggregatorV3Interface(params.ethUsd).decimals();
        uint8 usdcDecimals = AggregatorV3Interface(params.usdcUsd).decimals();
        if (ethDecimals > 18) revert IYBoldYieldVault.InvalidDecimals(params.ethUsd, 18, ethDecimals);
        if (usdcDecimals > 18) revert IYBoldYieldVault.InvalidDecimals(params.usdcUsd, 18, usdcDecimals);
    }

    function _requireContract(address target) private view {
        if (target == address(0)) revert IYBoldYieldVault.InvalidAddress();
        if (target.code.length == 0) revert IYBoldYieldVault.InvalidContract(target);
    }

    function _requireDecimals(address token, uint8 expected) private view {
        uint8 actual = IERC20Metadata(token).decimals();
        if (actual != expected) revert IYBoldYieldVault.InvalidDecimals(token, expected, actual);
    }

    function _requireAsset(address integration, address expected, address actual) private pure {
        if (actual != expected) revert IYBoldYieldVault.InvalidAsset(integration, expected, actual);
    }
}
