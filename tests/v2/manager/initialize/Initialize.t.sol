// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";

contract ManagerIdentityMock {
    receive() external payable {}
}

contract ManagerInitializeTest is Test {
    function test_ImplementationCannotBeInitialized() public {
        YieldManagerV2 implementation = new YieldManagerV2();
        IYieldManagerV2.Initialization memory configuration;
        vm.expectRevert();
        implementation.initialize(configuration);
    }

    function test_RejectsEOATreasury() public {
        YieldManagerV2 implementation = new YieldManagerV2();
        IYieldManagerV2.Initialization memory configuration;
        configuration.treasury = makeAddr("EOA-not-governance");
        vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
        new ERC1967Proxy(address(implementation), abi.encodeCall(implementation.initialize, (configuration)));
    }
}
