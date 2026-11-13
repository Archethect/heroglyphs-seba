# Hoodi V1 → V2 rehearsal: cross-repository phase gate

Status: design/implementation in progress. This is **not** a deployment authorization. The existing Hoodi apxETH stack
and the funded chain-1 test stack are out of scope. The owner approved new, uniquely named **private** Hoodi V1 and
V2-candidate graphs in the existing Hero's Team Goldsky project; existing mainnet graphs, tags and endpoints must not be
changed. This shares project quota and access, but not graph names. The unmodified V1 backend always sends a Bearer
header, so its test-only Goldsky token must live in a dedicated Secrets Manager secret, never a URL or CDK template.
Local Graph Node replay remains the independent receipt-level check; do not use the retired Alchemy Subgraphs deployment
path or repoint an existing production graph.

## Stop-and-review phases

1. Build the isolated three-repository rehearsal and prove it locally on a Hoodi fork plus a fresh mainnet fork. Report
   test evidence and gaps; stop.
2. Independently audit the exact three-repository candidate, fix confirmed findings, rerun tests and review deployment
   manifests; report and stop.
3. Deploy the fresh V1 Hoodi stack, V1 backend artifact and isolated V1 Goldsky subgraph; reconcile live receipts and
   indexed state; report and stop.
4. Stage V2 contracts, V2-aware backend and dual-era Goldsky candidate without changing the pool pointer; reconcile and
   report; stop.
5. Execute Safe-approved Stage A and Stage B separately, verify exact accounting and complete the backend/graph consumer
   cutover; report and stop.
6. Exercise V2 operation and failure/recovery drills on the isolated stack, review results, then decide separately about
   any mainnet release.

No later phase starts merely because the prior phase passed its tests. The owner receives its evidence and explicitly
chooses whether to proceed.

Phase-3 Safe bootstrap is complete on **Hoodi only**. Factory transaction
`0x3ac6307b93523487a9d39c079801994e6363d445f13554483f6540279d31fdf6` succeeded in block 3,994,979
(`0x78d5413ab1becd78b37ca4a3a987a0d2ac17212f5137cd09dc4ec8e51f66066f`). Its input exactly matches the generated factory
calldata hash `0x00ab1f11351f212ae1b5276ed0389a56524f801efe807be09833214f7e4b08fb`. `ProxyCreation` emitted Safe
`0xAc52395a9D706696Cf36125A0664c0C6d2B06B7b`, runtime code hash
`0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c`, singleton
`0x41675C099F32341bf84BFc5382aF534df5C7461a`, version 1.4.1. Read-only post-checks found sole owner
`0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f`, threshold 1, no modules and zero guard. The Safe nonce after the V1
deployment batches was 5; it advanced to 7 during Phase-3 setup and oracle refresh.

The five **Hoodi-only public V1 contract batches** succeeded at blocks 3,995,123, 3,995,135, 3,995,162, 3,995,175 and
3,995,211. Each input matched the reviewed plan, emitted Safe `ExecutionSuccess`, advanced the Safe nonce once and left
all expected runtime hashes intact. The final batch verified Safe-only core administration, manager-only adapter/router
roles, pool/PYBSeba/manager pointers and zero supporter claims/principal/pending conversion. See the
[non-secret public V1 receipt manifest](HOODI_V1_PUBLIC_MANIFEST.json). This completes the **contracts deployment/wiring
substep only. Since then, Phase 3 completed its public financial lifecycle: the isolated V1 backend swept 2 Hoodi test
ETH (1 ETH into the mock Beefy adapter, 1 ETH through the mock EthFlow order), the test solver delivered 2,000 synthetic
BOLD, and the backend finalized 2,000 sBOLD into pybSeba. The private V1 Goldsky graph indexed those receipts and
balances. There were no supporter deposits or public validator/backpay runs. The Safe nonce is now **7**, not 5; see the
[Phase-4 V2 staging gate](HOODI_V2_STAGE_BATCHES.md) before preparing another transaction.

## Evidence boundary

- The five V1 source files (`YieldManager`, `SebaPool`, `PYBSeba`, `EUSDUSDCBeefyYieldVault`, `EthToBoldRouter`) have no
  diff between the contracts CoW branch and `origin/main`; the Hoodi clone must deploy those unchanged sources. This
  source comparison does not by itself prove the Hoodi instance has mainnet's balances or external integrations.
