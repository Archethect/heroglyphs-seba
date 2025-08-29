// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct Users {
    address payable admin;
    address payable automator;
    address payable validator;
    address payable nonValidator;
    address payable yieldManager;
}

struct Contracts {
    address sebaPool;
    address yieldManager;
    address mockSimpleYieldManager;
    address pybSeba;
    address sBOLD;
    address bold;
    address WETH;
    address USDC;
    address ethToBoldRouter;
    address eUsdUsdcBeefyYieldVault;
    address ethFlow;
    address ethUsdFeed;
    address settlement;
    address swapRouter;
    address quoter;
    address curvePool;
    address beefy;
}
