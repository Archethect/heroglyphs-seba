# CoW intents: research gate and implementation plan

Status: implemented for **draft PR review**, **not release-ready**. No production deployment, order submission, signing,
transaction broadcast or fund movement is authorized. Observations below were collected on 2026-11-10.

## Isolated bases

All three original V2 PRs remain open. New `codex/seba-v2-cow-intents` branches start from:

| Repository | V2 PR                             | Base commit                                |
| ---------- | --------------------------------- | ------------------------------------------ |
| Contracts  | Archethect/heroglyphs-seba#4      | `6a86d14e613a09cd01cf8fff5e911460392514bf` |
| Backend    | Archethect/hero_boost_backend#12  | `6e243925c8242fae83185e02114250b738438368` |
| Subgraphs  | Archethect/hero_boost_subgraphs#3 | `93a82811a380cf225daf5f4b5fe79d4f1cfc7185` |

Worktrees are under the contracts checkout's ignored `.worktrees/seba-cow/{contracts,backend,subgraphs}` directory. The
original dirty backend/subgraph checkouts and archived rETH stash remain untouched.

## What V1 actually did

The legacy backend requested a WETH/BOLD CoW quote using `sellAmountBeforeFee` and passed `quote.buyAmount` to
`YieldManager.runBoldConversion`. That manager supplied its configured slippage and validity to `EthToBoldRouter`. The
router created a fill-or-kill Eth-flow order with a fixed minimum BOLD amount and expiration.

The router **did not read Chainlink or enforce a BOLD peg**, despite its inaccurate NatSpec reference to Chainlink. The
Beefy adapter's ETH/USDC principal routes separately enforced Chainlink-derived minima. Therefore carrying V1's
quote-only CoW policy into the new ysyBOLD protocol-investment route would extend operator price discretion to new
protocol-owned capital, not just reward/yield conversion. No Pyth dependency existed in that V1 path.

## CoW observations

Read-only `POST /mainnet/api/v1/quote` requests using `priceQuality: verified` returned `verified: true` for WETH/BOLD
and rETH/BOLD at 0.01, 1 and 100 input-token sizes. These probes used the existing treasury Safe as owner/receiver and
PreSign/onchain-order quote settings. They do **not** prove acceptance of a future custom contract order or an actual
live solver fill. No order was posted.

Selected responses, sampled at 10:44:02–10:44:05 UTC:

| Gross input | Quoted BOLD buy amount    | Quoted network fee in input tokens |
| ----------- | ------------------------- | ---------------------------------- |
| 1 WETH      | 2091.466009741239669520   | 0.000310449616239077               |
| 100 WETH    | 209155.231110470237509831 | 0.000865972256776491               |
| 1 rETH      | 2458.541013497044044846   | 0.000313179313092431               |
| 100 rETH    | 245712.994788467419321976 | 0.000365673621360456               |

These are expired research quotes, not executable production instructions. Gross input equals quoted sell amount plus
network fee. Responses also reported `protocolFeeBps: 2`; fee treatment must be validated against current service
semantics, not deducted twice or silently ignored. Production slippage/caps/deadlines remain separately unapproved.

Mainnet code/identity checks found the canonical settlement and its relayer at the addresses in CoW's official list:
`0x9008D19f58AAbD9eD0D60971565AA8510560ab41` and `0xC92E8bdf79f0507f65a392b0ab4667716BFE0110`. The settlement, not an
arbitrary caller, controls the relayer. Addresses must be reverified before a production release.

## Accounting design constraints

- Keep four fixed order sources: immediate rewards, ysyBOLD protocol capital, rETH supporter carry and rETH protocol
  carry. Debit exactly one source on opening; return refunds/proceeds only to that source.
- Use one-shot isolated order custody/receiver rather than the legacy router's global order. One active order per source
  supports bounded concurrency and avoids unbounded recovery loops.
- Do not credit ysyBOLD principal before BOLD has settled, both Yearn deposits succeed and actual final shares/native
  yBOLD basis are measured. Settled protocol BOLD must never enter reward `pendingBold`.
- Direct Rocket Pool minting, direct Yearn deposit/redemption, BOLD/sBOLD and pybSeba top-up remain direct calls. Public
  native supporter exits must not depend on any order, oracle, solver or API.
- A CoW UID is 56 bytes. Settlement `filledAmount` is **not permanent fill proof**: expired entries may be cleared, and
  invalidation overwrites it. Prove spend using isolated custody and the finite relayer allowance semantics of the exact
  supported tokens, with fork tests. Never reuse an escrow or renew a closed order's allowance.
- Actual BOLD received can include unsolicited BOLD. A donation must never fake a fill. The classification of gross
  receipts after a proven fill must be explicit; unfilled-order donations remain quarantined.
- Cancellation/final reconciliation and Safe recovery must remain possible without price feeds or orderbook API
  availability. Handle fill-before-cancel, repeat finalization, restart and reorg paths.

## Approved price/trust policy

The current V2 Curve EMA BOLD-peg gate would remain a pool dependency even after moving execution to CoW. Replacing it
with Pyth would add a new oracle policy. After reviewing the actual V1 path, the user explicitly approved the **V1
quote/fixed-minimum approach without Pyth** on 2026-11-10. The CoW order encodes an exact sell budget, positive minimum
BOLD amount and bounded expiry. No Chainlink, Curve or Pyth price condition is added to these orders.

