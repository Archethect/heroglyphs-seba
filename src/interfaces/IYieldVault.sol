// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IYieldVault
 * @notice Minimal interface that any yield-strategy vault must implement for Seba’s
 *         ecosystem. A vault manages principal (in underlying vault asset terms) and can:
 *         ① accept deposits, ② realise and forward yield, and ③ allow principal retrieval.
 * @dev Every strategy-specific vault (e.g., Beefy, Aave, Compound) must implement
 *      this interface so it can be plugged into the Seba YieldManager.
 */
interface IYieldVault {
    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit ETH into the strategy.
     * @dev The caller (usually a YieldManager) transfers ETH with the call.
     *      Implementations should convert / invest as needed and return
     *      the ETH-denominated value credited as principal.
     * @return depositValue Value (in unerlying vault asset terms) accounted as principal.
     */
    function deposit() external payable returns (uint256 depositValue);

    /**
 * @notice Claim strategy yield and transfer it back to the caller
     *         (either auto-compounded or forwarded on, depending on the caller’s logic).
     * @dev Implementations decide what constitutes “yield” versus principal.
     */
    function claimYield() external;

    /**
     * @notice Retrieve an arbitrary slice of principal, denominated in the underlying vault asset.
     * @param depositValue Amount of principal (underlying vault asset terms) requested for return.
     */
    function retrievePrincipal(uint256 depositValue) external;
}
