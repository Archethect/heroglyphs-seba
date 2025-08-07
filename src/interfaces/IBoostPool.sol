// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPoap } from "src/interfaces/IPoap.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { ISebaVault } from "src/interfaces/ISebaVault.sol";

/**
 * @title IBoostPool
 * @notice Interface for the BoostPool contract.
 * @dev The BoostPool manages validator subscriptions, graduation, and reward distribution.
 */
interface IBoostPool {
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a staker does not own the given POAP or when the POAP event does not match the required stakers union.
    error NonEligibleStaker(address staker, uint256 poapID);
    /// @notice Thrown when an address parameter is the zero address.
    error InvalidAddress();
    /// @notice Thrown when a validator is already subscribed to the pool.
    error ValidatorAlreadySubscribed(uint256 validatorId);
    /// @notice Thrown when a validator has already graduated.
    error ValidatorAlreadyGraduated(uint256 validatorId);
    /// @notice Thrown when a validator is not subscribed.
    error ValidatorNotSubscribed(uint256 validatorId);
    /// @notice Thrown when the graduation period for a validator has not yet passed.
    error GraduationPeriodNotOver(uint256 validatorId);

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the BoostPool contract receives Ether (donations or MEV rewards).
    /// @param sender The address sending Ether.
    /// @param donationAmount The amount of Ether received.
    event EtherReceived(address indexed sender, uint256 donationAmount);

    /// @notice Emitted when a validator is subscribed to the pool.
    /// @param staker The address of the staker who subscribed.
    /// @param validatorId The ID of the validator that was subscribed.
    event SubscribeValidator(address indexed staker, uint256 indexed validatorId);

    /// @notice Emitted when a withdrawal address sets or updates its reward recipient.
    /// @param withdrawalAddress The address that sets its reward recipient.
    /// @param poolRecipient The address designated as the reward recipient.
    event SetRewardRecipient(address indexed withdrawalAddress, address indexed poolRecipient);

    /// @notice Emitted when rewards (Ether) are swept into the yield manager.
    /// @param amount The amount of Ether swept.
    /// @param yieldManager The address of the yield manager that receives the funds.
    event RewardsSwept(uint256 amount, address indexed yieldManager);

    /// @notice Emitted when the yield manager address is updated.
    /// @param yieldManager The new yield manager address.
    event YieldManagerSet(address indexed yieldManager);

    /// @notice Emitted when a validator graduates, receiving reward shares.
    /// @param validatorId The ID of the validator that graduated.
    /// @param withdrawalAddress The address that received the graduation rewards.
    /// @param attestationPoints The number of attestation points used to calculate the reward.
    event ValidatorGraduated(uint256 indexed validatorId, address indexed withdrawalAddress, uint256 attestationPoints);

    /// @notice Emitted when the Seba Vault contract address is updated.
    /// @param _sebaVault The new Seba Vault contract address.
    event SebaVaultSet(address _sebaVault);

    /*//////////////////////////////////////////////////////////////
                         PUBLIC CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The duration of the graduation period in blocks (e.g., 180 days).
    function GRADUATION_DURATION_IN_BLOCKS() external view returns (uint256);

    /// @notice The role identifier for administrative functions.
    function ADMIN_ROLE() external view returns (bytes32);

    /// @notice The role identifier for automator functions.
    function AUTOMATOR_ROLE() external view returns (bytes32);

    /// @notice The Seba Vault contract instance.
    function sebaVault() external view returns (ISebaVault);

    /// @notice The yield manager contract instance.
    function yieldManager() external view returns (IYieldManager);

    /// @notice Mapping that returns the reward recipient for a given withdrawal address.
    function rewardRecipient(address) external view returns (address);

    /// @notice Mapping that returns the block number when a validator was registered.
    function validatorRegistrationBlock(uint256) external view returns (uint256);

    /// @notice Mapping that indicates whether a validator has graduated.
    function validatorIsGraduated(uint256) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Subscribes a validator to the BoostPool.
     * @dev A staker must own the specified POAP and the POAP must be from the stakers union.
     * @param _validatorId The ID of the validator to subscribe.
     */
    function subscribeValidator(uint64 _validatorId) external;

    /**
     * @notice Subscribes multiple validators to the BoostPool.
     * @param _validatorIdArray An array of validator IDs to subscribe.
     */
    function subscribeValidators(uint64[] calldata _validatorIdArray) external;

    /**
     * @notice Sets the reward recipient for the caller's withdrawal address.
     * @param _rewardAddress The address to be designated as the reward recipient.
     */
    function setRewardRecipient(address _rewardAddress) external;

    /**
     * @notice Sweeps any Ether held by the BoostPool into the yield manager.
     * @dev This function deposits the entire Ether balance of the contract into the yield manager.
     */
    function sweepRewards() external;

    /**
     * @notice Graduates a validator from the BoostPool, awarding reward shares.
     * @dev Graduation can only occur after the required graduation period has elapsed.
     * If a reward delegation is set for the withdrawal address, rewards are sent to that delegated address.
     * @param _validatorId The ID of the validator to graduate.
     * @param _withdrawalAddress The address to receive the graduation rewards.
     * @param _attestationPoints The total attestation points accumulated by the validator.
     */
    function graduateValidator(uint256 _validatorId, address _withdrawalAddress, uint256 _attestationPoints) external;

    /**
     * @notice Updates the yield manager contract address.
     * @param _yieldManager The new yield manager contract address.
     */
    function setYieldManager(address _yieldManager) external;

    function setSebaVault(address _sebaVault) external;
}
