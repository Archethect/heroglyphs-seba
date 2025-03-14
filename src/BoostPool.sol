// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IBoostPool } from "src/interfaces/IBoostPool.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IPoap } from "src/interfaces/IPoap.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IPerpYieldBearingAutoPxEth } from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";

/**
 * @title BoostPool
 * @notice Implements the BoostPool functionality for validator subscriptions, graduation,
 * and reward distribution.
 * @dev Inherits from AccessControl to manage roles. See {IBoostPool} for external interface.
 */
contract BoostPool is AccessControl, IBoostPool {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The stakers union POAP event ID.
    uint256 public constant STAKERS_UNION = 175498;
    /// @notice The duration of the graduation period in blocks (approximately 180 days).
    uint256 public constant GRADUATION_DURATION_IN_BLOCKS = 1_296_000;

    /// @notice Role identifier for administrative functions.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role identifier for automator functions.
    bytes32 public constant AUTOMATOR_ROLE = keccak256("AUTOMATOR_ROLE");

    /*//////////////////////////////////////////////////////////////
                              STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBoostPool
    IPoap public immutable poap;
    /// @inheritdoc IBoostPool
    IPerpYieldBearingAutoPxEth public immutable pybapxETH;
    /// @inheritdoc IBoostPool
    IYieldManager public yieldManager;

    /// @notice Mapping from a withdrawal address to its delegated reward recipient.
    mapping(address => address) public override rewardRecipient;
    /// @notice Mapping from a validator ID to the block number when it was registered.
    mapping(uint256 => uint256) public override validatorRegistrationBlock;
    /// @notice Mapping that indicates whether a validator has already graduated.
    mapping(uint256 => bool) public override validatorIsGraduated;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the BoostPool contract.
     * @dev Sets the initial roles and immutable contract references.
     * @param _admin The address to be granted the ADMIN_ROLE.
     * @param _automator The address to be granted the AUTOMATOR_ROLE.
     * @param _poap The address of the POAP contract.
     * @param _pybapxETH The address of the PerpYieldBearingAutoPxEth contract.
     * @param _yieldManager The address of the yield manager contract.
     */
    constructor(address _admin, address _automator, address _poap, address _pybapxETH, address _yieldManager) {
        if (_admin == address(0)) revert InvalidAddress();
        if (_automator == address(0)) revert InvalidAddress();
        if (_poap == address(0)) revert InvalidAddress();
        if (_pybapxETH == address(0)) revert InvalidAddress();
        if (_yieldManager == address(0)) revert InvalidAddress();

        _grantRole(ADMIN_ROLE, _admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _grantRole(AUTOMATOR_ROLE, _automator);
        _setRoleAdmin(AUTOMATOR_ROLE, ADMIN_ROLE);

        poap = IPoap(_poap);
        pybapxETH = IPerpYieldBearingAutoPxEth(_pybapxETH);
        yieldManager = IYieldManager(_yieldManager);
    }

    /*//////////////////////////////////////////////////////////////
                              FALLBACK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Be able to receive ether donations and MEV rewards
     **/
    fallback() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                              PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBoostPool
    function subscribeValidator(uint64 _validatorId, uint256 _poapId) external override {
        if (poap.ownerOf(_poapId) != msg.sender || poap.tokenEvent(_poapId) != STAKERS_UNION)
            revert NonEligibleStaker(msg.sender, _poapId);
        if (validatorRegistrationBlock[_validatorId] != 0) revert ValidatorAlreadySubscribed(_validatorId);

        validatorRegistrationBlock[_validatorId] = block.number;

        emit SubscribeValidator(msg.sender, _validatorId, _poapId);
    }

    /// @inheritdoc IBoostPool
    function subscribeValidators(uint64[] calldata _validatorIdArray, uint256 _poapId) external override {
        if (poap.ownerOf(_poapId) != msg.sender || poap.tokenEvent(_poapId) != STAKERS_UNION)
            revert NonEligibleStaker(msg.sender, _poapId);

        for (uint256 i = 0; i < _validatorIdArray.length; ) {
            if (validatorRegistrationBlock[_validatorIdArray[i]] != 0)
                revert ValidatorAlreadySubscribed(_validatorIdArray[i]);

            validatorRegistrationBlock[_validatorIdArray[i]] = block.number;

            emit SubscribeValidator(msg.sender, _validatorIdArray[i], _poapId);

            unchecked {
                i += 1;
            }
        }
    }

    /// @inheritdoc IBoostPool
    function setRewardRecipient(address _rewardAddress) external override {
        rewardRecipient[msg.sender] = _rewardAddress;
        emit SetRewardRecipient(msg.sender, _rewardAddress);
    }

    /// @inheritdoc IBoostPool
    function sweepRewards() external override {
        uint256 funds = address(this).balance;
        if (funds > 0) {
            yieldManager.depositFunds{ value: funds }();
            emit RewardsSwept(funds, address(yieldManager));
        }
    }

    /// @inheritdoc IBoostPool
    function graduateValidator(
        uint256 _validatorId,
        address _withdrawalAddress,
        uint256 _attestationPoints
    ) external override onlyRole(AUTOMATOR_ROLE) {
        if (validatorRegistrationBlock[_validatorId] == 0) revert ValidatorNotSubscribed(_validatorId);
        if (validatorIsGraduated[_validatorId]) revert ValidatorAlreadyGraduated(_validatorId);
        if (block.number < validatorRegistrationBlock[_validatorId] + GRADUATION_DURATION_IN_BLOCKS)
            revert GraduationPeriodNotOver(_validatorId);

        if (rewardRecipient[_withdrawalAddress] != address(0)) {
            _withdrawalAddress = rewardRecipient[_withdrawalAddress];
        }
        validatorIsGraduated[_validatorId] = true;
        pybapxETH.distributeShares(_withdrawalAddress, _attestationPoints);
        emit ValidatorGraduated(_validatorId, _withdrawalAddress, _attestationPoints);
    }

    /// @inheritdoc IBoostPool
    function setYieldManager(address _yieldManager) external override onlyRole(ADMIN_ROLE) {
        if (_yieldManager == address(0)) revert InvalidAddress();
        yieldManager = IYieldManager(_yieldManager);
        emit YieldManagerSet(_yieldManager);
    }
}
