# yBOLD architecture and security decision

Review date: 2026-10-22. See [the rollout/recovery runbook](YBOLD_MIGRATION_RUNBOOK.md) and
[test/audit evidence](../audits/ybold-stack-20261022/REVIEW.md). This is not a deployment approval or guarantee of
safety.

## Asset and compatibility decision

The proposed position is **ysyBOLD**, also called **st-yBOLD**: token `0x23346B04a7f55b8760E5860AA5A77383D63491cD`. Its
asset is yBOLD, whose asset is BOLD. This is not a separate unreviewed leveraged product. The graph is confirmed by live
`asset()`/`symbol()` reads and [Yearn's source](https://github.com/yearn/yBOLD) and
[risk documentation](https://github.com/yearn/risk-score/blob/master/reports/report/flex.md). Plain yBOLD targets
approximately one BOLD; profits accrue to the staked wrapper. Neither parity nor yield is guaranteed.

ETH entry: WETH→USDC (Uniswap V3)→BOLD (Curve)→yBOLD→ysyBOLD. Normal exit reverses this and pays **ETH to
YieldManager**. The deployed YieldManager and SebaPool are unchanged. Manager user IDs retain their recorded adapter and
30-day lock; protocol principal is independent. Backend and indexer changes are required to distinguish native units and
recovery.

Do not reuse August APY/TVL observations as current estimates. No current APY is promised here. Compare net delivered
yield after fees, two Yearn redemptions, swaps, gas and manager CoW conversion, not headline vault APY. Evaluate
harvests regularly and execute only when expected yield clears costs and safety margin. This is not a quarterly-only
process.

At the pinned fork the whole actual treasury position (156,014.003721394916792917 ysyBOLD) can be liquidated through the
reviewed route for roughly **71.04 ETH**, before gas. This is execution evidence at that block, not a standing quote, an
original-cost profit calculation, or a capacity guarantee for arbitrarily large deposits. Yearn limits, loss reports,
Curve depth/peg, Uniswap depth and fresh feeds must be checked at the full intended size before every tranche.

## Trust and invariant model

- Use standard OpenZeppelin UUPS/ERC1967 from the first deployment, atomically initialized with a locked implementation.
  Routine governance and treasury upgrade/recovery authority are distinct contract roles. No custom proxy.
- Treasury Safe upgrade authority can replace all logic and transfer all assets; the core-token rescue ban is not a
  governance constraint. Existing manager admins also retain broad strategy-switch power. External Yearn/Liquity/Curve/
  token/oracle governance and availability remain dependencies. Recovery protects against route failure, not asset loss.
- `principalValue` is yBOLD assets; `principalShares` is accounted ysyBOLD shares. Only unlocked value above principal
  is harvested. Underwater exits use pro-rata shares; healthy exits preserve unharvested yield, including the final
  exit. A material deficit blocks new deposits rather than socializing old loss to new capital. ERC4626 dust tolerance
  is 1e12.
- State-changing integration paths are role-gated and nonreentrant. ETH transfers occur after payout accounting updates;
  external failures revert manager ID deletion and adapter changes together. Exact ERC20 approvals are cleared
  afterward.
- Independent Chainlink ETH/USD and USDC/USD references bound swaps. Curve EMA plus a nominal BOLD floor fails closed on
  a material depeg rather than accepting a manipulated spot quote. Default execution slippage is 50 bps per venue, EMA
  peg band 100 bps, normal Yearn max loss 0, emergency Yearn max loss 100 bps. Caps are not recommended settings.
- Feed maximum ages are 1 hour ETH / 23 hours USDC. They intentionally fail closed; a maximum age shorter than a feed's
  normal heartbeat can create avoidable liveness gaps. Feed heartbeat provenance/operational cadence must be reviewed at
  release; there is no automatic tolerance widening. Treasury share recovery bypasses both feeds entirely.
- Pause/emergency stop entries and harvesting, not healthy principal exits. Treasury recovery freezes all ordinary
  paths, snapshots remaining liability, transfers exact accounted shares and reports any donation surplus separately. A
  donation cannot prevent recovery; a real shortfall still aborts. Surplus shares stay on proxy until all claims settle.
  Tracked yield shares with zero remaining principal can be recovered immediately without creating artificial claims.
  Pure unsolicited donations to a zero-tracked-share vault and other accidental core-token transfers remain
  upgrade-only; the routine rescue restriction has not been silently expanded.
- Final recovery ETH rate is uniformly floor-rounded and activated once, after sufficient authenticated treasury
  funding. Full, partial-loss and explicitly approved total-loss settlement are supported. A zero rate clears claims
  through the manager without fake funding. No direct user payments while manager IDs remain claimable. Existing locks
  are unchanged.
- Settlement pays only the manager, which clears existing IDs/protocol accounting. Last claim never gets a special
  favorable rate; only fully settled recovery permits excess ETH/donation sweeps. Custody/funding/rate/payment events
  support independent reconciliation. No conversion venue/oracle is needed to settle recovered ETH. The unchanged
  manager still calls the depositor's ETH receiver, even for zero payouts: a rejecting contract cannot clear its own ID
  and can delay final excess sweep, but cannot stop other users receiving their fixed-rate payouts.

## Review outcome and limits

The review fixed a donation-triggered recovery denial of service, made zero-ETH total-loss settlement explicit, ensured
recovery claimable-yield reads avoid unavailable Yearn calls, and corrected stale indexed principal-availability flags
after an upgrade. Release scripts now distinguish old/new native units, current treasury custody, residual protocol
principal, separate authorities, exact implementation/configuration and current Safe requirements.

The adapter/config validator have 100% focused line and branch coverage, backed by negative tests, stateful Foundry
sequences and real mainnet-fork integration. **This does not mean 100% coverage of the whole stack.** Backend/subgraph
coverage and short-vs-historical replay limits are explicitly reported in the evidence. Fault-injected oracle/venue
failures and future-time oracle refreshes are distinguished from actual current balances/venue execution.

AI review, static analyzers and passing tests cannot eliminate all potential exploits. Production readiness remains
conditional on unresolved release gates in the runbook, fresh execution simulation and human security approval. This
does not retrofit the deployed Beefy adapter or guarantee repayment at par.
