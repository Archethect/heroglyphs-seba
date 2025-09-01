// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "solmate/src/tokens/ERC20.sol";
import { MockBold } from "./MockBold.sol";
import { ISBOLD } from "src/vendor/liquity/ISBOLD.sol";

/// @notice Minimal mock ERC4626-like vault for testing with Solmate ERC20.
contract MockSBold is ERC20, ISBOLD {
    MockBold public immutable asset; // underlying BOLD

    constructor(MockBold _asset) ERC20("Mock sBold", "msBOLD", 18) {
        asset = _asset;
    }

    /// @notice Deposit BOLD and mint sBOLD 1:1
    function deposit(uint256 boldAmount, address receiver) external override returns (uint256 sharesMinted) {
        require(boldAmount > 0, "invalid amount");
        asset.transferFrom(msg.sender, address(this), boldAmount);
        _mint(receiver, boldAmount);
        return boldAmount;
    }

    /// @notice Withdraw BOLD by burning sBOLD 1:1
    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256) {
        require(assets > 0, "invalid amount");

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            require(allowed >= assets, "insufficient allowance");
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - assets;
            }
        }

        _burn(owner, assets);
        asset.transfer(receiver, assets);

        return assets;
    }
}
