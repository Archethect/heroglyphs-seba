// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IApxETHVault
/// @notice Interface for the ApxETHVault contract which is a drip vault for ApxETH.
/// @dev Extends the IDripVault interface.
import { IDripVault } from "src/interfaces/IDripVault.sol";

interface IApxETHVault is IDripVault {
    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the yield flow is activated.
    event YieldFlowActivated();

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Activates the yield flow.
     * @dev Can only be called by the yield manager. When activated, it claims any pending yield,
     * increases the vault’s total deposit by the corresponding amount, and then sets yield flow active.
     * Emits a {YieldFlowActivated} event.
     * @return interest The amount of interest (in ETH-equivalent units) that was added.
     */
    function activateYieldFlow() external returns (uint256);

    /**
     * @notice Returns the pending yield available for claiming.
     * @return The pending yield in ApxETH shares.
     */
    function getPendingClaiming() external view returns (uint256);
}
