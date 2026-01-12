// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRocketPoolBackPay
 * @notice Interface for the RocketPoolBackPay contract.
 * @dev The RocketPoolBackPay contract allows RocketPool node operators to backpay
 * their Execution Layer rewards.
 */
interface IRocketPoolBackPay {
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the validator ID array length is not equal to the back pay amount array
    error InvalidArrayLength();
    /// @notice Thrown when an address parameter is the zero address.
    error InvalidAddress();
    /// @notice Thrown when an the total summed up amount of back payments is not equal to the amount paid
    error InvalidTotalBackPay(uint256 totalToPay, uint256 paid);
    /// @notice Thrown when forwarding the funds to the SebaPool fails.
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a back pay is done for a validator
    /// @param sender The address doing the back pay
    /// @param validatorId The ID of the validator that was back paid.
    /// @param amount The amount that has been paid back
    /// @param block The block number when the payment was done.
    event BackPayMinipool(address indexed sender, uint64 indexed validatorId, uint256 amount, uint256 indexed block);


    /*//////////////////////////////////////////////////////////////
                         PUBLIC CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The Seba Pool contract address.
    function sebaPool() external view returns (address);

    /// @notice Mapping that returns the amount that was paid back per validator
    function backPayPerMiniPool(uint64) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enables minipool operators to back pay their outstanding Seba debt
     * @param _validatorIdArray An array containing all validator IDs to back pay for
     * @param _backPayArray An array containing all amounts to back pay for a validator
     */
    function backPaySebaForMinipools(uint64[] calldata _validatorIdArray, uint256[] calldata _backPayArray) external payable;
}
