// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}

    function mint(uint256 amount, address receiver) public {
        _mint(receiver, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
