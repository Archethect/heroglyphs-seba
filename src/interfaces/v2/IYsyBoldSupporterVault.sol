// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { IV2SupporterVault } from "./IV2SupporterVault.sol";

/// @title ysyBOLD-specific initialization interface
/// @author Seba contributors
/// @notice Exact reviewed native/basis token identities and fixed governance/coordinator binding.
interface IYsyBoldSupporterVault is IV2SupporterVault {
    /// @notice Initialize the fixed authority, coordinator and reviewed native/basis token identities.
    /// @param safe Verified treasury multisig contract; never an EOA.
    /// @param coordinator Fixed YieldManagerV2 proxy.
    /// @param token Verified ysyBOLD Yearn tokenized strategy version 3.0.4.
    /// @param yBold That strategy's exact yBOLD underlying token.
    function initialize(address safe, address coordinator, address token, address yBold) external;
}
