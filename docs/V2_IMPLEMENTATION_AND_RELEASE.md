# Seba V2 implementation and release review

Implementation branch: `codex/seba-yield-manager-v2`, based on contracts `origin/main`
`0d2c922d4df05c38d934bc481e020ef7dd79dab0`. The original dirty rETH checkout is preserved.

**Not a deployment approval.** No public deployment, real fund transfer, infrastructure rollout or merge was performed.
Local Anvil deployments, impersonation and fork-only transactions are test fixtures. Production execution limits are
unapproved and all new operational paths start disabled. The user approved a **two-stage exit then exact handoff** and
**three deep-audit passes**. The bounded-residual audit fix and post-fix verification remain review inputs, not
deployment authorization.

## What changes, and why

| Component                        | Change                                                                                                                                             | Reason / compatibility boundary                                                                                                                   |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `YieldManagerV2`                 | New UUPS proxy; separately assigned reward/rETH/ysyBOLD ETH; fixed-route execution; classified carry; exact one-shot legacy import                 | Keeps the deployed pool's `depositFunds()` selector, but does not duplicate public supporter positions or the old CoW order machine               |
| `NativeSupporterVault`           | Shared two-bucket accounting, native positions, 30-day locks, recognized-yield collection and fully implemented recovery                           | SUPPORTER and PROTOCOL backing cannot subsidize each other; no principal queue or mandatory swap on user exit                                     |
| `RethSupporterVault`             | rETH in/out; canonical ETH basis; registry/report validation                                                                                       | Report freshness gates entry/harvest, not otherwise valid native withdrawals                                                                      |
| `YsyBoldSupporterVault`          | ysyBOLD in/out; canonical yBOLD basis; deployed Yearn API 3.0.4 semantics                                                                          | No BOLD/USD price or Yearn redemption needed for native exits; incompatible Yearn API changes fail closed                                         |
| `SebaV2Executor`                 | Immutable typed routes, independently enforced floors, exact approvals/deltas, per-call caps and fixed recipient                                   | No arbitrary target/calldata or keeper reimbursement; partial input consumption atomically reverts                                                |
| `LegacyProtocolPrincipalHandoff` | Immutable known-ETH snapshot after exit; same-transaction arm/precheck/import; Safe-approved residual caps and final assertion; zero legacy return | Uses the deployed manager's admin principal-deposit path without booking imported principal twice; ordinary old public deposits revert atomically |
| `LegacyIntakeStopper`            | Minimal always-reverting intermediate adapter, installed during the first-stage exit                                                               | Leaves recovered ETH in the old manager and prevents new old deposits/sweeps while the final exact handoff is approved                            |
| Existing core contracts          | No production-source edits to SebaPool, old manager, Beefy adapter, router or pybSeba                                                              | Old claims/history stay in their original era; the pool pointer changes only during a separately approved cutover                                 |
| Build/tooling                    | Pinned portable npm lock, fixed remapping typos/test import case, current Solhint, storage/size/coverage gates                                     | Reproducible CI; original mainnet runtime parity remains separately documented                                                                    |

The [approved spec](SEBA_YIELD_MANAGER_V2_SPEC.md) remains the economic/design reference. Historical references in that
spec are not evidence that the V2 implementation was previously audited.

## Units and ownership

Supporters deposit **rETH or ysyBOLD directly into the selected vault**, not ETH/yBOLD into the manager. Withdrawal
returns that same token, representing remaining principal basis, not necessarily the original token count. Recognized
growth is donated; locked/unreported future growth follows the returned token. Positions are public, nontransferable,
fully withdrawn at once, and locked for 30 days. Identity is `(chain ID, vault proxy, local ID)`; IDs start at **1**,
and each vault has its own counter.

Fresh pool rewards retain 50% direct rewards. The other half is initially split equally: **50/25/25 overall**. Changed
weights affect future receipts only, never pending cash or existing positions. Imported legacy protocol ETH is **100%
investment**, with no second reward haircut. Treasury-owned supporter deposits are still SUPPORTER capital, not protocol
capital; treasury token holdings are not automatically migrated.

