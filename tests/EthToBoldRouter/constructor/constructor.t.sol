// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEthToBoldRouter } from "src/interfaces/IEthToBoldRouter.sol";
import { EthToBoldRouter } from "src/EthToBoldRouter.sol";

contract ConstructorTest is BaseTest {
    function test_WhenEthFlowIsZero() external {
        // it whould revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.InvalidAddress.selector));
        new EthToBoldRouter(address(0), contracts.bold, contracts.ethUsdFeed, users.admin, users.yieldManager);
    }

    function test_RevertWhen_BoldIsZero() external whenEthFlowIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.InvalidAddress.selector));
        new EthToBoldRouter(contracts.ethFlow, address(0), contracts.ethUsdFeed,users.admin, users.yieldManager);
    }

    function test_RevertWhen_EthUsdFeedIsZero() external whenEthFlowIsNotZero whenBoldIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.InvalidAddress.selector));
        new EthToBoldRouter(contracts.ethFlow, contracts.bold, address(0),users.admin, users.yieldManager);
    }

    function test_RevertWhen_AdminIsZero()
        external
        whenEthFlowIsNotZero
        whenBoldIsNotZero
        whenEthUsdFeedIsNotZero
        whenSettlementIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.InvalidAddress.selector));
        new EthToBoldRouter(contracts.ethFlow, contracts.bold, contracts.ethUsdFeed, address(0), users.yieldManager);
    }

    function test_RevertWhen_YieldManagerIsZero()
        external
        whenEthFlowIsNotZero
        whenBoldIsNotZero
        whenEthUsdFeedIsNotZero
        whenSettlementIsNotZero
        whenAdminIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEthToBoldRouter.InvalidAddress.selector));
        new EthToBoldRouter(contracts.ethFlow, contracts.bold, contracts.ethUsdFeed, users.admin, address(0));
    }

    function test_WhenYieldManagerIsNotZero()
        external
        whenEthFlowIsNotZero
        whenBoldIsNotZero
        whenEthUsdFeedIsNotZero
        whenSettlementIsNotZero
        whenAdminIsNotZero
    {
        EthToBoldRouter localEthToBoldROuter = new EthToBoldRouter(contracts.ethFlow, contracts.bold, contracts.ethUsdFeed, users.admin, users.yieldManager);

        // it should grant the correct roles
        assertEq(
            localEthToBoldROuter.hasRole(localEthToBoldROuter.ADMIN_ROLE(), users.admin),
            true,
            "admin should have the ADMIN role"
        );
        assertEq(
            localEthToBoldROuter.hasRole(
                localEthToBoldROuter.YIELD_MANAGER_ROLE(),
                users.yieldManager
            ),
            true,
            "yieldManager should have the YIELD_MANAGER role"
        );

        assertEq(
            localEthToBoldROuter.getRoleAdmin(localEthToBoldROuter.ADMIN_ROLE()),
            localEthToBoldROuter.ADMIN_ROLE(),
            "admin role should be admin role admin"
        );
        assertEq(
            localEthToBoldROuter.getRoleAdmin(localEthToBoldROuter.YIELD_MANAGER_ROLE()),
            localEthToBoldROuter.ADMIN_ROLE(),
            "admin role should be yield manager role admin"
        );

        // it should set the correct ethFlow
        assertEq(address(localEthToBoldROuter.ETH_FLOW()), contracts.ethFlow,"EthFlow is not correct");
        // it should set the correct bold
        assertEq(address(localEthToBoldROuter.BOLD()), contracts.bold,"BOLD is not correct");
        // it should set the correct ethUsdFeed
        assertEq(address(localEthToBoldROuter.ETH_USD_FEED()), contracts.ethUsdFeed,"EthUsdFeed is not correct");
    }
}
