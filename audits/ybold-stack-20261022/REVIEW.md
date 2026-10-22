# yBOLD stack review — 2026-10-22

Status: implementation/rehearsal review, **not production-release approval**. No mainnet writes, AWS release, hosted
subgraph publication, signing, fund movement or merge was performed. Unrelated rETH/backend/subgraph dirty worktrees
were preserved. Contract work continues the existing main-based yBOLD PR; companion repositories start at origin/main.

## Decisions

- The asset is ysyBOLD/st-yBOLD over yBOLD over BOLD. Keep deployed manager/pool bytecode unchanged.
- Standard OZ UUPS/ERC1967 proxy, initialized atomically and implementation locked. Separate routine governance from
  treasury Safe upgrade/recovery authority. At the inventory pin the treasury Safe is **3 of 7**, not the older 2 of 6.
- Recovery is implemented at launch. Transfer exact accounted shares without venue/oracle calls, freeze normal paths,
  fund ETH and finalize one uniformly rounded rate, then clear IDs/protocol liabilities through the existing manager.
- No fund-migration contract: old user withdrawals already completed. Treasury now owns real ysyBOLD, not ETH. Manager
  still has residual old protocol principal, which `setYieldVault` must successfully redeem before switching.

## Scope and audit method

Contracts: `YBoldYieldVault`, `YBoldConfigValidator`, interfaces and deployment/preflight/upgrade scripts; unchanged
manager/pool are integration context. Backend: expected-proxy/state/cadence guards and existing release compatibility.
Subgraph: per-vault units, permanent deposit records, dynamic recovery/upgrade mappings and release/replay
compatibility.

Official Pashov skill v4.1 was fetched at `eacfc09b365d2697b83355909d0300607e596ffc` (installed local copy was v3). Its
specialty/evidence checklists informed the review. The prescribed interactive/12-simultaneous-agent workflow could not
run unchanged under the four-slot harness; this is **not a claim of a completed unmodified 12-agent Pashov scan**.
Implementation lanes were independently cross-reviewed, with a separate read-only Daybreak Blue model review and local
static/invariant/fork checks. See final findings/evidence below. No tool or AI audit guarantees absence of exploits.

## Reproduction

Use Node 20, Yarn 1.22.22, Foundry 1.5.1 and Solidity 0.8.28, reviewed lockfile. Do not load signing keys.

```sh
yarn install --frozen-lockfile --ignore-scripts
forge build --sizes
forge test --match-path 'tests/YBoldYieldVault/**/*.t.sol'
forge test --match-path 'tests/YBoldYieldVault/invariant/**' -vv
yarn test:ybold:storage
forge coverage --match-path 'tests/YBoldYieldVault/**/*.t.sol' --no-match-path 'tests/YBoldYieldVault/invariant/**' --report summary --report lcov
```

With an operator-supplied **read-only** `MAINNET_RPC`:

```sh
YBOLD_SNAPSHOT_BLOCK=0x190840f node tools/ybold/mainnet-snapshot.mjs /tmp/ybold-mainnet-snapshot.json
forge test -vv
forge test --match-path tests/fork/YBoldMigrationFork.t.sol -vv
```

The first fork suite is current treasury-start evidence at 26,248,207. The older suite contains explicitly historical
old-unwind cases; neither a historical success nor injected capital is a current complete old migration proof. Storage
validation uses OpenZeppelin upgrades-core 1.46.0, previous PR storage baseline and append-only V2 fixture, including
ERC-7201 namespaces and an intentionally incompatible control. For later releases, freeze the actual deployed
predecessor instead of treating this review baseline as eternal.

## Current fork and cross-stack evidence

Inventory pin **26,248,207**, hash `0xf5e4c17803a895df4694de95ccfd727f0687c296ec04b0430b447527af8fb528`. See
[machine-readable inventory](mainnet-snapshot.json). IDs 1–9 are fully deleted. No active old user-position blocker was
observed. Treasury owns `156014003721394916792917` ysyBOLD base units and zero ETH in the queried inventory.

Two independent rehearsals:

- Foundry treasury-start: real shares → **71.037406571234590178 ETH**, real residual protocol exit and new proxy
  deposits; healthy withdrawals, external failure rollback/recovery, upgrade preservation, full/partial/total-loss
  settlement.
- Persistent Anvil + actual Safe `approveHash`/`execTransaction`, threshold **3/7 unchanged**: same initial real shares
  → **71.037440306013527291 ETH**. Manager selected the local proxy at block 26,248,247; protocol deposit/healthy
  withdrawal/ redeposit and new user IDs 10/11 succeeded. Small differences reflect locally mined transaction time/Yearn
  accounting.
