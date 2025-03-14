// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IApxETH } from "src/vendor/dinero/IApxETH.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IBoostPool } from "src/interfaces/IBoostPool.sol";
import { IPoap } from "src/interfaces/IPoap.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IPerpYieldBearingAutoPxEth } from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";
import { IApxETHVault } from "src/interfaces/IApxETHVault.sol";

/**
 * @title YieldManager
 * @notice Manages yield processing and user deposits.
 * @dev This contract receives ETH, interacts with the ApxETHVault to claim yield,
 * deposits funds into the pybapxEth vault, and allows users to retrieve funds after a lock period.
 */
contract YieldManager is AccessControl, IYieldManager {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS & ROLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    bytes32 public constant override ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @inheritdoc IYieldManager
    bytes32 public constant override AUTOMATOR_ROLE = keccak256("AUTOMATOR_ROLE");

    /// @notice The deposit lock duration (30 days).
    uint32 public constant override DEPOSIT_LOCK_DURATION = 30 days;

    /*//////////////////////////////////////////////////////////////
                              STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The next deposit id.
    uint256 public override depositId;

    /// @notice The BoostPool contract address.
    address public immutable override boostPool;
    /// @notice The ApxETH contract instance.
    IApxETH public immutable override apxETH;
    /// @notice The ApxETHVault contract instance.
    IApxETHVault public immutable override apxEthVault;
    /// @notice The PerpYieldBearingAutoPxEth contract instance.
    IPerpYieldBearingAutoPxEth public immutable override pybapxEth;

    /// @notice Mapping of deposit id to Deposit details.
    mapping(uint256 => Deposit) public override deposits;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the YieldManager.
     * @dev Sets roles and immutable contract addresses. Reverts if any provided address is zero.
     * @param _admin The address granted the ADMIN_ROLE.
     * @param _automator The address granted the AUTOMATOR_ROLE.
     * @param _boostPool The BoostPool contract address.
     * @param _apxETH The ApxETH contract address.
     * @param _apxEthVault The ApxETHVault contract address.
     * @param _pybapxEth The PerpYieldBearingAutoPxEth contract address.
     */
    constructor(
        address _admin,
        address _automator,
        address _boostPool,
        address _apxETH,
        address _apxEthVault,
        address _pybapxEth
    ) {
        if (_admin == address(0)) revert InvalidAddress();
        if (_automator == address(0)) revert InvalidAddress();
        if (_boostPool == address(0)) revert InvalidAddress();
        if (_apxETH == address(0)) revert InvalidAddress();
        if (_apxEthVault == address(0)) revert InvalidAddress();
        if (_pybapxEth == address(0)) revert InvalidAddress();

        _grantRole(ADMIN_ROLE, _admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _grantRole(AUTOMATOR_ROLE, _automator);
        _setRoleAdmin(AUTOMATOR_ROLE, ADMIN_ROLE);

        boostPool = _boostPool;
        apxETH = IApxETH(_apxETH);
        apxEthVault = IApxETHVault(_apxEthVault);
        pybapxEth = IPerpYieldBearingAutoPxEth(_pybapxEth);
    }

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    function distributeYield() external override {
        apxEthVault.claim();
        uint256 apxETHBalance = apxETH.balanceOf(address(this));
        if (apxETHBalance > 0) {
            apxETH.approve(address(pybapxEth), apxETHBalance);
            pybapxEth.topup(apxETHBalance);
            emit YieldDistributed(msg.sender, address(pybapxEth), apxETHBalance);
        }
    }

    /// @inheritdoc IYieldManager
    function depositFunds() external payable override {
        address depositor = msg.sender;
        if (msg.sender == boostPool) {
            depositor = address(this);
        }
        _depositFunds(depositor);
    }

    /// @inheritdoc IYieldManager
    function retrieveFunds(uint32 id) external override {
        Deposit storage d = deposits[id];
        uint256 returningAmount = d.amount;

        if (d.depositor == address(this)) {
            if (!hasRole(ADMIN_ROLE, msg.sender)) revert InvalidDepositor(msg.sender);
        } else {
            if (d.depositor != msg.sender) revert InvalidDepositor(msg.sender);
        }
        if (d.lockUntil > block.timestamp) revert DepositStillLocked(block.timestamp, d.lockUntil);

        delete deposits[id];

        apxEthVault.withdraw(msg.sender, returningAmount);

        emit FundsRetrieved(id, msg.sender, returningAmount);
    }

    /// @inheritdoc IYieldManager
    function activateYieldFlow() external override onlyRole(AUTOMATOR_ROLE) {
        uint256 interest = apxEthVault.activateYieldFlow();
        Deposit storage d = deposits[0];
        if (d.depositor == address(0)) d.depositor = address(this);
        d.amount += uint128(interest);
        emit FundsDeposited(0, address(this), interest);
        emit YieldFlowActivated();
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function that records a deposit.
     * @dev For external deposits, a new deposit record is created with a lock period.
     * For internal deposits (e.g. from yield or MEV rewards), deposit id 0 is used.
     * @param depositor The address for which the deposit is recorded.
     */
    function _depositFunds(address depositor) internal {
        uint256 sanitizedAmount = apxEthVault.deposit{ value: msg.value }();

        if (depositor == address(this)) {
            // Internal deposits (e.g., from MEV rewards)
            Deposit storage d = deposits[0];
            if (d.depositor == address(0)) d.depositor = address(this);
            d.amount += uint128(sanitizedAmount);
            emit FundsDeposited(0, depositor, sanitizedAmount);
        } else {
            // External deposits (retrievable by the depositor)
            depositId++;
            deposits[depositId] = Deposit({
                depositor: msg.sender,
                amount: uint128(sanitizedAmount),
                lockUntil: uint32(block.timestamp + DEPOSIT_LOCK_DURATION)
            });
            emit FundsDeposited(depositId, depositor, sanitizedAmount);
        }
    }
}
