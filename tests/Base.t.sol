// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

//import {SebaYieldVault} from "src/PerpYieldBearingAutoPxEth.sol";
//import { ApxETHVault } from "src/liquidity/ApxETHVault.sol";
//import { MockPirexETH } from "src/mocks/MockPirexETH.sol";
//import { MockApxETH } from "src/mocks/MockApxETH.sol";
import { Modifiers } from "tests/utils/modifiers.sol";
import { BoostPool } from "src/BoostPool.sol";
import { MockPOAP } from "src/mocks/MockPoap.sol";
import { YieldManager } from "src/YieldManager.sol";

/* solhint-disable max-states-count */
contract BaseTest is Modifiers {
    //MockPirexETH internal pirexETH;
    //MockApxETH internal apxETH;
    BoostPool internal boostPool;
    MockPOAP internal poap;
    YieldManager internal yieldManager;
    //SebaYieldVault internal pybapxEth;
    //ApxETHVault internal apxETHVault;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        _setupUsers();
        _setupContractsAndMocks();
        _grantRoles();

        setVariables(users, contracts);
    }

    function _setupUsers() internal {
        users.admin = createUser("admin");
        users.automator = createUser("automator");
        users.validator = createUser("validator");
        users.nonValidator = createUser("nonValidator");
    }

    function _setupContractsAndMocks() internal {
        vm.startPrank(users.admin);
        poap = new MockPOAP(users.admin);
        //pirexETH = new MockPirexETH(users.admin, 10_000);
       // apxETH = new MockApxETH(address(pirexETH));
        //pirexETH.setApxETH(address(apxETH));
        //pybapxEth = new PerpYieldBearingAutoPxEth(users.admin, apxETH);
        boostPool = new BoostPool(users.admin, users.automator);
        //apxETHVault = new ApxETHVault(users.admin, address(apxETH), address(pybapxEth));
        /*yieldManager = new YieldManager(
            users.admin,
            users.automator,
            address(boostPool),
            address(apxETH),
            address(apxETHVault),
            address(pybapxEth)
        );*/
        //pybapxEth.setBoostPool(address(boostPool));
        //boostPool.setPerpYieldBearingAutoPxEth(address(pybapxEth));
        boostPool.setYieldManager(address(yieldManager));
        //apxETHVault.setYieldManager(address(yieldManager));
        vm.stopPrank();

        contracts.boostPool = address(boostPool);
        contracts.poap = address(poap);
        //contracts.pirexETH = address(pirexETH);
        //contracts.apxETH = address(apxETH);
        //contracts.pybapxETH = address(pybapxEth);
        //contracts.apxETHVault = address(apxETHVault);
        contracts.yieldManager = address(yieldManager);
    }

    /* solhint-disable no-empty-blocks */
    function _grantRoles() internal {}
    /* solhint-enable no-empty-blocks */
}
/* solhint-enable max-states-count */
