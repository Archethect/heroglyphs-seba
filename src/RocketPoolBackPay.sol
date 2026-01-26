// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IRocketPoolBackPay } from "src/interfaces/IRocketPoolBackPay.sol";

/**
 * @title RocketPoolBackPay
 * @notice Implements the Seba RocketPoolBackPay functionality for allowing RocketPool node operators to backpay
 * their Execution Layer rewards.
 */
contract RocketPoolBackPay is IRocketPoolBackPay {

    /*//////////////////////////////////////////////////////////////
                             IMMUTABLES
   //////////////////////////////////////////////////////////////*/


    /// @inheritdoc IRocketPoolBackPay
    address public immutable sebaPool;

    /*//////////////////////////////////////////////////////////////
                              STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRocketPoolBackPay
    mapping(uint64 => uint256) public backPayPerMiniPool;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the RocketPoolBackPay contract.
     * @dev Sets the Seba Pool address.
     * @param _sebaPool The address to be granted the ADMIN_ROLE.
     */
    constructor(address _sebaPool) {
        if (_sebaPool == address(0)) revert InvalidAddress();

        sebaPool = _sebaPool;
    }


    /*//////////////////////////////////////////////////////////////
                              PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRocketPoolBackPay
    function backPaySebaForMinipools(uint64[] calldata _validatorIdArray, uint256[] calldata _backPayArray) external payable override {
        if(_validatorIdArray.length != _backPayArray.length) revert InvalidArrayLength();
        uint256 totalToPay;
        for (uint256 i = 0; i < _validatorIdArray.length; ) {

            // Add payments to total and individual minipool.
            totalToPay += _backPayArray[i];
            backPayPerMiniPool[_validatorIdArray[i]] += _backPayArray[i];

            emit BackPayMinipool(msg.sender, _validatorIdArray[i], _backPayArray[i], block.number);

            unchecked {
                i += 1;
            }
        }
        if(totalToPay != msg.value) revert InvalidTotalBackPay(totalToPay, msg.value);
        // Send to SebaPool
        (bool ok, ) = sebaPool.call{ value: totalToPay }("");
        if (!ok) revert TransferFailed();
    }
}
