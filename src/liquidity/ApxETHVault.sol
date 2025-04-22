// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseDripVault } from "./BaseDripVault.sol";
import { IApxETH } from "src/vendor/dinero/IApxETH.sol";
import { IPirexEth } from "src/vendor/dinero/IPirexEth.sol";
import { IDripVault } from "src/interfaces/IDripVault.sol";
import { IPerpYieldBearingAutoPxEth } from "src/interfaces/IPerpYieldBearingAutoPxEth.sol";
import { IApxETHVault } from "src/interfaces/IApxETHVault.sol";

/**
 * @title ApxETHVault
 * @notice Drip vault for ApxETH that interacts with PirexEth and a perpetual yield-bearing pxETH vault.
 * @dev Inherits from BaseDripVault and implements IApxETHVault.
 */
contract ApxETHVault is BaseDripVault, IApxETHVault {
    // ===============================================================
    //                        INTERNAL CONSTANTS
    // ===============================================================
    uint256 internal constant DENOMINATOR = 1_000_000;

    // ===============================================================
    //                        PUBLIC STATE VARIABLES
    // ===============================================================
    /// @notice Indicates whether the yield flow has been activated.
    bool public yieldFlowActive;

    /// @notice The ApxETH token contract.
    IApxETH public immutable APXETH;
    /// @notice The PirexEth contract, used for deposit fee calculation.
    IPirexEth public immutable PIREX_ETH;
    /// @notice The Perpetual Yield Bearing Auto PxEth vault.
    IPerpYieldBearingAutoPxEth public immutable PERP_YIELD_BEARING_AUTO_PX_ETH;

    // ===============================================================
    //                          CONSTRUCTOR
    // ===============================================================
    /**
     * @notice Constructs the ApxETHVault.
     * @dev Initializes the BaseDripVault with the owner, sets the token contracts.
     * @param _owner The owner address.
     * @param _apxETH The ApxETH token contract address.
     * @param _pybapxETH The PerpYieldBearingAutoPxEth contract address.
     */
    constructor(address _owner, address _apxETH, address _pybapxETH) BaseDripVault(_owner) {
        APXETH = IApxETH(_apxETH);
        PIREX_ETH = IPirexEth(IApxETH(_apxETH).pirexEth());
        PERP_YIELD_BEARING_AUTO_PX_ETH = IPerpYieldBearingAutoPxEth(_pybapxETH);
    }

    // ===============================================================
    //                     INTERNAL HOOKS OVERRIDES
    // ===============================================================
    /**
     * @notice Hook called after deposit.
     * @dev Deposits to PirexEth are executed here. The fee is subtracted from totalDeposit.
     * @param _amount The amount deposited.
     * @return depositAmount_ The effective deposit amount in ApxETH shares.
     */
    function _afterDeposit(uint256 _amount) internal override returns (uint256 depositAmount_) {
        // ApxETH does not have a 1:1 ratio with ETH, but Pirex does.
        uint256 fee;
        (depositAmount_, fee) = PIREX_ETH.deposit{ value: _amount }(address(this), true);
        totalDeposit -= fee;
        return depositAmount_;
    }

    /**
     * @notice Hook called before withdrawal.
     * @dev Converts the withdrawal amount to ApxETH shares and transfers them.
     * @param _to The address receiving the withdrawn funds.
     * @param _amount The amount to withdraw.
     * @return withdrawalAmount_ The amount in ApxETH shares.
     */
    function _beforeWithdrawal(address _to, uint256 _amount) internal override returns (uint256 withdrawalAmount_) {
        withdrawalAmount_ = APXETH.convertToShares(_amount);
        _transfer(address(APXETH), _to, withdrawalAmount_);
        return withdrawalAmount_;
    }

    // ===============================================================
    //                        EXTERNAL FUNCTIONS
    // ===============================================================

    /// @inheritdoc IDripVault
    function claim() external override nonReentrant onlyYieldManager returns (uint256 interestInApx_) {
        if (!yieldFlowActive) revert YieldFlowNotActivated();
        interestInApx_ = _getPendingClaiming();
        _transfer(address(APXETH), msg.sender, interestInApx_);
        emit InterestClaimed(msg.sender, interestInApx_);
        return interestInApx_;
    }

    /// @inheritdoc IApxETHVault
    function getPendingClaiming() external view returns (uint256) {
        return _getPendingClaiming();
    }

    /**
     * @notice Internal function to compute pending yield.
     * @dev Compares the current total deposit with the maximum redeemable value.
     * @return interestInApx_ The computed yield (in ApxETH shares).
     */
    function _getPendingClaiming() internal view returns (uint256 interestInApx_) {
        uint256 cachedTotalDeposit = getTotalDeposit();
        uint256 maxRedeemInETH = APXETH.convertToAssets(APXETH.maxRedeem(address(this)));
        if (maxRedeemInETH > cachedTotalDeposit) {
            interestInApx_ = APXETH.convertToShares(maxRedeemInETH - cachedTotalDeposit);
        }
        return interestInApx_;
    }

    /// @inheritdoc IDripVault
    function getOutputToken() external view returns (address) {
        return address(APXETH);
    }

    /// @inheritdoc IDripVault
    function previewDeposit(uint256 _amount) external view override returns (uint256 depositAmount_) {
        uint256 feeAmount = (_amount * PIREX_ETH.fees(0)) / DENOMINATOR;
        depositAmount_ = _amount - feeAmount;
        return depositAmount_;
    }

    /// @inheritdoc IApxETHVault
    function activateYieldFlow() external override onlyYieldManager returns (uint256 interest) {
        if (yieldFlowActive) revert YieldFlowAlreadyActivated();
        uint256 pending = _getPendingClaiming();
        if (pending > 0) {
            interest = APXETH.convertToAssets(pending);
            totalDeposit += interest;
        }
        yieldFlowActive = true;
        emit YieldFlowActivated();
        return interest;
    }
}
