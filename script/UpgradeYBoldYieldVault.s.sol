// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";
import { YBoldYieldVault } from "src/YBoldYieldVault.sol";
import { YBoldReleaseChecks } from "script/YBoldReleaseChecks.sol";

/**
 * @title UpgradeYBoldYieldVault
 * @notice Produces unsigned Safe upgrade calldata after exact implementation and authority checks.
 * @dev Read-only: deploy the independently reviewed implementation only after approval, then simulate this calldata.
 */
contract UpgradeYBoldYieldVault is Script {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    address internal constant TREASURY_SAFE = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;

    /// @notice Validates the current and proposed implementation hashes and prints upgradeToAndCall calldata.
    function run() external view returns (bytes memory data) {
        require(block.chainid == 1, "CHAIN_ID");
        address proxy = vm.envAddress("YBOLD_VAULT");
        require(proxy == vm.envAddress("YBOLD_EXPECTED_PROXY"), "RELEASE_PROXY");
        YBoldReleaseChecks.validate(0xf83b11b09EEc073ACE4481b2F4c8357e156714b3, TREASURY_SAFE, TREASURY_SAFE);
        address expectedCurrent = vm.envAddress("YBOLD_EXPECTED_IMPLEMENTATION");
        address next = vm.envAddress("YBOLD_NEXT_IMPLEMENTATION");
        require(proxy.code.length > 0 && next.code.length > 0 && proxy != next, "UPGRADE_CODE");
        require(
            address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT)))) == expectedCurrent,
            "CURRENT_IMPLEMENTATION"
        );
        require(
            expectedCurrent.codehash == vm.envBytes32("YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH"),
            "CURRENT_CODEHASH"
        );
        require(
            next != expectedCurrent && next.codehash == vm.envBytes32("YBOLD_NEXT_IMPLEMENTATION_CODEHASH"),
            "NEXT_CODEHASH"
        );
        require(YBoldYieldVault(payable(next)).proxiableUUID() == IMPLEMENTATION_SLOT, "NEXT_NOT_UUPS");
        require(
            YBoldYieldVault(payable(proxy)).hasRole(keccak256("UPGRADER_ROLE"), TREASURY_SAFE),
            "SAFE_NOT_UPGRADER"
        );
        bytes memory initialization = vm.envOr("YBOLD_UPGRADE_CALLDATA", bytes(""));
        data = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", next, initialization);
        console2.log("Safe transaction target (proxy)", proxy);
        console2.log("Safe transaction value", uint256(0));
        console2.logBytes(data);
    }
}
