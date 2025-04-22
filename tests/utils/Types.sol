// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct Users {
    address payable admin;
    address payable automator;
    address payable validator;
    address payable nonValidator;
}

struct Contracts {
    address boostPool;
    address poap;
    address pirexETH;
    address apxETH;
    address pybapxETH;
    address apxETHVault;
    address yieldManager;
}
