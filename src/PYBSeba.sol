// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC4626 } from "solmate/src/tokens/ERC4626.sol";
import { IPYBSeba } from "src/interfaces/IPYBSeba.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";

/**
 * @title SebaVault
 * @notice Seba Perpetual Yield vault.
 * @dev Inherits from ERC4626 for vault functionality and AccessControl for role management.
 * Implements the ISebaVault interface.
 */
contract PYBSeba is AccessControl, ERC4626, IPYBSeba {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Role identifier for administrative functions.
    bytes32 public constant override ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice The current share supply cap.
    uint256 public supplyCap;
    /// @notice The total assets currently deposited in the vault.
    uint256 public assetTotal;
    /// @notice The SebaPool contract address.
    address public sebaPool;

    /**
     * @notice Constructs the pybSeba vault.
     * @dev Initializes the ERC4626 vault with the underlying asset, sets the vault name and symbol.
     * @param _admin The address to be granted the ADMIN_ROLE.
     * @param _asset The ERC20 asset used as the underlying asset.
     */
    constructor(address _admin, ERC20 _asset) ERC4626(_asset, "Perpetual Yield Bearing Seba", "pybSeba") {
        if (_admin == address(0)) revert InvalidAddress();

        _grantRole(ADMIN_ROLE, _admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    /**
     * @notice Modifier that restricts execution to the BoostPool contract.
     * @dev Reverts with {NotBoostPool} if msg.sender is not the boostPool.
     */
    modifier onlyBoostPool() {
        if (msg.sender != sebaPool) revert NotSebaPool(msg.sender);
        _;
    }

    /// @inheritdoc IPYBSeba
    function topup(uint256 _amount) public override {
        uint256 preBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 delta = asset.balanceOf(address(this)) - preBalance;
        emit Topup(msg.sender, delta);
        afterDeposit(delta, 0);
    }

    /// @inheritdoc IPYBSeba
    function distributeShares(address _receiver, uint256 _shares) public override onlyBoostPool {
        _mint(_receiver, _shares);
        supplyCap += _shares;
        emit SharesDistributed(_receiver, _shares);
    }

    /**
     * @notice Deposits assets into the vault.
     * @dev Overrides ERC4626 {deposit} with a supply cap check and vault state update.
     * Emits a {Deposit} event.
     * @param _assets The amount of assets to deposit.
     * @param _receiver The address that will receive the minted shares.
     * @return shares The number of shares minted.
     */
    function deposit(uint256 _assets, address _receiver) public override returns (uint256 shares) {
        shares = previewDeposit(_assets);
        if (shares == 0) revert ZeroShares();
        if (shares + totalSupply > supplyCap) revert SupplyCapExceeded();

        uint256 preBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), _assets);
        uint256 delta = asset.balanceOf(address(this)) - preBalance;
        _mint(_receiver, shares);

        emit Deposit(msg.sender, _receiver, delta, shares);

        afterDeposit(delta, shares);
    }

    /**
     * @notice Mints a specified number of shares by depositing the equivalent amount of assets.
     * @dev Overrides ERC4626 {mint} with a supply cap check and vault state update.
     * Emits a {Deposit} event.
     * @param _shares The number of shares to mint.
     * @param _receiver The address that will receive the minted shares.
     * @return assets The amount of assets deposited.
     */
    function mint(uint256 _shares, address _receiver) public override returns (uint256 assets) {
        if (_shares + totalSupply > supplyCap) revert SupplyCapExceeded();

        assets = previewMint(_shares);
        if (assets == 0) revert ZeroAssets();
        uint256 preBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), assets);
        uint256 delta = asset.balanceOf(address(this)) - preBalance;
        _mint(_receiver, _shares);

        emit Deposit(msg.sender, _receiver, delta, _shares);

        afterDeposit(delta, _shares);
    }

    /**
     * @notice Hook called after assets are deposited into the vault.
     * @dev Overrides ERC4626 {afterDeposit} to update the internal assetTotal.
     * @param _assets The amount of assets deposited.
     */
    function afterDeposit(uint256 _assets, uint256) internal override {
        assetTotal += _assets;
    }

    /**
     * @notice Hook called before assets are withdrawn from the vault.
     * @dev Overrides ERC4626 {beforeWithdraw} to update the internal assetTotal.
     * @param _assets The amount of assets to withdraw.
     */
    function beforeWithdraw(uint256 _assets, uint256) internal override {
        assetTotal -= _assets;
    }

    /**
     * @notice Returns the maximum amount of assets a user can deposit.
     * @dev Overrides ERC4626 {maxDeposit}. It calculates the maximum deposit based on the user's asset balance
     * and the remaining supply capacity.
     * @param _user The address of the user.
     * @return The maximum deposit amount for the user.
     */
    function maxDeposit(address _user) public view override returns (uint256) {
        uint256 userAssets = asset.balanceOf(_user);
        uint256 maxPotentialDeposit = convertToAssets(supplyCap - totalSupply);
        return userAssets > maxPotentialDeposit ? maxPotentialDeposit : userAssets;
    }

    /**
     * @notice Returns the maximum number of shares a user can mint.
     * @dev Overrides ERC4626 {maxMint}. It calculates the maximum shares based on the user's asset balance
     * and the remaining supply capacity.
     * @param _user The address of the user.
     * @return The maximum number of shares the user can mint.
     */
    function maxMint(address _user) public view override returns (uint256) {
        uint256 userAssets = asset.balanceOf(_user);
        uint256 maxPotentialMint = convertToShares(userAssets);
        uint256 maxSharesToReachCap = supplyCap - totalSupply;
        return maxPotentialMint > maxSharesToReachCap ? maxSharesToReachCap : maxPotentialMint;
    }

    /**
     * @notice Sets the BoostPool address.
     * @dev Overrides {setBoostPool} from ISebaVault.
     * Reverts if the new address is the zero address. Emits a {BoostPoolChanged} event.
     * @param _boostPool The new BoostPool address.
     */
    /// @inheritdoc IPYBSeba
    function setSebaPool(address _sebaPool) public override onlyRole(ADMIN_ROLE) {
        if (_sebaPool == address(0)) revert InvalidAddress();
        sebaPool = _sebaPool;
        emit SebaPoolChanged(_sebaPool);
    }

    /**
     * @notice Returns the total assets held in the vault.
     * @dev Overrides ERC4626 {totalAssets} to return the internal assetTotal.
     * @return The total assets recorded by the vault.
     */
    function totalAssets() public view override returns (uint256) {
        return assetTotal;
    }
}
