// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BaseDripVault
 * @notice Abstract base contract for a drip vault.
 * @dev Implements common functionality for deposit, withdrawal, and yield processing.
 */
abstract contract BaseDripVault is IDripVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The address of the yield manager.
    address public yieldManager;
    /// @notice Internal accumulator for total deposit amount.
    uint256 internal totalDeposit;

    /**
     * @notice Modifier that restricts access to only the designated yield manager.
     * @dev Reverts with {NotYieldManager} if msg.sender is not equal to yieldManager.
     */
    modifier onlyYieldManager() {
        if (msg.sender != yieldManager) revert NotYieldManager();
        _;
    }

    /**
     * @notice Constructs the BaseDripVault.
     * @dev Initializes the vault with an owner.
     * @param _owner The address of the vault owner.
     */
    constructor(address _owner) Ownable(_owner) {}

    /// @inheritdoc IDripVault
    function deposit() external payable override nonReentrant onlyYieldManager returns (uint256 depositAmount_) {
        if (msg.value == 0) revert InvalidAmount();
        totalDeposit += msg.value;
        return _afterDeposit(msg.value);
    }

    /**
     * @notice Internal hook that is called after a deposit is made.
     * @dev Must be implemented by derived contracts.
     * @param _amount The amount of assets deposited.
     * @return depositAmount_ The resulting amount credited (in shares).
     */
    function _afterDeposit(uint256 _amount) internal virtual returns (uint256 depositAmount_);

    /// @inheritdoc IDripVault
    function withdraw(
        address _to,
        uint256 _amount
    ) external override nonReentrant onlyYieldManager returns (uint256 withdrawAmount_) {
        withdrawAmount_ = _beforeWithdrawal(_to, _amount);
        totalDeposit -= _amount;
        return withdrawAmount_;
    }

    /**
     * @notice Internal hook that is called before a withdrawal.
     * @dev Must be implemented by derived contracts.
     * @param _to The address to receive the withdrawal.
     * @param _amount The amount to withdraw.
     * @return withdrawalAmount_ The resulting withdrawal amount.
     */
    function _beforeWithdrawal(address _to, uint256 _amount) internal virtual returns (uint256 withdrawalAmount_);

    /**
     * @notice Transfers funds (ETH or ERC20) from the vault.
     * @dev If transferring ETH, uses call with value; otherwise uses SafeERC20.
     * @param _asset The asset address (address(0) for ETH).
     * @param _to The recipient address.
     * @param _amount The amount to transfer.
     */
    function _transfer(address _asset, address _to, uint256 _amount) internal {
        if (_amount == 0) return;
        if (_asset == address(0)) {
            (bool success, ) = _to.call{ value: _amount }("");
            if (!success) revert FailedToSendETH();
        } else {
            SafeERC20.safeTransfer(IERC20(_asset), _to, _amount);
        }
    }

    /**
     * @notice Sets the yield manager address.
     * @dev Can only be called by the owner. Emits a {YieldManagerUpdated} event.
     * @param _yieldManager The new yield manager address.
     */
    function setYieldManager(address _yieldManager) external onlyOwner {
        if (_yieldManager == address(0)) revert ZeroAddress();
        yieldManager = _yieldManager;
        emit YieldManagerUpdated(_yieldManager);
    }

    /// @inheritdoc IDripVault
    function getTotalDeposit() public view override returns (uint256) {
        return totalDeposit;
    }

    /// @inheritdoc IDripVault
    function getInputToken() external pure override returns (address) {
        return address(0);
    }
}