- Read-only mainnet check at block **26,384,998**: pool `0xe3B17b4533b339d3CBC26F57199d3fb937129894` still points to V1
  manager `0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269`, which still points to Beefy adapter
  `0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba`; manager `depositId` remains 9. The compiled deployed bytecode from this
  contracts branch matches the five live V1 runtimes—pool, manager, Beefy adapter, ETH-to-BOLD router and PYB—after
  masking constructor immutable slots. This is block-pinned source parity, not a complete fresh mainnet asset/claim
  inventory.
- A later read-only mainnet snapshot at block **26,385,111** found V1 manager `depositId=9` and
  `deposits(1..9).amount=0`, so no live V1 supporter claim was visible at that block. `USER_LOCK_SECS=2,592,000` (30
  days). Recheck every ID immediately before any real mainnet handoff; this snapshot is not a standing authorization or
  a substitute for the claim-veto fork test.
- Fresh mainnet fork at block **26,385,147** passed a fault-injected live-claim veto after Stage A. A separate full V1
  Safe Stage A/B fork at block **26,385,149** imported **1.489774050306692692 ETH** from the real Beefy exit; its V2 CoW
  solver inventory was synthetic. These are local fork transactions, not mainnet transactions or proof of a live order
  fill.
- Public Hoodi: unchanged Seba V1 and V2 business logic with test-only external dependencies; real Hoodi Rocket Pool
  where compatible. Mocks do not prove mainnet Beefy, Yearn, sBOLD, liquidity, or live CoW solver execution. The
  unchanged V1 backend may use a dedicated, test-only HTTPS quote stub approved for this rehearsal; its response is
  synthetic and the mock EthFlow fill remains a separate, explicit test-solver action.
- The two fixed-price Hoodi V1 oracle mocks expose only a **Safe-authorized** report-time refresh and reject future
  timestamps. Before any V1 Beefy-adapter entry or exit—including Stage A—the test Safe must refresh and verify both
  report times at the execution block: ETH/USD must be at most one hour old and USDC/USD at most 23 hours old. A stale
  feed or unavailable Safe is an abort, not a reason to bypass the legacy adapter's freshness checks. These timestamps
  only keep a synthetic test price usable; they do not establish real USD market value.
- Fresh mainnet fork: real existing V1 state and external integrations, with explicitly labelled local signer
  impersonation and synthetic solver funding.
- Only a separately approved live order can prove orderbook acceptance/fill.

## Versioned sequence and required proof

| Gate         | Contracts                                                                                                    | Backend                                                                               | Subgraph                                                                                                                         | Required cross-check                                                                                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V1 baseline  | Fresh mainnet-shaped SebaPool, PYBSeba, YieldManager, Beefy adapter and router; test dependencies identified | Separate Hoodi V1 stack with isolated state and a disabled-by-default schedule        | New V1 namespace from actual V1 deployment blocks                                                                                | Schema-defined V1 reward, principal and validator entities reconcile with chain at one block hash; router and external harvester activity reconcile from receipts, not graph entities |
| V2 staged    | Disabled V2 proxies/executor/CoW module; no pool pointer change                                              | V2-aware build still selects legacy from the real pool pointer; V2 execution disabled | Dual-era candidate replays V1 history and indexes V2 creation/initialization from actual blocks                                  | Old claims/history and new empty V2 ledgers match; no V2 action is misclassified as V1 income                                                                                         |
| Stage A      | Exact old protocol exit into old manager ETH; legacy intake stopper                                          | Pause only legacy yield maintenance; preserve validator/backpay checkpoints           | Preserve indexed V1 history; validate handoff transition from onchain receipt because no handoff event is in the V1 graph schema | Zero live V1 supporter claims, no active order, exact old principal/ETH and residual inventory; old pool pointer unchanged                                                            |
| Stage B      | Safe-approved exact handoff and pool pointer switch in one atomic batch                                      | Era changes only after verified pointer/implementations; no double automation         | Index V1 retirement and V2 import, then catch up before consumer switch                                                          | Exact imported ETH, no second 50/50 haircut, old manager ETH zero, V2 source buckets correct, same-block receipts/Graph balances agree                                                |
| V2 operation | Both protocol legs, supporter deposits/exits, rewards, CoW mock fill/refund, pause and recovery              | Bounded actions, restart/reorg-safe order reconciliation and blocked-path isolation   | Separate reward/protocol and leg/bucket ledgers, order lifecycle and completed donations                                         | Custody equals classified obligations and surplus; no double claim or donation; old V1 history remains queryable                                                                      |

