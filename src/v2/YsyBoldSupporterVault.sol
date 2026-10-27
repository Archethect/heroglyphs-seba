// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { NativeSupporterVault } from "./NativeSupporterVault.sol";
import { IYsyBoldSupporterVault } from "../interfaces/v2/IYsyBoldSupporterVault.sol";

/// @title Yearn tokenized strategy recognized-accounting interface
/// @author Seba contributors
/// @notice Deployed Yearn 3.0.4 tokenized strategy accounting, including effective unlocked-profit supply.
interface IVaultYearnAccounting {
    /// @notice Read the fixed underlying token.
    /// @return Underlying asset address.
    function asset() external view returns (address);
    /// @notice Read the implementation accounting API version.
    /// @return Version string; this vault supports 3.0.4 only.
    function apiVersion() external view returns (string memory);
    /// @notice Read cached recognized underlying assets.
    /// @return Recognized yBOLD base units.
    function totalAssets() external view returns (uint256);
    /// @notice Read effective supply, already excluding unlocked self-held profit shares.
    /// @return Effective ysyBOLD base units; do not subtract unlocked profit again.
    function totalSupply() external view returns (uint256);
}

/// @title ysyBOLD-native donation vault with recognized yBOLD principal basis
/// @author Seba contributors
/// @notice Only recognized outer-vault growth is donated; unreported/unlocked future rights follow returned shares.
contract YsyBoldSupporterVault is NativeSupporterVault, IYsyBoldSupporterVault {
    /// @inheritdoc IYsyBoldSupporterVault
    function initialize(address safe, address coordinator, address token, address yBold) external override initializer {
        __NativeSupporterVault_init(safe, coordinator, token, yBold);
        if (
            yBold == address(0) ||
            IVaultYearnAccounting(token).asset() != yBold ||
            keccak256(bytes(IVaultYearnAccounting(token).apiVersion())) != keccak256("3.0.4")
        ) revert InvalidConfiguration();
    }
    function _readRate() internal view override returns (uint256 numerator, uint256 denominator) {
        IVaultYearnAccounting token = IVaultYearnAccounting(asset);
        if (token.asset() != basisAsset || keccak256(bytes(token.apiVersion())) != keccak256("3.0.4"))
            revert InvalidConfiguration();
        numerator = token.totalAssets();
        denominator = token.totalSupply();
        if (denominator == 0) return (1, 1);
    }
    /// @dev Cached recognized Yearn accounting has no USD oracle or redemption availability gate.
    // solhint-disable-next-line no-empty-blocks
    function _requireFresh() internal pure override {
        // The protocol's canonical recognized accounting, including effective supply, is the specified entry reference.
    }
}
