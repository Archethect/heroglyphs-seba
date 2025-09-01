// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice vault-specific interface for sBOLD.
interface ISBOLD {
    // --- Vault-specific methods ---
    /// Deposits BOLD and mints sBOLD shares to msg.sender.
    function deposit(uint256 boldAmount, address receiver) external returns (uint256 sharesMinted);

    /// Withdraws BOLD by burning sBOLD and sending it to the receiver.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
}
