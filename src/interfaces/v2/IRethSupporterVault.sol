// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { IV2SupporterVault } from "./IV2SupporterVault.sol";

/// @title rETH-specific initialization and report-bound administration
/// @author Seba contributors
/// @notice Fixed rETH identities and Safe-approved entry/harvest report bounds.
interface IRethSupporterVault is IV2SupporterVault {
    /// @notice Safe configured report freshness without adding an age gate to native exits.
    /// @param maximumAge Maximum report age in seconds.
    /// @param maximumBlockLag Maximum report execution-block lag.
    event ReportBoundsConfigured(uint256 maximumAge, uint256 maximumBlockLag);
    /// @notice Initialize the fixed authority, coordinator, token and canonical RocketStorage registry.
    /// @param safe Verified treasury multisig contract; never an EOA.
    /// @param coordinator Fixed YieldManagerV2 proxy.
    /// @param token Verified canonical rETH token.
    /// @param registry Verified RocketStorage registry used by that token.
    function initialize(address safe, address coordinator, address token, address registry) external;
    /// @notice Safe-only entry/harvest report bounds; does not restrict native exits on report age.
    /// @param maxAge Maximum seconds since the latest report, positive and separately approved.
    /// @param maxBlockLag Maximum execution-block distance since the reported block, positive and approved.
    function configureReportBounds(uint256 maxAge, uint256 maxBlockLag) external;
    /// @notice Read the fixed RocketStorage registry.
    /// @return Fixed registry determining the canonical rETH balances source.
    function rocketStorage() external view returns (address);
    /// @notice Read the Safe-approved report-age limit for new entry and harvesting.
    /// @return Configured report freshness in seconds, zero until explicitly set.
    function maximumReportAge() external view returns (uint256);
    /// @notice Read the Safe-approved report-block lag for new entry and harvesting.
    /// @return Configured report execution-block lag, zero until explicitly set.
    function maximumReportBlockLag() external view returns (uint256);
}
