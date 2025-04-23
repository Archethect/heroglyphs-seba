// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { ApxETHVault } from "src/liquidity/ApxETHVault.sol";

contract ConstructorTest is BaseTest {
    function test_WhenConstructed() external {
        ApxETHVault localApxETHVault = new ApxETHVault(users.admin, contracts.apxETH, contracts.pybapxETH);

        // it should set apxETH
        assertEq(address(localApxETHVault.APXETH()), contracts.apxETH, "apxETH address is not set correctly");
        // it should set pirexETH
        assertEq(address(localApxETHVault.PIREX_ETH()), contracts.pirexETH, "pirexETH address is not set correctly");
        // it should set pybapxETH
        assertEq(
            address(localApxETHVault.PERP_YIELD_BEARING_AUTO_PX_ETH()),
            contracts.pybapxETH,
            "pybapxETH address is not set correctly"
        );
        // it should set the owner
        assertEq(localApxETHVault.owner(), users.admin, "owner is not set correctly");
    }
}
