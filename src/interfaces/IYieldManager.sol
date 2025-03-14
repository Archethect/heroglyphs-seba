// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IApxETH } from "src/vendor/dinero/IApxETH.sol";
import { IApxETHVault } from "src/interfaces/IApxETHVault.sol";
import { IPerpYieldBearingAutoPxEth } from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";

/**
 * @title IYieldManager
 * @notice Interface for the YieldManager contract.
 * @dev The YieldManager collects and distributes yield from an ApxETHVault,
 * manages user deposits, and allows fund retrieval after a lock period.
 */
interface IYieldManager {
    /*//////////////////////////////////////////////////////////////
                           STRUCTS
 //////////////////////////////////////////////////////////////*/
    /**
     * @notice Represents a deposit in the YieldManager.
     * @param lockUntil The timestamp until which the deposit is locked.
     * @param amount The amount of assets deposited.
     * @param depositor The address that made the deposit.
     */
    struct Deposit {
        uint32 lockUntil;
        uint128 amount;
        address depositor;
    }

    /*//////////////////////////////////////////////////////////////
                           ERRORS
 //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an address parameter is the zero address.
    error InvalidAddress();
    /// @notice Thrown when the depositor of a deposit is not valid.
    /// @param depositor The address that attempted to retrieve funds.
    error InvalidDepositor(address depositor);
    /// @notice Thrown when a user attempts to retrieve funds before the deposit lock period expires.
    /// @param timestamp The current block timestamp.
    /// @param lockUntil The timestamp until which the deposit is locked.
    error DepositStillLocked(uint256 timestamp, uint256 lockUntil);

    /*//////////////////////////////////////////////////////////////
                           EVENTS
 //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when yield is distributed from the ApxETHVault.
    /// @param caller The address that triggered the distribution.
    /// @param receiver The address that ultimately receives the yield-bearing shares.
    /// @param amount The amount of ApxETH processed.
    event YieldDistributed(address indexed caller, address indexed receiver, uint256 amount);

    /// @notice Emitted when funds are deposited into the YieldManager.
    /// @param depositId The identifier of the deposit.
    /// @param depositor The address that made the deposit.
    /// @param amount The amount of assets deposited.
    event FundsDeposited(uint256 indexed depositId, address indexed depositor, uint256 amount);

    /// @notice Emitted when funds are retrieved from the YieldManager.
    /// @param depositId The identifier of the deposit.
    /// @param depositor The address that retrieved the funds.
    /// @param amount The amount of assets retrieved.
    event FundsRetrieved(uint256 indexed depositId, address indexed depositor, uint256 amount);

    /// @notice Emitted when the yield flow is activated.
    event YieldFlowActivated();

    /*//////////////////////////////////////////////////////////////
                      PUBLIC VARIABLES (Getters)
 //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current deposit identifier.
    function depositId() external view returns (uint256);

    /// @notice Returns the deposit information for a given deposit id.
    /// @param id The deposit identifier.
    /// @return lockUntil The timestamp until which the deposit is locked.
    /// @return amount The amount deposited.
    /// @return depositor The address that made the deposit.
    function deposits(uint256 id) external view returns (uint32 lockUntil, uint128 amount, address depositor);

    /// @notice Returns the BoostPool contract address.
    function boostPool() external view returns (address);

    /// @notice Returns the ApxETH contract instance.
    function apxETH() external view returns (IApxETH);

    /// @notice Returns the ApxETHVault contract instance.
    function apxEthVault() external view returns (IApxETHVault);

    /// @notice Returns the PerpYieldBearingAutoPxEth contract instance.
    function pybapxEth() external view returns (IPerpYieldBearingAutoPxEth);

    /// @notice Returns the deposit lock duration (in seconds).
    function DEPOSIT_LOCK_DURATION() external view returns (uint32);

    /// @notice The role identifier for administrative functions.
    function ADMIN_ROLE() external view returns (bytes32);

    /// @notice The role identifier for automator functions.
    function AUTOMATOR_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                           FUNCTIONS
 //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits funds into the YieldManager.
     * @dev The caller must send ETH. The deposited funds are forwarded to the ApxETHVault.
     */
    function depositFunds() external payable;

    /**
     * @notice Distributes yield by claiming yield from the ApxETHVault and topping up the pybapxEth vault.
     * @dev This function processes yield and emits a {YieldDistributed} event.
     */
    function distributeYield() external;

    /**
     * @notice Retrieves funds from a deposit.
     * @dev The deposit can only be retrieved if its lock period has expired.
     * Reverts with {InvalidDepositor} or {DepositStillLocked} on failure.
     * @param id The deposit identifier.
     */
    function retrieveFunds(uint32 id) external;

    /**
     * @notice Activates the yield flow.
     * @dev Claims yield from the ApxETHVault and updates the internal deposit 0.
     * Emits {FundsDeposited} and {YieldFlowActivated} events.
     */
    function activateYieldFlow() external;
}
