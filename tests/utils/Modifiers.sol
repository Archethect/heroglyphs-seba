// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Helpers } from "./Helpers.sol";

abstract contract Modifiers is Helpers {
    modifier whenAdminIsNotZero() {
        _;
    }

    modifier whenAutomatorIsNotZero() {
        _;
    }

    modifier whenSenderIsPoapOwner() {
        _;
    }

    modifier whenPoapIsFromStakersUnion() {
        _;
    }

    modifier whenTheAutomatorRole() {
        resetPrank(users.automator);
        _;
    }

    modifier whenTheValidatorRegistrationBlockIsNotZero() {
        _;
    }

    modifier whenTheValidatorIsNotYetGraduated() {
        _;
    }

    modifier whenTheAdminRole() {
        resetPrank(users.admin);
        _;
    }

    modifier whenBoostpoolIsNotZero() {
        _;
    }

    modifier whenApxETHIsNotZero() {
        _;
    }

    modifier whenApxEthVaultIsNotZero() {
        _;
    }

    modifier whenTheYieldManager() {
        resetPrank(contracts.yieldManager);
        _;
    }

    modifier whenYieldFlowIsActive() {
        _;
    }

    modifier whenTheOwner() {
        resetPrank(users.admin);
        _;
    }

    modifier whenTheDepositorIsTheYieldManager() {
        resetPrank(contracts.yieldManager);
        _;
    }

    modifier whenTheDepositorIsNotTheYieldManager() {
        _;
    }

    modifier whenTheSenderIsTheDepositor() {
        _;
    }
}
