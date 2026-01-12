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

    modifier whenTheAmountOfSharesForTheAssetsIsNotZero() {
        _;
    }

    modifier whenTheCallerHasTheAdminRole() {
        resetPrank(users.admin);
        _;
    }

    modifier whenEthFlowIsNotZero() {
        _;
    }

    modifier whenBoldIsNotZero() {
        _;
    }

    modifier whenWethIsNotZero() {
        _;
    }

    modifier whenEthUsdFeedIsNotZero() {
        _;
    }

    modifier whenTheValueIsNotZero() {
        _;
    }

    modifier whenTheFeeIsSmallerThanTheBpsDenominator() {
        _;
    }

    modifier whenTheSlippageIsSmallerThanTheBpsDenominator() {
        _;
    }

    modifier whenThereIsNoOpenOrderYet() {
        _;
    }

    modifier whenTheOraclePriceIsBiggerThanZero() {
        _;
    }

    modifier whenSettlementIsNotZero() {
        _;
    }

    modifier whenTheCallerIsTheYieldManager() {
        _;
    }

    modifier whenThereIsAnActiveOrder() {
        _;
    }

    modifier whenYieldManagerIsNotZero() {
        _;
    }

    modifier whenUsdcIsNotZero() {
        _;
    }

    modifier whenSwapRouterIsNotZero() {
        _;
    }

    modifier whenQuoterIsNotZero() {
        _;
    }

    modifier whenCurvePoolIsNotZero() {
        _;
    }

    modifier whenTheYieldFlowIsActive() {
        _;
    }

    modifier whenTheCurrentVaultValueIsBiggerThanThePrincipalValue() {
        _;
    }

    modifier whenTheDepositValueIsNotZero() {
        _;
    }

    modifier whenThereAreSharesToWithdraw() {
        _;
    }

    modifier whenTheAdmin() {
        _;
    }

    modifier whenSebaPoolIsNotZero() {
        _;
    }

    modifier whenRouterIsNotZero() {
        _;
    }

    modifier whenSBOLDIsNotZero() {
        _;
    }

    modifier whenSebaVaultIsNotZero() {
        _;
    }

    modifier whenThereIsYieldClaimed() {
        _;
    }

    modifier whenTheDepositAmountIsNotZero() {
        _;
    }

    modifier whenTheDepositorIsTheSender() {
        _;
    }

    modifier whenTheUnlockTimeHasBeenReached() {
        _;
    }

    modifier whenTheConversionTimeoutIsFinished() {
        _;
    }

    modifier whenBeefyIsNotZero() {
        _;
    }

    modifier whenTheEthUsdFeedDoesNotReturnZero() {
        _;
    }

    modifier whenTheUsdcUsdFeedDoesNotReturnZero() {
        _;
    }

    modifier whenTheEthUsdFeedIsNotStale() {
        _;
    }

    modifier whenTheUsdcUsdFeedIsNotStale() {
        _;
    }

    modifier whenTheQuotedUniswapPriceIsNotTooLow() {
        _;
    }

    modifier whenTheYieldSharesAreNotZero() {
        _;
    }

    modifier whenTheLpMintedIsNotZero() {
        _;
    }

    modifier whenTheSharesMintedIsNotZero() {
        _;
    }

    modifier whenTheCorrectArrayLength() {
        _;
    }

    modifier whenTheCorrectAmountIsPaid() {
        _;
    }
}
