// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ManagerTestBase, ManagerTokenMock } from "../ManagerTestBase.t.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ManagerInitializationConfigurationTest is ManagerTestBase {
    function _fresh() internal returns (YieldManagerV2) {
        address implementation = deployCode("YieldManagerV2.sol:YieldManagerV2");
        return YieldManagerV2(payable(address(new ERC1967Proxy(implementation, ""))));
    }
    function test_EveryConfiguredIntegrationRequiresCode() public {
        for (uint8 i; i < 7; ++i) {
            YieldManagerV2 fresh = _fresh();
            IYieldManagerV2.Initialization memory c = _configuration();
            if (i == 0) c.treasury = address(0);
            if (i == 1) c.pool = address(0);
            if (i == 2) c.bold = address(0);
            if (i == 3) c.sBold = address(0);
            if (i == 4) c.pybSeba = address(0);
            if (i == 5) c.reth = address(0);
            if (i == 6) c.ysyBold = address(0);
            vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
            fresh.initialize(c);
        }
    }
    function test_SelfReferencesAliasesAndWrongAssetGraphReject() public {
        for (uint8 i; i < 7; ++i) {
            YieldManagerV2 fresh = _fresh();
            IYieldManagerV2.Initialization memory c = _configuration();
            if (i == 0) c.treasury = address(fresh);
            if (i == 1) c.pool = address(fresh);
            if (i == 2) c.bold = c.sBold;
            if (i == 3) c.reth = c.ysyBold;
            if (i == 4) c.sBold = address(ysyToken);
            if (i == 5) c.pybSeba = address(ysyToken);
            if (i == 6) c.ysyBold = address(new ManagerTokenMock(address(0)));
            vm.expectRevert(IYieldManagerV2.InvalidConfiguration.selector);
            fresh.initialize(c);
        }
    }
    function test_ZeroOperatorIsAllowedButAllExecutionStillDisabled() public {
        YieldManagerV2 fresh = _fresh();
        IYieldManagerV2.Initialization memory c = _configuration();
        c.operator = address(0);
        fresh.initialize(c);
        assertFalse(fresh.operators(address(0)));
        assertFalse(fresh.intakeEnabled());
        assertFalse(fresh.executionEnabled());
        assertEq(fresh.rethBps(), 5_000);
        assertEq(fresh.ysyBoldBps(), 5_000);
        assertEq(fresh.weightVersion(), 1);
    }
}
