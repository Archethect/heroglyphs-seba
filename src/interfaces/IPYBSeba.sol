// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPYBSeba
 * @notice Interface for the Perpetual Seba vault.
 * @dev Extends an ERC4626-style vault. It adds functions for topping up and distributing shares, as well as setting the BoostPool.
 */
interface IPYBSeba {
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an address parameter is the zero address.
    error InvalidAddress();
    /// @notice Thrown when a function is called by an address other than the SebaPool.
    /// @param sender The address that attempted the call.
    error NotSebaPool(address sender);
    /// @notice Thrown when a deposit or mint operation would result in zero shares.
    error ZeroShares();
    /// @notice Thrown when a deposit or mint operation would result in zero assets.
    error ZeroAssets();
    /// @notice Thrown when a deposit or mint would cause the total share supply to exceed the cap.
    error SupplyCapExceeded();
    /// @notice Thrown when a deposit is tried as it is not allowed.
    error DepositNotAllowed();
    /// @notice Thrown when a mint is tried as it is not allowed.
    error MintNotAllowed();

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the SebaPool address is updated.
    /// @param sebaPool The new SebaPool address.
    event SebaPoolChanged(address indexed sebaPool);
    /// @notice Emitted when the vault is topped up.
    /// @param sender The address initiating the topup.
    /// @param amount The amount of assets transferred.
    event Topup(address indexed sender, uint256 amount);
    /// @notice Emitted when shares are distributed.
    /// @param receiver The address receiving the shares.
    /// @param shares The number of shares distributed.
    event SharesDistributed(address indexed receiver, uint256 shares);

    /*//////////////////////////////////////////////////////////////
                         PUBLIC VARIABLES (Getters)
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the total assets held in the vault.
    function assetTotal() external view returns (uint256);
    /// @notice Returns the SebaPool contract address.
    function sebaPool() external view returns (address);

    /// @notice The role identifier for administrative functions.
    function ADMIN_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tops up the vault by transferring assets from the caller.
     * @dev See {topup} in the contract.
     * @param amount The amount of assets to top up.
     */
    function topup(uint256 amount) external;

    /**
     * @notice Distributes yield-bearing shares to a receiver.
     * @dev Can only be called by the BoostPool. Emits a {SharesDistributed} event.
     * @param receiver The address to receive shares.
     * @param shares The number of shares to distribute.
     */
    function distributeShares(address receiver, uint256 shares) external;

    /**
     * @notice Sets the SebaPool address.
     * @dev Reverts if the new address is zero. Emits a {SebaPoolChanged} event.
     * @param _sebaPool The new SebaPool address.
     */
    function setSebaPool(address _sebaPool) external;
}
