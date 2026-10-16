// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IYBoldYieldVault } from "src/interfaces/IYBoldYieldVault.sol";

/**
 * @title IYBoldConfigValidator
 * @notice Stateless one-time validation for a yBOLD proxy's initialization graph.
 */
interface IYBoldConfigValidator {
    /**
     * @notice Reverts unless every authority and integration is a compatible deployed contract.
     */
    function validate(IYBoldYieldVault.InitializationParams calldata params) external view;
}