- Persistent recovery: exact `158535073860022353594794` shares transferred to treasury and actually liquidated for
  **72.183781942993241034 ETH**. The chosen **80%-of-proceeds** commitment is a deliberate policy-loss fixture, not an
  observed 20% liquidation loss. Canonical rate `331149512040045`, committed ETH `57747025554394426249` wei; all
  user/protocol claims paid `57747025554394426248` wei, leaving one wei of committed claim-rounding dust.
- Backend actual state reader followed normal → paused → recovery and correctly refused automated new yield operations
  while frozen. Independent CoW/graduation paths remain intact. Graph Node 0.45.0 replay matched both block hashes, 19
  actual strategy events, native principal `174383544153950730337992`, user histories and deleted active IDs.
- Final Anvil block 26,248,319: manager protocol/adapter principal and adapter ETH zero; all claimed IDs deleted;
  excess/dust returned only after full settlement. No Graph indexing errors.

The persistent fixture used local impersonation and synthetic **gas/deployer** accounts only, not treasury investment
top-ups, token minting, oracle/venue mocks or Safe threshold overrides. Existing user locks were honored by local time
advance. Foundry failure tests and future oracle refreshes are explicitly injected. Prices/quotes are pinned evidence,
not current execution promises. Reusable harness/receipts live in the companion backend and indexer PRs.

## Coverage boundaries and release gates

Adapter/config-validator line/branch coverage is reported separately from scripts, mocks, unchanged manager/pool and the
whole stack. Backend's new state reader/local-write guard have 100% focused line/branch coverage; this is not
whole-backend coverage. Subgraph tests exercise all changed/new handlers, but Matchstick's raw whole-mapping coverage is
**37.1% (13/35 static non-inlined handlers)**; no 100% line/branch claim is made for the subgraph.

The actual Graph replay was short, starting immediately before local activation. It does not replace original-start-
block history, all validators, historical Beefy records or hosted endpoint catch-up. Full historical replay, target AWS
state-retention/configuration diff, verified governance execution route and fresh full-size Safe simulations remain
mandatory before Gate 2. Previously the contracts repo had no Actions workflows/runs/secrets; fork tests used local
`MAINNET_RPC`. That private endpoint was not uploaded. New PR CI runs offline unit/invariant/coverage/storage checks;
hosted fork testing is an optional manual `workflow_dispatch` job and is **not run, not passed** on PR events. If
explicitly dispatched without its RPC secret, it fails clearly. Current local fork evidence is separately published.

See [runbook](../../docs/YBOLD_MIGRATION_RUNBOOK.md) for exact calls, roles, funding/rate mathematics, abort criteria,
loss disclosure, unchanged locks and irreversible recovery/rollback limits. Final test counts, analyzer triage and
independent findings are recorded below after the final source freeze.

## Finding disposition

The initial independent Daybreak source review is preserved in [DAYBREAK-INITIAL.md](DAYBREAK-INITIAL.md); its line
references describe the pre-fix checkout and its source-only test limitations, not current verification results. It
found no proven Critical/High issue, two Medium findings and two Low findings. Fixes were independently reviewed. The
[final Daybreak recheck](DAYBREAK-RECHECK.md) confirms the accounted-yield and backend fixes and explicitly retains the
donation-only custody limitation, Medium independent-artifact approval gate and Low manager-callback limitation. It
reviewed production source blob `9da415cc02d5d49d980f4be3ab71c917ceb4eceb`. The later minimal manager-role-admin
hardening is separately regression-tested and independently peer-reviewed; do not treat the earlier model report as
having reviewed a later source hash.

| Finding                                            | Disposition and proof                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Donation blocks recovery (implementation review)   | Fixed: actual shares may exceed accounted shares; exact accounted custody transfer and surplus events/sweep tested. A real shortage still reverts.                                                                                                                                                                                                                                                       |
| M-01: zero-liability residual yield cannot recover | Accounted-yield case fixed: transfer tracked shares, snapshot0, immediately Settled/Completed; unit and live-fork regression. **Pure unsolicited donations with zero tracked shares remain upgrade-only**, as do other accidental core tokens; no user liability is involved. Do not call the entire custody limitation eliminated.                                                                      |
| M-02: preflight accepts incorrect configuration    | **Mitigated, Medium release-control gate remains.** Canonical governor/treasury, exact3/7 owners, empty modules/guard, proxy inventory/runtime, dependencies and defaults now have negative tests and actual CREATE2 dry-run. Operator-provided proxy/implementation/hash expectations are consistency checks, NOT independent authorization: Gate2 must independently approve exact artifacts/calldata. |
| L-01: skipped distribution repeatedly harvests     | Fixed in backend PR9: independently persisted confirmed-harvest cadence, legacy fallback frozen before distribution, true failures retry, frozen state stops harvest, native1e12 yield floor. 125 tests and exact-head hosted CI green.                                                                                                                                                                  |
| L-02: ETH-rejecting depositor prevents completion  | Confirmed **unchanged manager limitation**, not fixed by this release: its own ID remains claimable, final sweep waits; other users receive their rate. Regression and runbook disclosure. Manager recipient-credit redesign is out of scope and requires separate approval.                                                                                                                             |
| Stale indexed availability after upgrade           | Fixed: retain last numeric observation but invalidate availability for changed vault/matching active pool, without external implementation calls. Matchstick regression and independent re-review.                                                                                                                                                                                                       |

