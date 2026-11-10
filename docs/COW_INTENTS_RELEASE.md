# CoW intents — review and release runbook

Draft for the stacked CoW PRs. Not production authorization; do not deploy, broadcast transactions, move funds, change
hosted services or merge from this document. The V2 migration approval gate remains in force.

## Review status and accepted migration risks

The frozen-source [three-pass Pashov review](../audits/v2-cow-pashov-20261110.md) returned **35 of
36** planned specialist reviews (one pass-two access reviewer failed at the platform boundary). It reported five
migration-availability findings and no confirmed unauthorized asset extraction. It is not an audit of subsequent
hardening changes, and the separate companion chat could not verify a Daybreak model selection. The exact live CoW
order format/zero-fee acceptance remains unproved and blocks production enablement.

The Safe-approved exact-snapshot and zero-live-legacy-claims gates are intentionally strict. An unprivileged party can
send one wei to the old manager/router, send an extra Beefy share atom to the old adapter, or hold a valid public legacy
claim. Each can veto Stage B or require a newly reviewed handoff; none should be treated as safely auto-retryable. The
historical-ID scan also grows with every deposit ID. The currently observed nine IDs are not a gas blocker, but a full
current-block Safe-batch gas simulation is mandatory before Stage A. If any snapshot, residual cap, live-claim or gas
condition fails, **abort before Stage A where possible**; if Stage A already completed, leave parked ETH in the old
manager and seek fresh Safe approval. Do not bypass or loosen these gates without a separate design decision.

## Approved behavior and trust boundary

Only DEX swap portions change to CoW orders. Keep direct Rocket Pool minting, direct Yearn deposit/redemption,
BOLD-to-sBOLD deposits and pybSeba top-ups. Native supporter deposits/withdrawals do not use CoW.

The user approved V1's quote/fixed-minimum model without Pyth. The backend obtains a verified quote, validates its
identities/amounts/expiry and applies the approved slippage tolerance to set the immutable BOLD minimum. Onchain
contracts bound the source, sell budget, tokens, receiver and expiry, **not economic fair value**. A compromised
operator or bad quote can misprice protocol capital and harvested yield. A per-call cap is not a cumulative spending or
loss limit. CoW cannot guarantee a fill or create liquidity when none is available.

An order's minimum does not automatically improve when market prices move after placement. Quote expiry and order expiry
are distinct; neither may be silently extended. Production caps, thresholds, slippage, TTL and operator funding need
separate Safe approval. All new execution starts disabled.

The quote's expiration gates opening authorization. After confirmation, retries post the same immutable order until its
signed `validTo`; quote expiry does not revoke the public pre-signature. Existing downstream contracts such as sBOLD can
still have their own oracle/freshness checks. Removing Seba's DEX-oracle guards does not remove those dependencies.

Direct Rocket Pool/Yearn operations retain **exact** backend previews. The user declined a preview-drift tolerance:
Yearn's rate can change between the preview block and the execution block, causing a healthy ysyBOLD deployment to
revert and remain pending for retry. A fork reproduced this on the source-1 BOLD deployment; loosening the minimum by
1 bp made that local transaction pass, but that tolerance is **not** implemented or approved. A separate sBOLD oracle
returned `TooStalePrice()` on the time-warped fork, blocking donation independently of CoW. Do not represent the local
composite rehearsal as a completed healthy donation or assume repeated exact previews will eventually succeed.

## Sources and accounting

| Source | Input debited at order creation                | Proven-fill BOLD                     | Unfilled refund          |
| ------ | ---------------------------------------------- | ------------------------------------ | ------------------------ |
| 0      | `pendingEth[0]`, immediate reward ETH          | `pendingBold`, rewards               | Same pending ETH purpose |
| 1      | `pendingEth[2]`, ysyBOLD protocol ETH          | `pendingProtocolBold`, never rewards | Same pending ETH purpose |
| 2      | `harvestInventory[0][0]`, supporter rETH carry | `pendingBold`, rewards               | Same carry bucket        |
| 3      | `harvestInventory[0][1]`, protocol rETH carry  | `pendingBold`, rewards               | Same carry bucket        |

