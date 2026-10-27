# V2 changes across the stack

Review branches start from independent `origin/main` snapshots. This is a new native-token product, not a merge of the
unrelated rETH branch or the former ETH-only yBOLD adapter. No production deployment, fund movement or merge is
authorized.

## Contracts — `heroglyphs-seba`

Base: `0d2c922d4df05c38d934bc481e020ef7dd79dab0`. Existing deployed production source is unchanged. Its runtime parity,
live authority overlap and deployment-state limitations are recorded in
[baseline evidence](V2_BASELINE_AND_REHEARSAL.md).

| Files                                                                                                    | What changed and why                                                                                                                                                                                                                                                                      |
| -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/v2/YieldManagerV2.sol`, `src/interfaces/v2/IYieldManagerV2.sol`                                     | New pool-compatible `depositFunds()` coordinator. Retains the fresh-reward 50/50 rule, then assigns invested ETH to independent legs. Tracks classified reward/carry inventory and completed donations; imports old protocol ETH without another reward split.                            |
| `src/v2/NativeSupporterVault.sol`, `src/interfaces/v2/IV2SupporterVault.sol`                             | Public, owner-only native positions with separate SUPPORTER/PROTOCOL backing, original 30-day locks, recognized-yield collection, pro-rata impaired exits and terminal fully funded native-token recovery.                                                                                |
| `src/v2/RethSupporterVault.sol`, `src/interfaces/v2/IRethSupporterVault.sol`                             | rETH in/out against ETH principal basis, canonical Rocket Pool rate/report checks. Native withdrawal does not require rETH burn liquidity or an ETH queue.                                                                                                                                |
| `src/v2/YsyBoldSupporterVault.sol`, `src/interfaces/v2/IYsyBoldSupporterVault.sol`                       | ysyBOLD in/out against yBOLD principal basis. Matches deployed Yearn accounting; native withdrawal does not require Yearn redemption or Curve liquidity.                                                                                                                                  |
| `src/v2/SebaV2Executor.sol`, `src/interfaces/v2/IV2Executor.sol`, `src/vendor/v2/IExecutorProtocols.sol` | Fixed routes/recipients, independent floors, exact consumption/deltas and bounded caps. Backend cannot pass arbitrary calls or weaken the approved onchain minimum.                                                                                                                       |
| `src/v2/LegacyIntakeStopper.sol`                                                                         | Stateless intermediate adapter rejects legacy intake while Stage A parks the real old exit proceeds in the old manager.                                                                                                                                                                   |
| `src/v2/LegacyProtocolPrincipalHandoff.sol`, matching interface                                          | Exact, one-shot Stage B import and executable Safe assertions. Four immutable Safe-approved caps permit only bounded, disclosed unmigrated legacy/router surplus; above-cap drift aborts. The old manager forwards ETH but records zero new adapter principal, avoiding duplicate claims. |
| `script/v2/DeploySebaV2.s.sol`                                                                           | Three standard ERC1967/UUPS proxies, locked implementations, actual Safe authority from initialization, no temporary EOA administration. All operations disabled; Safe binding is a separate payload.                                                                                     |
| `storage-layout/v2`, `tools/v2/check-artifacts.cjs`                                                      | Semantic layout snapshots, enum ordering, positive/corrupted-slot controls and real optimized EVM size limits. All consumers use proxy addresses.                                                                                                                                         |
| `tools/v2/preflight*`                                                                                    | Read-only pinned runtime/security/graph/default-state checks and tests. It is not a substitute for full legacy custody/order reconciliation.                                                                                                                                              |
| `tests/v2`, `tools/v2/check-coverage.cjs`, workflow                                                      | Per-method branching tests, fuzz/handlers, real protocol forks, actual 3-of-7 Safe migration, loss/recovery/upgrade reconciliation. CI rejects missing new-source coverage.                                                                                                               |
| Build manifests/remappings and `tests/Base.t.sol`                                                        | Portable pinned dependencies, storage metadata, modern Solidity lint and one Linux case-sensitive test-import fix. No legacy economic refactor.                                                                                                                                           |

UUPS authority can ultimately move all proxy assets. Aragon retains its separate legacy powers over pool/reward
integration. Neither independent ledgers nor native exits guarantee repayment after external protocol/token loss. See
[implementation, procedures and verification boundaries](V2_IMPLEMENTATION_AND_RELEASE.md).

## Backend — `hero_boost_backend`

Base: `3955839c029c8f16b902aa1a9e5e157719b43f74`. No new database, queue, broad service rewrite or production state
reset. Review: [backend PR #12](https://github.com/Archethect/hero_boost_backend/pull/12).

| Files/components                                                                 | What changed and why                                                                                                                                                                                                                                                                                                       |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `yield-v2-config.ts`, `yield-v2-identity.ts`                                     | Strict reviewed address/implementation identities, reciprocal bindings and actual pool-pointer era; fail closed on drift or reorg. No invented V2 production addresses.                                                                                                                                                    |
| `yield-v2-client.ts`, new ABI JSON                                               | Typed routine operations only. No upgrade, recovery, allocation change or principal-withdrawal methods in the operator client.                                                                                                                                                                                             |
| `yield-v2-policy.ts`, `yield-v2-quotes.ts`                                       | Explicit unapproved-by-default thresholds and conservative independent minima in each asset's real units. No summing ETH/yBOLD principal or spot-price fallback.                                                                                                                                                           |
| `yield-v2-maintenance.ts`, `yield-v2-runtime.ts`, `yield-v2.ts`                  | Four carry sources and two assigned protocol legs; exact simulation/estimate/send/confirmed-receipt flow. Bound receipt waits and invocation budget; unresolved pending nonce blocks further sends. Even with V2 config absent, verify the pool still points at legacy before allowing standalone legacy rETH maintenance. |
| Existing validator-graduator handler/helpers                                     | Era-gate old `activateYieldFlow`, suppress unrelated legacy rETH maintenance after cutover, preserve graduation/backpay processing and S3 checkpoints.                                                                                                                                                                     |
| CDK constructs and optional legacy pause                                         | Explicit configuration only. Default offchain V2 flag false; Stage A maintenance pause does not erase epochs or pause unrelated validator duties. No cloud rollout performed.                                                                                                                                              |
| `scripts/v2-local.ts`, tests/workflow                                            | Loopback-only retained-fork execution and reproducible targeted coverage. Simulated sends are not completed donation evidence.                                                                                                                                                                                             |
| `docs/YIELD_MANAGER_V2_RELEASE.md`, `docs/YIELD_MANAGER_V2_FRONTEND_HANDOVER.md` | Exact configuration, operating/release gates and out-of-scope frontend implementation contract.                                                                                                                                                                                                                            |

The legacy manager address remains configured separately; replacing its old ABI target with V2 is incorrect. New
optional persisted statistics preserve existing and unknown fields. This work does not attest the currently deployed AWS
Node.js patch level or authorize infrastructure changes.

## Subgraphs — `hero_boost_subgraphs`

Base: `cd4c92d40cda077d4ba8335ab4b66882cee99863`. Only the Ethereum Seba graph changes; unrelated networks remain
untouched. Review: [subgraph PR #3](https://github.com/Archethect/hero_boost_subgraphs/pull/3).

| Files/components                                        | What changed and why                                                                                                                                                                                                                                                                |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `seba-ethereum/schema.graphql`                          | Namespaced native IDs, permanent legacy history, separate bucket units, inventories and recovery state. Native custody is not automatically principal, and imported capital is not yield.                                                                                           |
| `src/nativeSupporterVault.ts`                           | Event-driven owner/lock/basis/closed state; fixed settlement budgets, paid/closed counters, irrevocable repairs versus authenticated refundable funding.                                                                                                                            |
| `src/yieldManagerV2.ts`                                 | Assigned ETH, four carry sources, conversions/imports and completed donations. Exactly one `DonationCompleted` counts income; PYB top-up does not duplicate it.                                                                                                                     |
| Existing `src/yieldManager.ts`                          | No nonexistent `principalValue()` call on the stopper/handoff. Reconcile exact deposited basis per manager/vault from events while preserving legacy active API and permanent closed history.                                                                                       |
| Existing `src/sebaPool.ts`                              | Retain manager transitions; do not discover V2 only at cutover and miss its earlier initialization/deposit history.                                                                                                                                                                 |
| ABIs, templates, `tools/v2-manifest.mjs`                | Actual deployment-block/transaction/hash evidence before adding sources. Normal generation retains original full-history sources/start blocks.                                                                                                                                      |
| `tools/local-v2-replay`, tests/workflow                 | Isolated Graph Node replay of actual receipts and RPC inventories; the patched handoff tuple includes four zero-default residual caps and requires an exact `ResidualSurplusObserved` Stage-B receipt. Explicit delta baseline is not a full historical backfill or hosted release. |
| `docs/YIELD_MANAGER_V2_INDEXING.md`, `docs/v2-evidence` | Schema meanings, receipt-level evidence, interventions, limits and historical catch-up release gate.                                                                                                                                                                                |

## Cross-repository fixes found during review

The focused peer review found and corrected a legacy graph getter failure at retirement, a cached canonical-hash check,
unbounded backend receipt waiting, and a missing-config legacy-maintenance era gap. Regression tests prove these paths.
The full three-pass contract audit is separate; its findings, fixes and residual leads must remain linked to exact
revisions.

## Required before rollout

Finish security review and revalidation; approve numeric limits; complete full historical graph catch-up; have the
frontend team implement and test its handover; approve exact environments, addresses and Safe transactions. The existing
funded mainnet test stack and stale Hoodi environment are not disposable. Use an isolated persistent mainnet fork first.
