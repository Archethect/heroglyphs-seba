// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISBOLD is IERC20 {
    /// Deposits BOLD and mints sBOLD shares to msg.sender.
    function deposit(uint256 boldAmount) external returns (uint256 sharesMinted);
}