ETH orders use WETH internally. Each order has one isolated escrow/receiver, an exact finite relayer allowance and a
56-byte UID. A nonzero BOLD balance alone is not fill proof. CoW's `filledAmount` alone is not permanent proof either:
expired storage can be cleared. Reconciliation must establish the one-shot authorized sell spend and measure actual
refund/output before recording a terminal result exactly once.

After a proven fill, gross BOLD receipts in that escrow belong to its source, including unsolicited same-purpose BOLD.
Pure execution analytics must use CoW trade receipts rather than claiming every escrow token was bought. BOLD donated to
an unfilled order is quarantined and cannot fake a fill; surplus rescue is Safe-only after the order is terminal.

ysyBOLD protocol capital remains in-flight or pending BOLD until direct Yearn deposits and native-vault credit succeed.
Credit actual final shares and their yBOLD basis, not original ETH spent. Never debit the same ETH again on deployment.
Only `DonationCompleted` denotes a completed pybSeba donation; order creation/fill and sBOLD minting do not.

## Roles

- Safe: configures/pauses modules and caps, grants/revokes bounded operators, cancels early, rescues terminal surplus,
  recovers buffers and authorizes proxy upgrades. Existing upgrade powers can change all asset-moving logic.
- Backend operator: requests verified quotes, opens typed capped orders, submits exactly the authorized order to CoW,
  reconciles filled/expired orders, deploys settled protocol BOLD and donates classified rewards. No arbitrary token,
  destination, calldata, signer or authority change is permitted.
- CoW orderbook/solvers: provide discovery and execution liveness. HTTP/API status alone cannot credit manager balances.
  No private signing key for the manager/escrow is given to the backend or a solver; the escrow authorizes its one
  order.
- Legacy Aragon authority: unchanged. The existing pool-level authority overlap must remain disclosed in V2 release
  docs.

## Normal maintenance

1. Verify chain ID, manager/module/executor identities, proxy implementations, configured caps and flags against the
   reviewed deployment manifest. Read one canonical block/hash; do not combine state across a reorg.
2. Reconcile active source orders before creating replacements. After a restart or posting timeout, retry the same
   stored order UID, not a newly priced order spending the same inventory. Never wait inside a Lambda for a fill.
3. For eligible source inventory, predict the new escrow, obtain/validate a fresh quote for that exact owner/receiver,
   compute a positive final BOLD minimum and bind the next order ID. Simulate before submitting the creation
   transaction.
4. After confirming the creation receipt and canonical block, submit the exact stored order to the orderbook. The
   network-fee/protocol-fee conversion must match current quote semantics and the contract's gross budget.
5. Finalize only using the module/escrow's onchain terminal evidence and measured custody. An unfilled order is normally
   refundable only strictly after its inclusive `validTo`. The Safe may cancel earlier; fill-before-cancel is possible.
6. Invest source-1 BOLD through Yearn separately. Convert reward BOLD to sBOLD, then top up pybSeba. Retain failed-stage
   inventory for retry without relabeling it as invested principal or completed income. For direct operations, the
   backend intersects the manager cap with the direct executor cap and live Rocket Pool/Yearn capacity. Those direct
   caps and views must not limit unrelated CoW sources. Pausing the direct executor does not block minting sBOLD or
   donating already-settled reward BOLD; the manager's execution pause still does.
7. Compare all source/in-flight/pending balances with actual custody and GraphQL at an exact matching block/hash.

## Emergency pause, cancellation and recovery

Pausing new execution is **not the same as cancelling already authorized CoW orders**. With PreSign, an outstanding
order can still fill within its fixed minimum/expiry until its authorization/allowance is actually revoked. Do not
promise immediate cancellation from an offchain API request.

1. Stop backend order creation; Safe disables affected opening/execution paths. Native supporter exits stay independent.
2. Read each of the four bounded active-source slots and build a reviewed Safe batch cancelling/finalizing every live
   order. Verify each exact ID/UID/escrow; a fill before the cancellation is mined must reconcile as a fill, not refund.
3. Confirm all active counts/slots are zero, allowances revoked and orders terminal. Classify measured refunds/proceeds
   into their original sources. Keep unfilled donated output out of principal/reward receipts.
4. Only then recover manager buffers through the existing Safe recovery procedure, including pending protocol BOLD.
   Publish exact per-source quantities and reconciliation commitment. Active escrows must not be erased by a buffer
   recovery event or silently bypassed by replacing the module.
