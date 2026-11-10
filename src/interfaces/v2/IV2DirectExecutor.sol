// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { IV2Executor } from "./IV2Executor.sol";
/// @title Direct Rocket Pool/Yearn executor extension
/// @author Seba
/// @notice DEX swapping is unavailable; BOLD principal has already settled through CoW.
interface IV2DirectExecutor is IV2Executor {
    /// @notice Safe-approved BOLD atoms per direct investment; zero disables it.
    function maximumBold() external view returns (uint256);
    /// @notice Safe configures the BOLD cap while execution is paused.
    /// @param amount Nonzero maximum BOLD atoms per direct protocol investment.
    function configureBoldLimit(uint256 amount) external;
    /// @notice Pull exact BOLD and return actual nested Yearn shares only to manager.
    /// @param amount Exact BOLD atoms pulled from manager.
    /// @param minimum Minimum actual ysyBOLD atoms returned.
    /// @param deadline Inclusive timestamp within the approved execution horizon.
    /// @return Actual ysyBOLD atoms delivered to the fixed manager.
    function investBold(uint256 amount, uint256 minimum, uint256 deadline) external returns (uint256);
}