The unchanged V1 supporter lock is 30 days. Prompt Hoodi Stage B uses protocol capital with zero live V1 supporter
claims; claim closure, lock expiry, and a claim-veto case must pass on the fresh mainnet fork. Public Hoodi supporter
positions created after V2 launch retain their normal lock.

## Non-negotiable acceptance checks

1. Commit hashes, chain ID 560048, all code hashes, verified identities, transaction receipts, deployment blocks and
   hashes are pinned in a public non-secret manifest. Secrets, RPC URLs and keys stay out of Git.
2. The 1-of-1 Hoodi Safe is owned by the previously used Hoodi admin EOA; its owner, threshold, modules and guard are
   verified before either V1 or V2 receives administration. The isolated public V1 contracts receive the Safe as
   `ADMIN_ROLE` at construction, so the EOA never holds their V1 admin role; it retains only bounded V1
   automator/mock-solver functions. See [the five-batch signing and receipt gate](HOODI_V1_SAFE_BATCHES.md). This
   differs from mainnet's retained Aragon role overlap and is testnet governance, not production policy. Test the
   direct-EOA admin failure and Safe success.
3. Existing Hoodi onchain contracts and holders are not modified. The old Hoodi **testnet** AWS/graph resources may be
   retired or replaced only after an inventory snapshot and a verified isolated successor; the chain-1/production stack
   is never targeted. No `cdk deploy --all`. The public Hoodi rehearsal invokes only the financial-maintenance path;
   validator graduation/backpay stay on local/fork regression tests. Do not invoke the complete legacy poller against
   stale NFT/Gnosis graph inputs.
4. Full V1 backend and graph behavior works before migration. V2-aware backend and dual-era graph must also work while
   the pool still points at V1.
5. Faults include no fill, expiry, fill/cancel race, stale or unavailable dependencies, restart, reorg, donor dust,
   wrong pointer, duplicate receipts, unauthorized calls, underfunding and recovery. Failures leave identifiable
   inventory and a documented authorized exit.
6. New code passes TDD regressions, required line/branch coverage, lint/type checks, relevant fuzz/invariants and
   current fork tests. An independent cross-stack audit and fix re-review cover the exact commits to be deployed.
7. Before any Hoodi transaction, the lead presents the exact manifest, signer, amount, calldata, gas estimate and abort
   conditions for review. A failing gate stops the sequence; it does not trigger an improvised top-up or bypass.

The read-only `tools/hoodi-public-safe-plan.mjs <ignored-local-env-file>` generated the completed Safe-factory
transaction. The read-only `tools/hoodi-public-v1-next.mjs <ignored-local-env-file> <batch-index-0..4>` now produces one
separately simulated V1 Safe batch at a time. Both have no signer or send path. A dirty source is marked
`executionReady: false`; re-run from a clean pinned source and recheck the live head immediately before signing. The
loopback-only Anvil proof sends transactions **only** to its local fork, never Hoodi. For the factory UI, copy
`transaction.factoryInputs.initializer` directly from generated JSON. It must be 356 bytes; compare
`transaction.dataHash` with the wallet's full calldata when available. Do not manually transcribe long hex from chat.
The failed Hoodi factory transaction `0x53921503cce3f97b4cf1f189f24974c5f784a0490cbbd45228c323c5e808034f` used a
362-byte initializer (six extra zero bytes), reverted without deploying a Safe, and consumed the EOA nonce. Replay at
the parent block confirms the submitted call reverts and the exact generated calldata returns the expected Safe address.
A retry requires a fresh nonce/gas preflight, not an unchanged old transaction.

## CROPS record for this rehearsal

- Chosen default: separate Hoodi stack plus fresh mainnet fork, retaining old deployments and full event history.
- Censorship/exit: the test Safe can pause or upgrade V2, and the mock CoW service can withhold fills. Native exits and
  Safe recovery are tested; mock fills never stand in for live solver availability.
- Open/free: release manifests, source, tests and self-hosted graph procedure must be reproducible from pinned commits;
  repository licenses are checked before claiming the whole stack is freely forkable.
- Privacy: public deposits, validator and order events expose addresses and amounts; no test secrets or personal
  identifiers go into manifests/logs.
- Security: the 1-of-1 Safe is an accepted **testnet-only** single-key compromise. Mainnet remains governed by its
  existing threshold Safe and overlapping Aragon authority, which the fork rehearsal must model.
