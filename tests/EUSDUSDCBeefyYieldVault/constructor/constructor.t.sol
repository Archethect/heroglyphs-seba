// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { EUSDUSDCBeefyYieldVault } from "src/EUSDUSDCBeefyYieldVault.sol";

contract ConstructorTest is BaseTest {
    function test_WhenAdminIsZero() external {
        // it whould revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.InvalidAddress.selector));
        new EUSDUSDCBeefyYieldVault(
            address(0),
            users.yieldManager,
            contracts.weth,
            contracts.usdc,
            contracts.swapRouter,
            contracts.quoter,
            contracts.curvePool,
            contracts.beefy
        );
    }

    function test_RevertWhen_YieldManagerIsZero() external whenAdminIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.InvalidAddress.selector));
        new EUSDUSDCBeefyYieldVault(
            users.admin,
            address(0),
            contracts.weth,
            contracts.usdc,
            contracts.swapRouter,
            contracts.quoter,
            contracts.curvePool,
            contracts.beefy
        );
    }

    function test_RevertWhen_WethIsEro() external whenAdminIsNotZero whenYieldManagerIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.InvalidAddress.selector));
        new EUSDUSDCBeefyYieldVault(
            users.admin,
            users.yieldManager,
            address(0),
            contracts.usdc,
            contracts.swapRouter,
            contracts.quoter,
            contracts.curvePool,
            contracts.beefy
        );
    }

    function test_RevertWhen_UsdcIsZero() external whenAdminIsNotZero whenYieldManagerIsNotZero whenWethIsNotZero {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.InvalidAddress.selector));
        new EUSDUSDCBeefyYieldVault(
            users.admin,
            users.yieldManager,
            contracts.weth,
            address(0),
            contracts.swapRouter,
            contracts.quoter,
            contracts.curvePool,
            contracts.beefy
        );
    }

    function test_RevertWhen_SwapRouterIsZero()
        external
        whenAdminIsNotZero
        whenYieldManagerIsNotZero
        whenWethIsNotZero
        whenUsdcIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.InvalidAddress.selector));
        new EUSDUSDCBeefyYieldVault(
            users.admin,
            users.yieldManager,
            contracts.weth,
            contracts.usdc,
            address(0),
            contracts.quoter,
            contracts.curvePool,
            contracts.beefy
        );
    }

    function test_RevertWhen_QuoterIsZero()
        external
        whenAdminIsNotZero
        whenYieldManagerIsNotZero
        whenWethIsNotZero
        whenUsdcIsNotZero
        whenSwapRouterIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.InvalidAddress.selector));
        new EUSDUSDCBeefyYieldVault(
            users.admin,
            users.yieldManager,
            contracts.weth,
            contracts.usdc,
            contracts.swapRouter,
            address(0),
            contracts.curvePool,
            contracts.beefy
        );
    }

    function test_RevertWhen_CurvePoolIsZero()
        external
        whenAdminIsNotZero
        whenYieldManagerIsNotZero
        whenWethIsNotZero
        whenUsdcIsNotZero
        whenSwapRouterIsNotZero
        whenQuoterIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.InvalidAddress.selector));
        new EUSDUSDCBeefyYieldVault(
            users.admin,
            users.yieldManager,
            contracts.weth,
            contracts.usdc,
            contracts.swapRouter,
            contracts.quoter,
            address(0),
            contracts.beefy
        );
    }

    function test_RevertWhen_BeefyIsZero()
        external
        whenAdminIsNotZero
        whenYieldManagerIsNotZero
        whenWethIsNotZero
        whenUsdcIsNotZero
        whenSwapRouterIsNotZero
        whenQuoterIsNotZero
        whenCurvePoolIsNotZero
    {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.InvalidAddress.selector));
        new EUSDUSDCBeefyYieldVault(
            users.admin,
            users.yieldManager,
            contracts.weth,
            contracts.usdc,
            contracts.swapRouter,
            contracts.quoter,
            contracts.curvePool,
            address(0)
        );
    }

    function test_WhenBeefyIsNotZero()
        external
        whenAdminIsNotZero
        whenYieldManagerIsNotZero
        whenWethIsNotZero
        whenUsdcIsNotZero
        whenSwapRouterIsNotZero
        whenQuoterIsNotZero
        whenCurvePoolIsNotZero
    {
        EUSDUSDCBeefyYieldVault localEUSDUSDCBeefyYieldVault = new EUSDUSDCBeefyYieldVault(
            users.admin,
            users.yieldManager,
            contracts.weth,
            contracts.usdc,
            contracts.swapRouter,
            contracts.quoter,
            contracts.curvePool,
            contracts.beefy
        );

        // it should grant the correct roles
        assertEq(
            localEUSDUSDCBeefyYieldVault.hasRole(localEUSDUSDCBeefyYieldVault.ADMIN_ROLE(), users.admin),
            true,
            "admin should have the ADMIN role"
        );
        assertEq(
            localEUSDUSDCBeefyYieldVault.hasRole(localEUSDUSDCBeefyYieldVault.YIELDMANAGER_ROLE(), users.yieldManager),
            true,
            "yieldManager should have the YIELDMANAGER role"
        );

        assertEq(
            localEUSDUSDCBeefyYieldVault.getRoleAdmin(localEUSDUSDCBeefyYieldVault.ADMIN_ROLE()),
            localEUSDUSDCBeefyYieldVault.ADMIN_ROLE(),
            "admin role should be admin role admin"
        );
        assertEq(
            localEUSDUSDCBeefyYieldVault.getRoleAdmin(localEUSDUSDCBeefyYieldVault.YIELDMANAGER_ROLE()),
            localEUSDUSDCBeefyYieldVault.ADMIN_ROLE(),
            "admin role should be yield manager role admin"
        );

        // it should set the correct weth
        assertEq(address(contracts.weth), localEUSDUSDCBeefyYieldVault.WETH(), "weth is not correct");
        // it should set the correct usdc
        assertEq(address(contracts.usdc), localEUSDUSDCBeefyYieldVault.USDC(), "usdc is not correct");
        // it should set the correct swapRouter
        assertEq(
            address(contracts.swapRouter),
            address(localEUSDUSDCBeefyYieldVault.swapRouter()),
            "swapRouter is not correct"
        );
        // it should set the correct quoter
        assertEq(address(contracts.quoter), address(localEUSDUSDCBeefyYieldVault.quoter()), "quoter is not correct");
        // it should set the correct curvePool
        assertEq(
            address(contracts.curvePool),
            address(localEUSDUSDCBeefyYieldVault.curvePool()),
            "curvePool is not correct"
        );
        // it should set the correct beefy
        assertEq(address(contracts.beefy), address(localEUSDUSDCBeefyYieldVault.beefy()), "beefy is not correct");
    }
}
