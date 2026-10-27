// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { Test } from "forge-std/src/Test.sol";
import { YieldManager } from "src/YieldManager.sol";

interface ILegacyBeefyProbe {
    function principalValue() external view returns (uint256);
    function principalShares() external view returns (uint256);
}

/// @notice Read-only mainnet fork measurement, not a broadcast or a full migration rehearsal.
contract LegacyExitProbeTest is Test {
    function test_CurrentLegacyProtocolExitMeasurement() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC"), vm.envOr("SEBA_V2_FORK_BLOCK", uint256(26_255_470)));
        YieldManager old = YieldManager(payable(0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269));
        ILegacyBeefyProbe adapter = ILegacyBeefyProbe(address(old.yieldVault()));
        uint256 preEth = address(old).balance;
        emit log_named_uint("Before old manager native principal", old.principalValue());
        emit log_named_uint("Before adapter native principal", adapter.principalValue());
        emit log_named_uint("Before adapter shares", adapter.principalShares());
        vm.prank(0x888D768764A2E304215247F0bA3457cCb0f0ab4f);
        old.retrievePrincipalFromYieldVault();
        assertEq(old.principalValue(), 0);
        assertGt(address(old).balance, preEth);
        emit log_named_uint("Actual ETH wei received", address(old).balance - preEth);
        emit log_named_uint("After adapter native principal", adapter.principalValue());
        emit log_named_uint("After adapter shares", adapter.principalShares());
        emit log_named_uint("Observed block", block.number);
    }
}