| Authority                                                   | Can do                                                                                          | Cannot do under current implementation                                         |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Treasury Safe, `0x888D768764A2E304215247F0bA3457cCb0f0ab4f` | V2 configuration, operators, upgrades, recovery, protocol native withdrawals to itself          | Ordinary user-position withdrawal or unlock override; routine core-token sweep |
| Backend operator                                            | Bounded investment, harvest, conversion and completed donation                                  | Change configuration/recipients, move supporter principal, upgrade or recover  |
| Supporter                                                   | Deposit into selected leg; withdraw own unlocked position                                       | Rebalance another user's capital, claim twice or access protocol backing       |
| Retained Aragon DAO                                         | Existing legacy admin powers, including replacing pool manager / changing pybSeba configuration | No direct V2 proxy authority is granted by this implementation                 |

**The system is not globally Safe-only.** Aragon's retained legacy powers can redirect future inflows/reward
integration. The Safe's proxy upgrade authority can ultimately move all V2 assets, despite today's core-token rescue
restriction. This is a trusted-governance recovery model, not protection against a malicious/compromised governance
quorum or external Yearn/BOLD/Rocket Pool losses. A code-bearing address alone is not proof of multisig governance:
preflight must verify the actual reviewed Safe owners, threshold, modules and guard.

## Test evidence recorded locally

Compiler: Solidity 0.8.28, Cancun, optimizer 10,000. Foundry **1.5.1-stable**. Commands use `tools/v2/run-foundry.mjs`,
which parses `.env` with `util.parseEnv` and redacts RPC credentials. Do not print or pass the secret endpoint in
command arguments. Hosted CI is separate evidence until its actual runs pass.

```sh
node tools/v2/run-foundry.mjs --env-file /absolute/path/to/ignored/.env test
FOUNDRY_TEST=tests/v2 node tools/v2/run-foundry.mjs coverage --offline --no-match-path '**/fork/**' --report lcov --report-file v2-unit.lcov
node tools/v2/check-coverage.cjs v2-unit.lcov
node tools/v2/run-foundry.mjs build --force --build-info --build-info-path out/v2-complete-build-info
node tools/v2/check-artifacts.cjs
```

Measured complete suite after the residual-cap fix: **393 passed, 0 failed, 0 skipped** across 101 suites. Combined V2
non-fork unit suite: **208 passed** across 51 suites, including two stateful handlers, each **256 runs / 16,384 calls /
zero reverts**. Deployment script: **11 fork tests passed**, measured **52/52 lines, 6/6 Foundry branches and 3/3
functions**. Read-only preflight: **53 tests passed** and all **36 gates** passed on a fresh, separately isolated local
deployment before this final cap change; rerun at release. Targeted negative controls prove the invariant handlers
detect injected custody leaks and the rounding/execution regressions actually fail before their fixes. Final PR/CI
evidence must supersede these counts if code changes further.

| New executable onchain source  |   Lines | Foundry branches | Functions |
| ------------------------------ | ------: | ---------------: | --------: |
| NativeSupporterVault           | 328/328 |            66/66 |     47/47 |
| RethSupporterVault             |   34/34 |              7/7 |       5/5 |
| YsyBoldSupporterVault          |   14/14 |              3/3 |       3/3 |
| YieldManagerV2                 | 327/327 |            61/61 |     38/38 |
| SebaV2Executor                 | 202/202 |            40/40 |     24/24 |
| LegacyProtocolPrincipalHandoff | 179/179 |            26/26 |     15/15 |
| LegacyIntakeStopper            |     6/6 |              0/0 |       3/3 |

This is **100% measured line/branch/function coverage of these seven new executable sources**, not 100% coverage of
legacy code, inherited OpenZeppelin code, external protocols, backend or subgraphs. No executable V2 function is
excluded. Semantic cases additionally test short-circuit validation operands, authorization for every entry point, fault
rollback, order independence, live-claim reconciliation, dust and upgrade storage preservation. Coverage is not proof
that no exploit exists.

