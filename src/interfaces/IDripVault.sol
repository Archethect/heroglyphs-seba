// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDripVault
 * @notice Interface for a drip vault that accepts deposits, processes yield, and allows withdrawals.
 * @dev The vault is expected to accept ETH deposits and mint or burn corresponding shares.
 */
interface IDripVault {
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a transfer of ETH fails.
    error FailedToSendETH();
    /// @notice Thrown when an invalid deposit amount (usually zero) is provided.
    error InvalidAmount();
    /// @notice Thrown when a caller that is not the designated yield manager attempts a restricted function.
    error NotYieldManager();
    /// @notice Thrown when a native (ETH) deposit is attempted on a vault that does not accept it.
    error NativeNotAccepted();
    /// @notice Thrown when a zero address is provided where a valid address is required.
    error ZeroAddress();
    /// @notice Thrown when attempting to activate yield flow that is already active.
    error YieldFlowAlreadyActivated();
    /// @notice Thrown when attempting to claim yield before yield flow is activated.
    error YieldFlowNotActivated();

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the yield manager address is updated.
    /// @param yieldManager The new yield manager address.
    event YieldManagerUpdated(address indexed yieldManager);

    /// @notice Emitted when interest (yield) is claimed from the vault.
    /// @param receiver The address that received the interest.
    /// @param amount The amount of interest claimed.
    event InterestClaimed(address indexed receiver, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                         PUBLIC VARIABLES (Getters)
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the total amount of assets deposited in the vault.
    function getTotalDeposit() external view returns (uint256);

    /// @notice Returns the input token address of the vault.
    /// @dev For a native ETH vault this can be hard-coded to address(0).
    function getInputToken() external view returns (address);

    /// @notice Returns the output token address of the vault.
    function getOutputToken() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits ETH into the vault.
     * @dev The caller must send ETH as msg.value. The function mints vault shares based on the deposit.
     * @return depositAmount_ The effective deposit amount (in terms of vault shares).
     */
    function deposit() external payable returns (uint256 depositAmount_);

    /**
     * @notice Withdraws ETH or tokens from the vault.
     * @dev The specified amount is withdrawn and the corresponding shares are burned.
     * @param _to The address to receive the withdrawn funds.
     * @param _amount The amount of ETH or token to withdraw.
     * @return withdrawAmount_ The effective amount withdrawn.
     */
    function withdraw(address _to, uint256 _amount) external returns (uint256 withdrawAmount_);

    /**
     * @notice Claims any accrued yield from the vault.
     * @dev The function returns the amount of interest claimed.
     * @return The amount of yield (interest) claimed.
     */
    function claim() external returns (uint256);

    /**
     * @notice Provides a preview of the deposit operation.
     * @dev This function returns the amount of deposit after fees are applied.
     * @param _amount The amount to deposit.
     * @return The net deposit amount that would be credited.
     */
    function previewDeposit(uint256 _amount) external view returns (uint256);
}
