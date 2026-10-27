// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IYieldVault } from "src/interfaces/IYieldVault.sol";

/// @title Legacy intake stop between the two approved migration stages
/// @notice Every legacy strategy operation reverts; this contract never receives ordinary ETH or holds principal.
/// @dev Stage A exits the original strategy into the old manager before installing this fixed, stateless marker.
/// @author Seba Protocol
contract LegacyIntakeStopper is IYieldVault {
    /// @notice Legacy intake and strategy operations are intentionally unavailable during staged approval.
    error IntakeStopped();

    /// @inheritdoc IYieldVault
    function deposit() external payable override returns (uint256) {
        revert IntakeStopped();
    }

    /// @inheritdoc IYieldVault
    function claimYield() external pure override {
        revert IntakeStopped();
    }

    /// @inheritdoc IYieldVault
    function retrievePrincipal(uint256) external pure override {
        revert IntakeStopped();
    }
}