OpenZeppelin standalone upgrade-safety checks passed for all three implementations. Normalized storage snapshots include
enum member ordering; compiler AST IDs are intentionally not compared as storage semantics. Positive and corrupted-slot
negative controls accompany the size/layout checker. Optimized runtime bytes: manager **24,391**, rETH **21,501**,
ysyBOLD **21,073**, executor **16,204**, handoff **14,775**, stopper **243**. The manager has limited headroom below
24,576; CI enforces the actual optimized runtime/initcode limits. Test/script and unoptimized coverage size warnings are
not production artifact sizes.

### Real fork versus injected/synthetic behavior

- Pinned protocol regression: block **26,255,470**. Fresh two-stage migration/flow/recovery run: block **26,255,819**,
  **9 passed / 0 failed / 0 skipped** before the cap change. Post-fix, a fresh block **26,283,091** ran five migration
  tests including approved router-ETH dust and cap-plus-one fault injection; all passed. The real unchanged 3-of-7 Safe
  approves a standard MultiSendCallOnly transaction through three locally impersonated real owners; the threshold is not
  overridden.
- Fresh legacy exit/import at block 26,283,091: **1.341163713997148671 ETH**, then actual protocol credit into both real
  routes. No synthetic capital funds this handoff. Adapter residue remains **150 native principal atoms / 121 Beefy
  share atoms**, not ETH. Old IDs 1–9 were already closed; do not describe this as a new ID 4 withdrawal.
- Additional component tests exercise actual treasury-sized rETH/ysyBOLD and 1/100 ETH BOLD / 1/70 ETH ysyBOLD routes.
  Test risk values are explicitly unapproved, not a production recommendation by default.
- Manager flow fixtures additionally use labelled synthetic pool reward ETH. Recovery returns actual exported native
  tokens; withholding 10% simulates a treasury token shortfall, **not an observed executable liquidation loss**.
- Time advancement tests native lock expiry and already-reported Yearn profit unlocking. They do not refresh real oracle
  reports. A long warp can legitimately block downstream sBOLD/Pyth conversion; do not mock it fresh and claim a healthy
  real route. Native principal exits do not require that conversion.
- Venue/oracle failure injections prove isolation/recovery mechanics, not that those failures were observed on mainnet.
- A separate Safe Stage-B trace at block **26,283,085**, nine historical IDs, measured **633,033 execution gas** plus
  **31,872 intrinsic gas** for an approximate **664,905**. This is not a standalone receipt: local approval/Stage A
  warmed state. Fresh standalone Safe simulation remains mandatory before any approved Stage A.

## Required release gates and abort criteria

1. Complete the approved two-stage handoff and three-pass deep audit. Resolve all release-blocking findings and publish
   remaining risks. The audit found that arbitrary token donations could permanently veto a zero-residual handoff; four
   immutable, Safe-reviewed residual caps now permit only bounded disclosed surplus. **This does not eliminate
   donation-based migration denial:** an attacker can add one atom above a tightly set cap, or one wei to the old
   manager's exact-ETH balance, after approval. Each such drift aborts Stage B and requires a newly reconciled Safe
   handoff. This is the explicitly accepted governance-availability trade-off, not a guarantee of timely cutover. Fresh
   swap output changes between blocks: execute the first-stage exit, then approve an exact import of ETH already held by
   the old manager. There is no standing pre-exit swap quote.
2. Approve a numeric risk pack separately: caps, per-hop slippage, mint fee, oracle/report freshness, venue fee tiers,
   deadline, minimum entry/harvest sizes. Defaults remain disabled/zero. Never widen Yearn redemption loss above zero as
   an automatic fallback.
3. Complete fresh source/implementation, asset graph, Safe owner/threshold/module/guard and legacy role/order/custody
   reconciliation. Local zero UID/order flags alone do not prove no forgotten historical EthFlow escrow exists.
4. Frontend team completes the handover requirements; deploy matching dual-era backend/subgraph configuration, ABIs,
   receipts and start blocks. Prove full historical indexer catch-up separately from local delta replay.
5. Get explicit environment/state/configuration and transaction approvals. Only merged, reviewed release code may be
   proposed for actual deployment. No production action is authorized by this document.

