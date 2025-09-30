// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IBeefyVault } from "src/vendor/beefy/IBeefyVault.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { IQuoter } from "src/vendor/uniswap_v3/IQuoter.sol";
import { StdStorage, stdStorage } from "forge-std/src/StdStorage.sol";

contract ClaimYieldTest is BaseTest {
    using stdStorage for StdStorage;
    StdStorage private stdstore;

    function test_RevertWhen_NotTheYieldManager(address invocator) external {
        vm.assume(invocator != users.yieldManager && invocator != contracts.yieldManager);
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                invocator,
                eUsdUsdcBeefyYieldVault.YIELDMANAGER_ROLE()
            )
        );
        resetPrank(invocator);
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_WhenTheYieldFlowIsNotActive() external whenTheYieldManager {
        resetPrank(users.yieldManager);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(false)
        );

        // it should emit YieldClaimed
        vm.expectEmit();
        emit IEUSDUSDCBeefyYieldVault.YieldClaimed(0, 0);
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_WhenTheCurrentVaultValueIsSmallerOrEqualThanThePrincipalValue()
        external
        whenTheYieldManager
        whenTheYieldFlowIsActive
    {
        resetPrank(users.yieldManager);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(true)
        );
        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(0)
        );

        // it should emit YieldClaimed
        vm.expectEmit();
        emit IEUSDUSDCBeefyYieldVault.YieldClaimed(0, 0);
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_RevertWhen_TheYieldSharesAreZero()
        external
        whenTheYieldManager
        whenTheYieldFlowIsActive
        whenTheCurrentVaultValueIsBiggerThanThePrincipalValue
    {
        resetPrank(users.yieldManager);

        stdstore.target(contracts.eUsdUsdcBeefyYieldVault).sig("principalShares()").checked_write(1e18);

        stdstore.target(contracts.eUsdUsdcBeefyYieldVault).sig("principalValue()").checked_write(1e18);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(true)
        );
        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(1 ether + 1)
        );

        // it should emit YieldClaimed
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.NothingToClaim.selector));
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_RevertWhen_TheEthUsdFeedReturnsZero()
        external
        whenTheYieldManager
        whenTheYieldFlowIsActive
        whenTheCurrentVaultValueIsBiggerThanThePrincipalValue
        whenTheYieldSharesAreNotZero
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(true)
        );
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 pps = beefy.getPricePerFullShare();

        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(pps + 1 ether)
        );

        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 0, 0, 0, 0)
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.OracleInvalid.selector));
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_RevertWhen_TheUsdcUsdFeedReturnsZero()
        external
        whenTheYieldManager
        whenTheYieldFlowIsActive
        whenTheCurrentVaultValueIsBiggerThanThePrincipalValue
        whenTheYieldSharesAreNotZero
        whenTheEthUsdFeedDoesNotReturnZero
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(true)
        );
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 pps = beefy.getPricePerFullShare();

        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(pps + 1 ether)
        );

        mockAndExpectCall(
            contracts.usdcUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 0, 0, 0, 0)
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.OracleInvalid.selector));
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_RevertWhen_TheEthUsdFeedIsStale()
        external
        whenTheYieldManager
        whenTheYieldFlowIsActive
        whenTheCurrentVaultValueIsBiggerThanThePrincipalValue
        whenTheYieldSharesAreNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(true)
        );
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 pps = beefy.getPricePerFullShare();

        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(pps + 1 ether)
        );

        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 1, 0, 0, 0)
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.OracleStale.selector));
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_RevertWhen_TheUsdcUsdFeedIsStale()
        external
        whenTheYieldManager
        whenTheYieldFlowIsActive
        whenTheCurrentVaultValueIsBiggerThanThePrincipalValue
        whenTheYieldSharesAreNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(true)
        );
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 pps = beefy.getPricePerFullShare();

        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(pps + 1 ether)
        );

        mockAndExpectCall(
            contracts.usdcUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 1, 0, 0, 0)
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.OracleStale.selector));
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_RevertWhen_TheQuotedUniswapPriceIsTooLow()
        external
        whenTheYieldManager
        whenTheYieldFlowIsActive
        whenTheCurrentVaultValueIsBiggerThanThePrincipalValue
        whenTheYieldSharesAreNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
        whenTheUsdcUsdFeedIsNotStale
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(true)
        );
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 pps = beefy.getPricePerFullShare();

        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(pps + 1 ether)
        );

        mockAndExpectCall(
            contracts.quoter,
            abi.encodeWithSelector(IQuoter.quoteExactInputSingle.selector),
            abi.encode(0)
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.SlippageExceeded.selector));
        eUsdUsdcBeefyYieldVault.claimYield();
    }

    function test_WhenTheQuotedUniswapPriceIsNotTooLow()
        external
        whenTheYieldManager
        whenTheYieldFlowIsActive
        whenTheCurrentVaultValueIsBiggerThanThePrincipalValue
        whenTheYieldSharesAreNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
        whenTheUsdcUsdFeedIsNotStale
        whenTheQuotedUniswapPriceIsNotTooLow
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            users.yieldManager,
            abi.encodeWithSelector(IYieldManager.yieldFlowActive.selector),
            abi.encode(true)
        );
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 pps = beefy.getPricePerFullShare();

        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(pps + 1 ether)
        );

        pps = beefy.getPricePerFullShare();

        uint256 principalValue = eUsdUsdcBeefyYieldVault.principalValue();
        uint256 principalShares = eUsdUsdcBeefyYieldVault.principalShares();
        uint256 currentVaultValue = (principalShares * pps) / 1e18;
        uint256 yieldShares = ((currentVaultValue - principalValue) * 1e18) / pps;

        uint256 balanceBefore = users.yieldManager.balance;

        // it should emit YieldClaimed
        //vm.expectEmit();
        //emit IEUSDUSDCBeefyYieldVault.YieldClaimed(yieldShares, 461295094032920340);
        eUsdUsdcBeefyYieldVault.claimYield();

        // it should subtract the yieldShares from the principalShares
        assertEq(eUsdUsdcBeefyYieldVault.principalShares(), principalShares - yieldShares);
        // it should set the new principalValue
        assertEq(eUsdUsdcBeefyYieldVault.principalValue(), (eUsdUsdcBeefyYieldVault.principalShares() * pps) / 1e18);
        // it should sent the converted WETH to the sender
        uint256 balanceAfter = users.yieldManager.balance;
        assertGt(balanceAfter, balanceBefore);
    }
}
