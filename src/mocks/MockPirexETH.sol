// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "src/mocks/MockApxETH.sol";
import "src/vendor/dinero/IPirexEth.sol";

/**
 * @title MockPirexETH
 * @notice Minimal mock of the PirexEth contract:
 *  - Has a `feeRate` in parts-per-million (1e6).
 *  - In `deposit`, it calculates a fee, mints net ApxETH shares, and returns (depositAmount, fee).
 */
contract MockPirexETH is Ownable, IPirexEth {
    /// @notice Fee rate in ppm (e.g., 10_000 means 1%, if DENOMINATOR=1_000_000).
    uint32 public feeRate;

    /// @notice APXETH mock token to mint when deposit is called.
    IMockApxETH public apxEth;

    /// @dev Denominator for fee calculation.
    uint256 private constant DENOMINATOR = 1_000_000;

    constructor(address _owner, uint32 _initialFeeRate) Ownable(_owner) {
        feeRate = _initialFeeRate;
    }

    /**
     * @notice Change the deposit fee rate.
     * @param _feeRate New fee rate in parts per million.
     */
    function setFeeRate(uint32 _feeRate) external {
        require(_feeRate <= 50_000, "feeRate too high"); // example check
        feeRate = _feeRate;
    }

    /**
     * @notice Called by ApxETHVault to deposit ETH.
     *  - Compute `fee = msg.value * feeRate / 1e6`.
     *  - Net deposit = `msg.value - fee`.
     *  - Mint that many "shares" of ApxETH to `to`.
     * @param to Unused bool in the real interface, we keep it to match signature.
     * @return depositAmount net deposit
     * @return fee fee
     */
    function deposit(address to, bool) external payable returns (uint256 depositAmount, uint256 fee) {
        fee = (msg.value * feeRate) / DENOMINATOR;
        depositAmount = msg.value - fee;

        // Mint the net deposit as "shares" directly to the vault
        // For simplicity, we do 1 depositAmount => 1 share minted
        // but if you want to incorporate `pricePerShare`, you can do:
        //   shares = depositAmount * 1e18 / apxEth.pricePerShare()
        // and mint that. The vault code never calls 'mint' itself; we do it here.
        apxEth.mint(to, depositAmount);

        return (depositAmount, fee);
    }

    /**
     * @notice Return the fee for a given index (0 => deposit).
     * @dev    The vault code calls `fees(0)` to get the deposit fee. We just return `feeRate`.
     */
    function fees(uint8) external view override returns (uint32) {
        return feeRate;
    }

    function setApxETH(address _apxEth) external onlyOwner {
        apxEth = IMockApxETH(_apxEth);
    }
}