5. Safe may rescue terminal escrow surplus only to treasury. Unavailable CoW APIs or price feeds must not prevent this.
   Recovery is not a guarantee of par, and already filled swaps cannot be rolled back.

Unsolicited tokens/forced ETH sent directly to the immutable module, rather than an order escrow, stay unclassified and
have no module-level sweep. Normal order operations preserve that unrelated baseline. Do not send funds manually to the
module or count such donations as assigned capital or recoverable manager inventory.

## Verification and abort gates

Local post-audit evidence (2026-11-10): `node tools/v2/check-coverage.cjs /private/tmp/seba-cow-postaudit-unit.lcov`
reported **100% lines, branches and functions for all ten measured V2 onchain targets**, with no changed production
source excluded. The coverage run had 256 V2 unit tests. The full Foundry run first had 447 passing tests and one
legacy fork `setUp()` failure from transient Alchemy DNS; the rerun exited successfully. Targeted pinned fork
migration passed 5/5 and imported 1.4893780996765226 ETH of actual old protocol capital, not synthetic funding.
`node tools/v2/check-artifacts.cjs` passed EIP-170/initcode and the pre-CoW layout commitment; the manager runtime is
22,662/24,576 bytes. OpenZeppelin standalone upgrade validation passed for manager, both vaults and a compatible
manager upgrade fixture. The three repository tests, local Graph reorg and independent post-audit diff review are
additional evidence, not substitutes for live order acceptance or release approval.

- Unit, branching-tree, value-math fuzz and stateful conservation invariants for every changed onchain path; honest 100%
  line/every-branch results and no excluded changed production code disguised as full coverage.
- Real CoW settlement/relayer/token fork integration, authorized local solver/funding injections explicitly labeled;
  test no fill, expiry, fill/cancel races, double settlement, donations, storage cleanup, concurrent sources and
  recovery.
- Backend restart/reorg/duplicate posting/concurrent invocations/invalid API response tests. Subgraph lifecycle tests
  and real Graph Node replay must reconcile source custody and principal versus rewards without double counting.
- Storage-layout/initialization/upgrade authority and EIP-170/initcode size checks; independent security review and
  static analysis, with confirmed findings fixed and regressions rerun.
- Separate live orderbook/solver fill acceptance remains a production validation gate: a quote or synthetic local
  settlement is not proof of a future live fill. No live test order is authorized by this runbook.
- Abort on unexpected identities, source mismatch, allowance drift, unproven terminal state, quote/UID drift,
  unacceptable quote economics, missing real integration evidence, indexing errors or any unexplained custody delta.

## Cross-repository and frontend handover

Release contracts, backend ABI/config and subgraph schema/handlers as one compatible version. Keep new automation
disabled until all three identities and indexed deployment boundaries are verified. Display pending order, unfilled,
expired/cancelled, settled-but-uninvested protocol BOLD and completed donation as distinct states. Do not show a CoW
order as a public supporter deposit or erase the existing 30-day native position lock.

The isolated test rehearsal uses Anvil loopback port 38545 and new CoW-specific Graph Node volumes/ports. Do not reset
the retained V2 28545 environment, funded mainnet-test stack, old Hoodi deployment or legacy production graph history.
Local delta replay is not a complete historical rebuild or hosted production deployment.

The isolated local reorg rehearsal at fork block 26384078 indexed an orphaned `CowExecutionSet(true)` receipt, reverted
that Anvil block, mined a different transaction at the same height restoring `false`, and advanced the local chain.
Graph Node removed the orphaned transaction `0x296b0a89f856c08736bd89a4c670936f40112c2b92cca0cbc04178d0bfc3c175`, indexed replacement
`0xc3fba4ada21d6f2d43bcc626f379a82a037af4cdf431c1efaf49041fcffec97b`, and showed the module disabled at canonical
block 26384079. The repeatable, loopback-guarded test is `node tools/cow/local-graph-reorg.cjs FIXTURE --execute-local`;
it requires a fresh fixture head and dedicated ports 38545/38000. This proves local rollback for that event, not every
possible cross-chain/indexer reorg.
The script was rerun from a fresh checkpoint at block 26384085 and passed independently at competing block 26384086,
reporting `orphanEventRemoved=true`, `replacementEventIndexed=true`, and `stateRestored=true`.
