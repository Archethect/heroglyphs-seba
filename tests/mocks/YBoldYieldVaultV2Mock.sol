// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { YBoldYieldVault } from "src/YBoldYieldVault.sol";

contract YBoldYieldVaultV2Mock is YBoldYieldVault {
    uint256 public upgradeMarker;

    constructor(address configValidator) YBoldYieldVault(configValidator) {}

    function initializeV2(uint256 marker) external reinitializer(2) onlyRole(UPGRADER_ROLE) {
        upgradeMarker = marker;
    }
}
