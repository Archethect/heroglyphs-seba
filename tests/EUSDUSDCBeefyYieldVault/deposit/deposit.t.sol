// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "tests/Base.t.sol";
import { IEUSDUSDCBeefyYieldVault } from "src/interfaces/IEUSDUSDCBeefyYieldVault.sol";
import { ICurvePool } from "src/vendor/curve/ICurvePool.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { AggregatorV3Interface } from "src/vendor/chainlink/AggregatorV3Interface.sol";
import { IQuoter } from "src/vendor/uniswap_v3/IQuoter.sol";
import { IBeefyVault } from "src/vendor/beefy/IBeefyVault.sol";

contract DepositTest is BaseTest {
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
        eUsdUsdcBeefyYieldVault.deposit();
    }

    function test_RevertWhen_TheValueIsZero() external whenTheYieldManager {
        resetPrank(users.yieldManager);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.NoEthProvided.selector));
        eUsdUsdcBeefyYieldVault.deposit();
    }

    function test_RevertWhen_TheEthUsdFeedReturnsZero() external whenTheYieldManager whenTheValueIsNotZero {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 0, 0, 0, 0)
        );
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.OracleInvalid.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_RevertWhen_TheUsdcUsdFeedReturnsZero()
        external
        whenTheYieldManager
        whenTheValueIsNotZero
        whenTheEthUsdFeedDoesNotReturnZero
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            contracts.usdcUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 0, 0, 0, 0)
        );
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.OracleInvalid.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_RevertWhen_TheEthUsdFeedIsStale()
        external
        whenTheYieldManager
        whenTheValueIsNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            contracts.ethUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 1, 0, 0, 0)
        );
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.OracleStale.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_RevertWhen_TheUsdcUsdFeedIsStale()
        external
        whenTheYieldManager
        whenTheValueIsNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            contracts.usdcUsdFeed,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 1, 0, 0, 0)
        );
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.OracleStale.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_RevertWhen_TheQuotedUniswapPriceIsTooLow()
        external
        whenTheYieldManager
        whenTheValueIsNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
        whenTheUsdcUsdFeedIsNotStale
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            contracts.quoter,
            abi.encodeWithSelector(IQuoter.quoteExactInputSingle.selector),
            abi.encode(0)
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.SlippageExceeded.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_RevertWhen_TheLpMintedIsZero()
        external
        whenTheYieldManager
        whenTheValueIsNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
        whenTheUsdcUsdFeedIsNotStale
        whenTheQuotedUniswapPriceIsNotTooLow
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            contracts.curvePool,
            abi.encodeWithSelector(ICurvePool.add_liquidity.selector),
            abi.encode(0)
        );
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.SlippageExceeded.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_WhenTheSharesMintedIsZero()
        external
        whenTheYieldManager
        whenTheValueIsNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
        whenTheUsdcUsdFeedIsNotStale
        whenTheQuotedUniswapPriceIsNotTooLow
        whenTheLpMintedIsNotZero
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(contracts.beefy, abi.encodeWithSelector(IBeefyVault.depositAll.selector), abi.encode());
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.NoSharesMinted.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_WhenTheDepositValueIsZero()
        external
        whenTheYieldManager
        whenTheValueIsNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
        whenTheUsdcUsdFeedIsNotStale
        whenTheQuotedUniswapPriceIsNotTooLow
        whenTheLpMintedIsNotZero
        whenTheSharesMintedIsNotZero
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        mockAndExpectCall(
            contracts.beefy,
            abi.encodeWithSelector(IBeefyVault.getPricePerFullShare.selector),
            abi.encode(0)
        );
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEUSDUSDCBeefyYieldVault.ZeroDepositValue.selector));
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();
    }

    function test_WhenTheDepositValueIsNotZero()
        external
        whenTheYieldManager
        whenTheValueIsNotZero
        whenTheEthUsdFeedDoesNotReturnZero
        whenTheUsdcUsdFeedDoesNotReturnZero
        whenTheEthUsdFeedIsNotStale
        whenTheUsdcUsdFeedIsNotStale
        whenTheQuotedUniswapPriceIsNotTooLow
        whenTheLpMintedIsNotZero
        whenTheSharesMintedIsNotZero
    {
        resetPrank(users.yieldManager);
        vm.deal(users.yieldManager, 1 ether);

        uint256 lpBeforeDeposit = eUsdUsdcBeefyYieldVault.beefy().balanceOf(address(eUsdUsdcBeefyYieldVault));

        // it should emit Deposited
        //vm.expectEmit();
        //emit IEUSDUSDCBeefyYieldVault.Deposited(address(this), 1 ether,0);
        eUsdUsdcBeefyYieldVault.deposit{ value: 1 ether }();

        uint256 lpAfterDeposit = eUsdUsdcBeefyYieldVault.beefy().balanceOf(address(eUsdUsdcBeefyYieldVault));
        uint256 pps = beefy.getPricePerFullShare();

        // it should mint new shares
        assertGt(lpAfterDeposit, lpBeforeDeposit);
        // it should increase the principalShares
        assertEq(eUsdUsdcBeefyYieldVault.principalShares(), lpAfterDeposit - lpBeforeDeposit);
        // it should increase the principalValue
        assertEq(eUsdUsdcBeefyYieldVault.principalValue(), (((lpAfterDeposit - lpBeforeDeposit) * pps) / 1e18));
    }
}
