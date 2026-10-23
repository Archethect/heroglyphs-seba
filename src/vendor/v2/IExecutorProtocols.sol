// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Fixed-route Yearn vault interface
/// @notice Native Yearn share conversion and zero-loss redemption methods used by the executor.
/// @author Seba Protocol
interface IExecutorYearn {
    /// @notice Read the vault's underlying asset identity.
    /// @return Underlying ERC20 token address.
    function asset() external view returns (address);
    /// @notice Preview native shares minted for an underlying deposit with downward rounding.
    /// @param assets Underlying token atoms to deposit.
    /// @return Expected vault-share atoms.
    function previewDeposit(uint256 assets) external view returns (uint256);
    /// @notice Read recognized native asset value, excluding still-locked future profit.
    /// @param shares Vault-share atoms being valued.
    /// @return Underlying token atoms, rounded down by the vault.
    function convertToAssets(uint256 shares) external view returns (uint256);
    /// @notice Read the vault's current redeemable-share limit for an owner.
    /// @param owner Address holding the vault shares.
    /// @return Maximum currently redeemable vault-share atoms; not an execution guarantee.
    function maxRedeem(address owner) external view returns (uint256);
    /// @notice Deposit underlying assets and mint native vault shares.
    /// @param assets Exact underlying token atoms offered.
    /// @param receiver Address receiving the minted shares.
    /// @return Minted vault-share atoms.
    function deposit(uint256 assets, address receiver) external returns (uint256);
    /// @notice Redeem native shares with an explicit permitted realized-loss bound.
    /// @param shares Vault-share atoms to burn.
    /// @param receiver Address receiving underlying assets.
    /// @param owner Address whose shares are burned.
    /// @param maxLoss Maximum permitted realized loss in basis points; executor always supplies zero.
    /// @return Underlying token atoms received.
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss) external returns (uint256);
}

/// @title Fixed BOLD/USDC Curve pool interface
/// @notice StableSwap-NG exchange and native price-oracle methods used by the executor.
/// @author Seba Protocol
interface IExecutorCurve {
    /// @notice Read an indexed pool-coin identity.
    /// @param index Pool index: 0 BOLD, 1 USDC.
    /// @return ERC20 token address.
    function coins(uint256 index) external view returns (address);
    /// @notice Read the pool's EMA of coin[index+1] denominated in coin[0].
    /// @param index Oracle index; executor uses zero for BOLD per USDC.
    /// @return Normalized price with 18 decimals, not a standalone external USD oracle.
    function price_oracle(uint256 index) external view returns (uint256);
    /// @notice Exchange exact pool input for output with a native minimum.
    /// @param i Input index; executor uses 1 for USDC.
    /// @param j Output index; executor uses 0 for BOLD.
    /// @param dx Input USDC atoms, with six decimals.
    /// @param minimum Minimum BOLD output atoms, with eighteen decimals.
    /// @return Actual BOLD output atoms reported by Curve.
    function exchange(int128 i, int128 j, uint256 dx, uint256 minimum) external returns (uint256);
}

/// @title Rocket Pool integration registry interface
/// @notice Read current protocol-contract identities before bounded rETH operations.
/// @author Seba Protocol
interface IExecutorRocketStorage {
    /// @notice Read an address by RocketStorage's native typed key.
    /// @param key Keccak256 of packed contract.address and the Rocket Pool contract name.
    /// @return Current registered integration address.
    function getAddress(bytes32 key) external view returns (address);
}

/// @title Rocket Pool native report freshness interface
/// @notice Both timestamp and execution-block age must satisfy Safe-approved bounds.
/// @author Seba Protocol
interface IExecutorRocketBalances {
    /// @notice Read the native balance-report timestamp.
    /// @return Report timestamp in Unix seconds.
    function getBalancesTimestamp() external view returns (uint256);
    /// @notice Read the native balance-report execution block.
    /// @return Execution block number associated with the report.
    function getBalancesBlock() external view returns (uint256);
}

/// @title Rocket Pool native deposit settings interface
/// @notice Read the dynamic native rETH mint fee, not a DEX fee.
/// @author Seba Protocol
interface IExecutorRocketSettings {
    /// @notice Read the current deposit fee fraction.
    /// @return Fee fraction scaled by 1e18.
    function getDepositFee() external view returns (uint256);
}

/// @title Rocket Pool synchronous native deposit interface
/// @notice Mint rETH only through the registry-approved deposit pool; this interface exposes no queue or burn.
/// @author Seba Protocol
interface IExecutorRocketPool {
    /// @notice Read the current maximum accepted ETH deposit.
    /// @return Deposit capacity in ETH wei; not a guarantee the later transaction will execute.
    function getMaximumDepositAmount() external view returns (uint256);
    /// @notice Deposit exactly msg.value ETH wei and mint rETH to the caller under current protocol settings.
    function deposit() external payable;
}

/// @title Rocket Pool native receipt-token valuation interface
/// @notice Native forward conversions avoid treating a rounded displayed exchange rate as an exact inverse.
/// @author Seba Protocol
interface IExecutorReth {
    /// @notice Convert rETH atoms to recognized ETH value using Rocket Pool's native rounding.
    /// @param tokens rETH atoms to value.
    /// @return ETH wei, rounded down by the native conversion.
    function getEthValue(uint256 tokens) external view returns (uint256);
    /// @notice Convert ETH value to rETH atoms using Rocket Pool's native rounding.
    /// @param ethValue ETH wei to value.
    /// @return rETH atoms, rounded down by the native conversion.
    function getRethValue(uint256 ethValue) external view returns (uint256);
}
