// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { NativeSupporterVault } from "./NativeSupporterVault.sol";
import { IRethSupporterVault } from "../interfaces/v2/IRethSupporterVault.sol";

/// @title Rocket Pool registry identity interface
/// @author Seba contributors
/// @notice Rocket Pool registry getters used by native-value accounting.
interface IVaultRocketStorage {
    /// @notice Resolve a canonical Rocket Pool contract address.
    /// @param key Registry address key derived from the exact protocol name.
    /// @return Current registered contract.
    function getAddress(bytes32 key) external view returns (address);
}
/// @title Rocket Pool reported network balances interface
/// @author Seba contributors
/// @notice Reported, rather than DEX-valued, rETH backing and supply.
interface IVaultRocketBalances {
    /// @notice Read canonical reported network ETH backing.
    /// @return Reported backing in ETH wei.
    function getTotalETHBalance() external view returns (uint256);
    /// @notice Read matching reported rETH supply.
    /// @return Reported rETH base units.
    function getTotalRETHSupply() external view returns (uint256);
    /// @notice Read when the current report was accepted.
    /// @return Report timestamp in seconds.
    function getBalancesTimestamp() external view returns (uint256);
    /// @notice Read which execution block the report describes.
    /// @return Reported execution-block number.
    function getBalancesBlock() external view returns (uint256);
}

/// @title rETH-native donation vault with ETH principal basis
/// @author Seba contributors
/// @notice Withdrawals return rETH without requiring a native burn, redemption queue or USD oracle.
contract RethSupporterVault is NativeSupporterVault, IRethSupporterVault {
    /// @inheritdoc IRethSupporterVault
    address public override rocketStorage;
    /// @inheritdoc IRethSupporterVault
    uint256 public override maximumReportAge;
    /// @inheritdoc IRethSupporterVault
    uint256 public override maximumReportBlockLag;

    /// @inheritdoc IRethSupporterVault
    function initialize(
        address safe,
        address coordinator,
        address token,
        address registry
    ) external override initializer {
        __NativeSupporterVault_init(safe, coordinator, token, address(0));
        if (registry.code.length == 0) revert InvalidConfiguration();
        rocketStorage = registry;
        _balances();
    }
    /// @inheritdoc IRethSupporterVault
    function configureReportBounds(uint256 maxAge, uint256 maxBlockLag) external override onlySafe onlyNormal {
        if (maxAge == 0 || maxBlockLag == 0) revert InvalidConfiguration();
        maximumReportAge = maxAge;
        maximumReportBlockLag = maxBlockLag;
        emit ReportBoundsConfigured(maxAge, maxBlockLag);
    }
    function _readRate() internal view override returns (uint256 numerator, uint256 denominator) {
        IVaultRocketBalances balances = _balances();
        numerator = balances.getTotalETHBalance();
        denominator = balances.getTotalRETHSupply();
        if (denominator == 0) return (1, 1);
    }
    function _requireFresh() internal view override {
        if (maximumReportAge == 0 || maximumReportBlockLag == 0) revert StaleReport();
        IVaultRocketBalances balances = _balances();
        uint256 timestamp = balances.getBalancesTimestamp();
        uint256 number = balances.getBalancesBlock();
        if (
            timestamp == 0 ||
            number == 0 ||
            timestamp > block.timestamp ||
            block.timestamp - timestamp > maximumReportAge ||
            number > block.number ||
            block.number - number > maximumReportBlockLag
        ) revert StaleReport();
    }
    function _balances() private view returns (IVaultRocketBalances balances) {
        IVaultRocketStorage registry = IVaultRocketStorage(rocketStorage);
        if (registry.getAddress(keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))) != asset)
            revert InvalidConfiguration();
        address target = registry.getAddress(keccak256(abi.encodePacked("contract.address", "rocketNetworkBalances")));
        if (target.code.length == 0) revert InvalidConfiguration();
        balances = IVaultRocketBalances(target);
    }
}
