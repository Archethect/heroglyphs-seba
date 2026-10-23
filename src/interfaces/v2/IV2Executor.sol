// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Fixed Seba V2 execution routes
/// @notice Only the configured manager may execute. All outputs go back to that manager.
/// @author Seba Protocol
interface IV2Executor {
    /// @notice Fixed identities; deployment must verify them against the target chain.
    struct Config {
        address manager;
        address treasury;
        address reth;
        address weth;
        address usdc;
        address bold;
        address yBold;
        address ysyBold;
        address swapRouter;
        address curvePool;
        address ethUsdFeed;
        address usdcUsdFeed;
        address rocketStorage;
    }

    /// @notice Safe-approved risk configuration. Zero defaults cannot enable execution.
    /// @dev Amount caps are ETH wei, rETH atoms and ysyBOLD atoms; fee is WAD, other tolerances BPS.
    struct Limits {
        uint256 maxEth;
        uint256 maxReth;
        uint256 maxYsy;
        uint256 maxMintFeeWad;
        uint32 ethMaxAge;
        uint32 usdcMaxAge;
        uint32 reportMaxAge;
        uint32 reportMaxBlockLag;
        uint32 maxDeadline;
        uint16 slippageBps;
        uint16 pegBps;
        uint24 wethUsdcFee;
        uint24 rethWethFee;
        address depositPool;
        address networkBalances;
        address depositSettings;
    }

    error Unauthorized();
    error InvalidConfiguration();
    error ExecutionDisabled();
    error InvalidExecution();
    error InvalidOracle();
    error StaleOracle();
    error PegExceeded();
    error RegistryChanged();
    error MintFeeExceeded();
    error UnexpectedTokenDelta();
    error InsufficientOutput();
    error PartialInput();

    /// @notice Risk settings changed while execution was disabled.
    /// @param configurationHash Keccak256 commitment to the complete ABI-encoded Limits struct.
    event LimitsConfigured(bytes32 indexed configurationHash);
    /// @notice Safe explicitly enabled or disabled all conversion routes.
    /// @param enabled Whether reviewed conversion routes may execute.
    event ExecutionEnabled(bool enabled);
    /// @notice An atomic route completed with exact input and actual output.
    /// @param route Route identifier: 0 rETH mint, 1 ysyBOLD investment, 2 ETH, 3 rETH, 4 ysyBOLD conversion.
    /// @param input Exact native input atoms consumed, or ETH wei for payable routes.
    /// @param output Actual final-token atoms delivered to the fixed manager.
    event RouteExecuted(uint8 indexed route, uint256 input, uint256 output);

    /// @notice Fixed manager identity.
    /// @return Authorized caller and sole output recipient.
    function manager() external view returns (address);
    /// @notice Fixed governance Safe identity.
    /// @return Contract authorized to configure limits and enable execution.
    function treasury() external view returns (address);
    /// @notice Returns fixed external identities.
    /// @return Constructor-validated token, venue, oracle and authority identities.
    function configuration() external view returns (Config memory);
    /// @notice Returns currently approved risk limits.
    /// @return Limits last approved by the Safe, or zero defaults before configuration.
    function limits() external view returns (Limits memory);
    /// @notice Execution is disabled at deployment.
    /// @return Whether the Safe has enabled configured routes.
    function enabled() external view returns (bool);
    /// @notice Safe configures limits only while disabled.
    /// @param proposed Complete proposed limits; invalid or zero safety bounds revert.
    function configureLimits(Limits calldata proposed) external;
    /// @notice Safe separately activates reviewed configuration.
    /// @param proposed True to enable configured routes; false to disable them.
    function setEnabled(bool proposed) external;
    /// @notice Mint rETH through the current, approved Rocket Pool registry entry.
    /// @param minTokens Minimum rETH atoms delivered, additionally bounded by the independent native mint floor.
    /// @param deadline Inclusive execution deadline in Unix seconds, within the configured horizon.
    /// @return output Actual rETH atoms delivered to manager for exactly msg.value ETH wei.
    function investReth(uint256 minTokens, uint256 deadline) external payable returns (uint256 output);
    /// @notice ETH → WETH → USDC → BOLD → yBOLD → ysyBOLD.
    /// @param minTokens Minimum ysyBOLD atoms delivered, in addition to independent per-hop floors.
    /// @param deadline Inclusive execution deadline in Unix seconds, within the configured horizon.
    /// @return output Actual ysyBOLD atoms delivered to manager for exactly msg.value ETH wei.
    function investYsyBold(uint256 minTokens, uint256 deadline) external payable returns (uint256 output);
    /// @notice ETH → WETH → USDC → BOLD, returning BOLD to manager.
    /// @param minBold Minimum BOLD atoms delivered, in addition to independent per-hop floors.
    /// @param deadline Inclusive execution deadline in Unix seconds, within the configured horizon.
    /// @return output Actual BOLD atoms delivered to manager for exactly msg.value ETH wei.
    function convertEthToBold(uint256 minBold, uint256 deadline) external payable returns (uint256 output);
    /// @notice rETH → WETH → USDC → BOLD; pull exactly amount from manager.
    /// @param amount Exact rETH input atoms pulled from manager and consumed atomically.
    /// @param minBold Minimum BOLD atoms delivered, in addition to independent per-hop floors.
    /// @param deadline Inclusive execution deadline in Unix seconds, within the configured horizon.
    /// @return output Actual BOLD atoms delivered to manager.
    function convertRethToBold(uint256 amount, uint256 minBold, uint256 deadline) external returns (uint256 output);
    /// @notice ysyBOLD → yBOLD → BOLD with zero redemption loss and no USD-feed/DEX dependency.
    /// @param amount Exact ysyBOLD input atoms pulled from manager and redeemed atomically.
    /// @param minBold Minimum BOLD atoms delivered, in addition to canonical zero-loss redemption floors.
    /// @param deadline Inclusive execution deadline in Unix seconds, within the configured horizon.
    /// @return output Actual BOLD atoms delivered to manager; locked future Yearn profit is not promised.
    function convertYsyToBold(uint256 amount, uint256 minBold, uint256 deadline) external returns (uint256 output);
}
