// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Minimal verified GPv2 settlement interface
/// @author Seba
/// @notice No solver settlement method is exposed to Seba operations.
interface ICowSettlement {
    /// @notice Return chain/deployment-bound EIP-712 domain.
    function domainSeparator() external view returns (bytes32);
    /// @notice Return sole ERC20 allowance spender.
    function vaultRelayer() external view returns (address);
    /// @notice Authenticate/revoke the caller-owned exact UID.
    /// @param orderUid Exact 56-byte order UID owned by the caller.
    /// @param signed True authorizes settlement; false revokes that authorization.
    function setPreSignature(bytes calldata orderUid, bool signed) external;
}