No new storage slot, struct ordering or inheritance was changed by the final recovery fixes. Treasury governance is
still trusted, and normal routes still deliberately fail closed on stale feeds/depeg/capacity. Recovery cannot insure
against external loss. Batched activation+first deposit has not been replayed through Graph Node: use separate
transactions until that exact sequence is verified. No blocker is hidden by the term “full E2E”.

Final least-privilege hardening makes `UPGRADER_ROLE`, not routine `ADMIN_ROLE`, administer `YIELDMANAGER_ROLE`. Routine
governance cannot self-grant a caller role and drain the proxy through `retrievePrincipal(msg.sender)`. Release guards
reject the old role-admin graph and a routine admin already holding the manager role. Existing deployed manager ADMIN
strategy-selection power remains trusted. The routine governor is an Aragon DAO, with a separately verified existing
single-EOA Admin-plugin shortcut and a 2-approval Multisig plugin; neither is the treasury's 3/7 Safe. Exact public
route/membership/settings reads are in the pinned inventory, and the runbook distinguishes both authority systems. A
local non-persistent Admin→DAO→adapter eth_call succeeded; full Aragon multisig proposal execution remains an explicit
release gate. Treasury can initiate adapter recovery directly without waiting on this routine-admin route.

## Final static analysis

Aderyn0.6.8 ingested the two final production files with solc0.8.28 and ran88 detectors:
[raw report](aderyn-final.json), one high pattern category and seven low categories. Slither0.10.4 was run directly with
the pinned solc0.8.28 (optimizer10000/Cancun), avoiding changing the user's global solc selection or racing test build
artifacts: [adapter](slither-final.json), [validator](slither-validator-final.json). Both JSON results have
`success:true`; Slither exit255 indicates findings, not a clean scan or compilation failure. No detectors were
suppressed.

- Reentrancy matches: initialized through the proxy constructor; implementation locked; stateless immutable validator
  uses view/static calls. Operational deposit/exit/recovery paths are role-gated and nonreentrant; actual share amounts
  must be read before accounting. No unprotected state-mutating callback was established. Recovery payouts update state
  before manager ETH send. Residual read-only getters do not authorize transfers.
- Strict-equality matches are intentional zero-output guards or liability-zero completion, not balance-equality gates.
  The vulnerable actual==tracked recovery equality was removed and has a donation regression.
- Chainlink `startedAt` is deliberately unused; roundId/answer/updatedAt/answeredInRound validity and freshness are
  checked. Timestamp dependency includes explicit oracle liveness and Yearn views; no same-pool spot oracle sets swap
  minima.
- Remaining style/compiler/naming notices: pinned compiler/pragma, mainnet Cancun PUSH0, literal readability,
  intentionally ignored OZ `_grantRole` return booleans and NatSpec-only interface import. Centralization is an explicit
  trusted-Safe design risk, not dismissed as absent. Validator Slither results are eight informational naming notices.

Automated pattern matches are not counted as proven exploits or silently called “zero findings”. Final deployment
size/layout/coverage output is in [TEST_RESULTS.md](TEST_RESULTS.md). Halmos, Echidna and Medusa campaigns were not run;
the actual stateful search is Foundry, not a claim of using unavailable engines.

## Review pull requests

- Contracts: [heroglyphs-seba#3](https://github.com/Archethect/heroglyphs-seba/pull/3).
- Backend: [hero_boost_backend#9](https://github.com/Archethect/hero_boost_backend/pull/9), reviewed head `8310ac1`.
- Subgraphs: [hero_boost_subgraphs#2](https://github.com/Archethect/hero_boost_subgraphs/pull/2), reviewed head
  `5bb15ed`.

Backend:125 tests, build, changed-source lint and offline CDK synth passed on GitHub. Subgraph:18 Matchstick tests,
portable guard tests, codegen/build/lint passed on GitHub. Neither proves AWS deployment-state equality or full
original- start-block history. Final contracts hosted CI/fork-secret availability must be checked on the exact pushed
head.