Abort on a new legacy ID/live claim, changed Safe security state, changed code/identity, active/unreconciled order,
unexpected custody/allowance, stale quote, expired import, unacceptable native execution, impaired new-leg entry,
indexer error/lag, mismatched backend era or unapproved parameters. Do not retry by disabling checks.

## Normal rollout and operation

1. Rehearse in a **new isolated persistent mainnet fork** with dedicated backend state and Graph Node namespace.
   Preserve existing test environments: `HeroBoostBackendStackTestMain` is funded **mainnet**, not a disposable testnet;
   old Hoodi is architecturally different. Never use `cdk deploy --all` or reset either existing environment.
2. After separate approval, deploy the manager and two vaults through standard ERC1967Proxy with atomic initializers;
   implementation initializers stay locked. Deploy the typed executor. Safe administration exists from initialization;
   the deployer EOA never receives temporary administration. Record implementation and proxy addresses and receipts.
3. Verify sources, layout/size commitments and default disabled state. The Safe separately binds the reciprocal vault
   pair; use **proxy addresses everywhere**, never implementation addresses for balances, configuration or indexers.
4. Install reviewed dual-era backend/indexers with V2 disabled. Rehearse both stages and inspect every event and
   balance. **Stage A:** Safe `old.setYieldVault(stopper)` exits the real old protocol position, sets old protocol
   principal to zero and blocks new legacy deposits through the reverting stopper. ETH stays in the old manager; no
   funds enter V2 yet. Pause legacy yield-maintenance actions during this staging period. Pool rewards remain in the
   pool until cutover. Record the actual ETH received, zero live old claims, old adapter residue and every remaining old
   obligation.
5. **Stage B:** publish a manifest containing the exact block/hash, old manager/router BOLD and sBOLD token balances,
   router ETH balance, and four independent approved maxima (`maximumOldBold`, `maximumOldSBold`, `maximumRouterBold`,
   `maximumRouterEth`) in their native units. Zero remains the default. The Safe must explicitly approve nonzero caps as
   **unmigrated surplus**, not as converted or imported capital, and verify the constructor `CONFIGURATION_HASH`
   includes them. Never set broad speculative caps; if an amount exceeds its reviewed cap, abort, reconcile and approve
   a fresh handoff. Confirm zero live legacy claims, zero pending conversions, no active order, exact parked ETH,
   verified code identities and a complete Safe-batch gas simulation at the current `depositId`. Deploy that exact
   handoff against the known idle ETH and reviewed staging state. In one Safe transaction: new
   `armLegacyImport(handoff,knownETH,expiry,manifest)` → `handoff.assertPreMigration()` → old `setYieldVault(handoff)`
   (old principal is already zero) → old `depositPrincipalIntoYieldVault()` → new `setIntakeEnabled(true)` → pool
   `setYieldManager(newProxy)` → `handoff.assertPostMigration()`. Each inner operation is a CALL inside the verified
   standard MultiSend delegatecall. Import arming belongs **inside** this batch: a failed Stage B rolls arming back too.
   Unexpected donated ETH still causes an exact-amount abort; refresh the immutable handoff candidate, not the already
   deployed V2 manager, while its import remains unarmed. Verify 100% investment import, old protocol principal zero, no
   old live claims, exact new assigned ETH and separately disclosed old dust. Reconcile `ResidualSurplusObserved`
   against the manifest and actual post-batch old manager/router balances; none of these residual tokens or router ETH
   was transferred to V2. The old historical-ID scan is linear and is not a scalable future migration mechanism; if the
   complete batch approaches the Safe/block gas envelope, abort before Stage A and separately review a bounded or paged
   alternative. Stage B rollback does **not** undo the already executed Stage A exit; funds remain parked in the old
   manager.
6. Configure approved executor/manager/vault caps and report bounds through the Safe, then separately enable reviewed
   entries, harvest and execution. Operators spend only the named pending leg, collect bucket carry, convert it once,
   mint sBOLD with an independent canonical floor, and call existing pybSeba `topup` once. A failed route leaves
   classified inventory for retry; no failed transaction counts as a completed donation.