This is an accepted economic trust boundary: the authorized operator/backend selects the quote-derived minimum. Contract
checks restrict tokens, receivers, source inventory, per-call caps and expiry, but do not establish fair value. A
compromised operator or bad quote can misprice available protocol-owned capital as well as harvested yield. Per-call
caps are not a cumulative-loss limit. No oracle-based fallback or automatic tolerance widening is authorized. Direct
Rocket Pool and Yearn canonical accounting/zero-loss redemption checks remain in force.

Pyth's official Ethereum sponsored-feed data lists BOLD/USD, feed
`d6134dbb0427240f901e3e596d6e63f7d85088f96cd4cd4ae2f89c0819b5d623`. At block 26,383,988, the Core getter returned price
`99664516`, confidence `78080`, exponent `-8`, publish time `1794304641`; the block timestamp was `1794307403`. This one
sample does not establish freshness availability/SLA.

Pyth is research context only and is **not part of the approved implementation**. PreSign matches the approved fixed
limit model; the minimum does not automatically rise when the market moves while the order is pending. Optional appData
hooks are not treated as contract-enforced safety checks.

## TDD and integration sequence

1. Freeze the approved quote-only policy, order/escrow ABI, source accounting, events and recovery transitions.
2. Write red tests, then minimal escrow/router/manager changes. Cover each branch, value math fuzzing and handler-based
   conservation invariants; preserve storage layout and verify deployed code size.
3. Backend: bounded, restart-safe quote/post/reconcile/finalize; canonical onchain order records are retry authority,
   never API `fulfilled` alone. Validate quote identity, exact gross/net/fee accounting, minima and expiry.
4. Subgraph: new order lifecycle plus in-flight source quantities and separate protocol BOLD. Do not reuse existing
   synchronous `ProtocolDeployed`/`RewardsConverted` debit semantics and double-debit sources.
5. Fork-test real CoW contracts and token allowance behavior. Identify injected solver/funding and distinguish this from
   live orderbook acceptance/fill reliability. Run backend + Graph Node replay and reconcile exact block/hash.
6. Independent audit, static analysis, storage/size checks, complete regression/coverage, runbook and frontend handover.
   Open linked stacked PRs; keep draft if viability or E2E evidence is incomplete. Never deploy or merge.

## Evidence so far

- Existing manager baseline: 68 tests passed, zero failed/skipped. Handler invariant: 256 runs, 16,384 calls, zero
  reverts. This is baseline V2 evidence, not proof for unimplemented CoW behavior.
- Fresh fixed-route component fork at block 26,384,004: the ETH/BOLD aggregate test and treasury-sized rETH/BOLD test
  reverted with `Too little received`. In the ETH test, the 1 ETH call first succeeded with `2088.618145086959099772`
  BOLD. The subsequent 100 ETH call failed at Uniswap WETH/USDC: minimum `208300979736` USDC atoms versus actual
  `208210855043`. The aggregate failure must not be reported as failure of its 1 ETH call. The preceding 1 ETH swap
  affects the subsequent call's local pool state. No minimum was widened to make tests pass.
- The three-pass frozen-source audit at `2d77f42` returned 35/36 specialists; its
  [assembled report](../audits/v2-cow-pashov-20261110.md) records five migration-availability
  findings and eight leads, not a clean bill of health. Post-audit destination-preflight hardening was separately
  reviewed and tested. The measured changed onchain targets reached 100% lines/branches/functions in unit coverage;
  the current full Foundry run passed after retrying one transient Alchemy DNS setup failure. The isolated local
  backend/Graph replay reconciled canonical balances/events and a same-height reorg. **Live exact-order acceptance,
  actual solver fill, numeric production risk parameters, hosted indexer catch-up and frontend acceptance remain open
  release gates.** Draft PR review must not be mistaken for deployment authorization.

## CROPS/trust review

The proposed default isolates orders with fixed tokens/recipients and bounded operator actions. Native supporter exits
remain independent, but new investments/donations depend on CoW's orderbook/solver availability. Onchain cancellation
and Safe-directed recovery are the escape path; no automatic alternative venue is authorized.

Existing source/licensing and build paths remain unchanged; a new API dependency must be documented with reproducible
tools and clear endpoint configuration. Quote requests disclose token pairs, quantities and owner/receiver to CoW. No
private signing keys or RPC credentials belong in evidence, config or PRs. Existing Safe upgrade authority and legacy
Aragon overlap remain unchanged. Quote-only economic trust above was explicitly approved; numeric production limits
remain disabled and require separate approval.

## Primary sources

- [CoW core deployments and guarantees](https://docs.cow.fi/cow-protocol/reference/contracts/core)
- [CoW signing schemes](https://docs.cow.fi/cow-protocol/reference/core/signing-schemes)
- [CoW native tokens / recurring WETH orders](https://docs.cow.fi/cow-protocol/tutorials/cow-swap/native)
- [CoW settlement source](https://github.com/cowprotocol/contracts/blob/main/src/contracts/GPv2Settlement.sol)
- [CoW current quote schema](https://github.com/cowprotocol/services/blob/main/crates/model/src/quote.rs)
- [Pyth sponsored feeds](https://docs.pyth.network/pro/sponsored-feeds)
- [Pyth deployments](https://docs.pyth.network/pro/contract-addresses)
