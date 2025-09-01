// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "solmate/src/tokens/ERC20.sol";

/// @notice Simple mintable ERC20 for testing.
contract MockBold is ERC20 {
    constructor() ERC20("Mock Bold", "mBOLD", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