## Emergency procedure (same native token)

1. Safe pauses affected vault entry/harvest and relevant manager/executor operations. Native exits remain available when
   safe/canonically valued; a physical custody deficit blocks affected-leg ordinary operations to prevent a payout race.
2. Publish an initial manifest with chain/block/hash, proxy, every open ID/basis/lock, both bucket balances, surplus,
   actual custody and shortage. Safe calls affected vault `beginRecovery(initialManifestHash)`. This freezes new entry
   and ordinary redemption, snapshots liabilities and exports only accounted native tokens to the fixed Safe. No Yearn
   redemption, Curve/Uniswap swap, USD quote or rETH burn is required. Inspect actual transfer and snapshot events.
3. Treasury recovers/holds the **same native token**. `fundRecovery(bucket,tokens)` tags original returned backing,
   capped by exported quantity. `repairRecovery` is an irrevocable voluntary repair donation, not a refund entitlement.
   Only Safe `fundRefundableRecovery` explicitly tags refundable extra funding, after that bucket's entire original
   export has been returned. Never relabel exported principal/carry as refundable repair.
4. Publish final per-bucket budgets, funding, loss and classification. Normal
   `activateSettlement([supporter,protocol], finalManifestHash)` requires funding and canonical principal caps. If the
   canonical getter is unavailable, the Safe may use the distinctly observable `activateExceptionalSettlement` with
   publicly reconciled fixed native budgets. This trusted exception is not an oracle fallback or a treasury par
   guarantee.
5. Users call the same vault `withdraw(id,minTokens,deadline)` **after their original unlock**. Protocol claims settle
   via Safe `withdrawProtocol(basis,minTokens,deadline)` to treasury. Each payout is
   `floor(bucketBudget * claimBasis / snapshotBasis)`, independent of claim order. Already closed IDs cannot claim
   again. A total-loss zero budget needs explicit disclosure/minimum acceptance; never pay users directly while leaving
   positions open.
6. Until every liability closes, settlement reserves cannot be swept, increased for late claimants or confiscated after
   an arbitrary expiry. Then Safe calls `finalizeRecovery()`: rounding dust/returned carry become classified manager
   yield; only explicitly authenticated unused overfunding is refundable. Reconcile closed basis, paid tokens, native
   custody, event inventory and every ID independently.
7. `manager.recoverBuffers(manifest)` exports only its classified buffers, not leaf assets. It permanently retires
   intake and execution but intentionally leaves authenticated leaf callbacks available. A later terminal leaf-yield
   receipt can be exported once with a new reconciliation. Explicitly pause leaf entries when retiring the manager:
   manager recovery does not automatically pause independent leaves. Restore reward delivery only through a reviewed
   upgrade/migration.

Recovery cannot force a frozen token to transfer. Manager-buffer export is atomic across its classified assets; a token
freeze can require the trusted upgrade escape to recover other buffers. No upgrade can manufacture lost external assets.

## Rollback limits

Before Stage A, abort and leave the old live stack untouched. After Stage A, ETH stays in the old manager with legacy
intake stopped; aborting does not restore Beefy. A failed Stage B rolls back that batch, including import arming, but
not Stage A. After the handoff the old manager points to a zero-return adapter: **repointing the pool back is not a
working rollback**. Old ordinary deposits would revert. Native supporter positions cannot be silently moved or
rebalanced. Use the tested pause/recovery path, or obtain approval for a separately reviewed upgrade/migration; never
conceal a loss or duplicate a live claim during manual remediation.

## Security evidence boundaries

Independent peer review identified a real legacy-indexer handoff getter failure, a cached-hash coherence gap, and a
backend invocation-budget issue. Fixes and regressions are required in linked stack PRs. Slither and Aderyn ran locally;
their raw alerts are not automatically confirmed exploits. Slither's fixed-manager `transferFrom` and post-call
accounting alerts require checking immutable caller/recipient restrictions and reentrancy guards; protective exact-delta
checks are intentional. Dependency advisories and complete deep-audit findings must be reviewed before release. Do not
represent static-tool completion, 100% coverage or this internal review as a guarantee against exploits.
