# yBOLD stack rollout and treasury recovery

Status: review only. **No production deployment, publication, fund movement or merge is authorized.** All addresses
below are Ethereum mainnet. A local Anvil transaction is rehearsal, not production execution.

## Current starting point

Snapshot: block **26,248,207**, hash `0xf5e4c17803a895df4694de95ccfd727f0687c296ec04b0430b447527af8fb528`, 2026-10-22
12:38:59 UTC. Refresh every balance, role, owner, pending intent, code hash and quote immediately before signing.

| Component                                 | Verified address / state at snapshot                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Treasury / upgrade and recovery authority | `0x888D768764A2E304215247F0bA3457cCb0f0ab4f`; Safe **3 of 7**                                     |
| Routine adapter admin                     | `0xf83b11b09EEc073ACE4481b2F4c8357e156714b3`; existing governance contract, not the treasury Safe |
| YieldManager (unchanged)                  | `0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269`                                                      |
| SebaPool (unchanged)                      | `0xe3B17b4533b339d3CBC26F57199d3fb937129894`                                                      |
| Old adapter                               | `0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba`; still manager's active vault                        |
| yBOLD                                     | `0x9F4330700a36B29952869fac9b33f45EEdd8A3d8`                                                      |
| st-yBOLD, onchain symbol **ysyBOLD**      | `0x23346B04a7f55b8760E5860AA5A77383D63491cD`                                                      |
| Treasury capital in this rehearsal        | `156014003721394916792917` ysyBOLD base units; treasury ETH **0**                                 |
| Old user deposit IDs 1–9                  | Fully deleted; do not withdraw them again                                                         |
| Manager's residual old protocol principal | `3033332133271012792310` **old native units, not ETH**                                            |
| Pending conversion / active CoW UID       | zero / zero; yield flow active                                                                    |

This is a **treasury-start rollout**, not a new migration of old user IDs. The earlier ID-4 liquidity blocker is
historical, not an active user-position blocker at this snapshot. Switching vaults must still exit the residual protocol
principal through the old adapter. A successful historical fork is not evidence of a current exit. The inventory covers
the explicitly queried assets, not every possible token held by treasury.

## Authority and units

Use a standard OpenZeppelin ERC1967Proxy with UUPS logic. Atomic initialization and a locked implementation prevent
initializer takeover. Self-administered `UPGRADER_ROLE` belongs to the treasury Safe; it also administers
`RECOVERY_ROLE` and manager-role rotation. Routine admin cannot grant itself upgrade or payout-caller authority. Do not
configure an EOA or give routine operators upgrade/recovery powers. Treasury already holds manager ADMIN independently
of the new adapter.

**Upgrade authority is fully trusted and can ultimately move every proxy asset**, despite today's core-token rescue
restriction. Recovery is trusted custody plus funded settlement, not insurance against Yearn/BOLD losses. The proxy
address, never implementation address, belongs in YieldManager, backend and release inventory.

The routine admin is the **Aragon DAO** above (implementation `0x58c1f7bc62bb63fb137bc8f6d8ea6321a0501d29`). At the pin,
its Admin plugin `0xef639bdd87805e811b3c5d3e308d3300561cb4d6` and Multisig plugin
`0x5373e070a37a51a400c98df4087753ecdd98f57d` both have DAO EXECUTE permission and target the DAO using Call. The
Multisig reports onlyListed=true/minApprovals=2; this is **not** the treasury's 3/7 Safe threshold. The existing Admin
shortcut authorizes EOA `0x5ebaaa3e84f9595fbf787a71c3caad97d370bc28`; treasury is not its member and cannot call DAO
execute directly. This existing single-admin shortcut is an explicit governance trust risk, not a multisig guarantee.
For an approved routine action, that authorized admin can call the Admin plugin's
`executeProposal(bytes metadata,(address to,uint256 value,bytes data)[] actions,uint256 allowFailureMap)` with metadata
`0x`, one action `(proxy,0,abi.encodeCall(targetFunction,args))`, and allowFailureMap `0`. Alternatively use the
existing Aragon proposal UI and actual approvers/execution window. Refresh membership/settings and approve the chosen
route. A non-persistent local eth_call through Admin→DAO→proxy `setEmergencyMode(true)` succeeded. The full Aragon
multisig proposal/approval workflow has not been rehearsed. Treasury may call adapter `initiateRecovery()` directly
without waiting for routine pause: recovery itself freezes atomically. Treasury can also call manager ADMIN paths
directly because it already holds that role. Existing DAO manager-admin strategy-selection power remains economically
trusted.

Adapter/manager user `principalValue` is **yBOLD assets**; adapter `principalShares` is **ysyBOLD shares**. Old adapter
values use a different denomination. Never sum old and new native principal or label either as ETH.
`deposits(id).vaultAtDeposit` remains authoritative after a switch. New user deposits retain the manager's **30-day
lock**.

## Gate 1 — evidence before proposing production changes

1. Pin the three reviewed repository commits, dependency locks and current contract/compiler artifacts. Run the commands
   in `audits/ybold-stack-20261022/REVIEW.md`. Require passing tests, storage validation and independent review.
2. Refresh `tools/ybold/mainnet-snapshot.mjs` with `MAINNET_RPC`; retain block/hash and owner list. Verify both
   governance execution route and Safe owners/threshold/modules/guard against the approved inventory. Threshold/count
   alone do not prove owner identities. No threshold or storage overrides are allowed in execution simulations.
3. Simulate the actual treasury Safe operation and residual old protocol exit at a fresh block. Quote the entire
   treasury liquidation and new entry sizes, not a one-ETH sample. Rehearse a small tranche before the approved
   remainder.
4. Run backend/indexer integration against local Anvil. Complete a historical subgraph replay from original start
   blocks, compare legacy IDs and aggregates with the old deployment, and require no indexing errors. The short local
   replay does **not** replace this historical replay gate.
5. Settle/cancel outstanding CoW intents using the existing release process. Require pending conversion and active UID
   zero; stop keeper jobs during the switch. Preserve databases, buckets, existing schedules and chain history.

Abort for active old user claims, changed owners/roles/code, unexplained balances, pending intents, stale/invalid
oracles, depeg/insufficient capacity, failed old protocol exit, failed indexing/reconciliation, or any unresolved
material finding. Do not raise tolerances, fabricate funding or pick an older successful block to bypass a failed gate.

## Gate 2 — explicit human release approval

The team must approve the exact three commits, networks/accounts, role graph, Safe signers, implementation and proxy
addresses/code hashes, calldata and ETH values, fresh simulation block, slippage/loss ceilings, operational window,
monitoring/rollback limits and any disclosed residual gaps. Until then **dry runs only**. No command below authorizes
broadcasting, verifying/publishing a production deployment, CDK deployment or subgraph publication.

## Normal rollout, after Gate 2 only

1. **Deployment operator:** fill `YBOLD_EXPECTED_DEPLOYER`, `YBOLD_ADMIN`, `YBOLD_UPGRADE_AUTHORITY`,
   `YBOLD_RECOVERY_TREASURY`, `YBOLD_VERSION_SALT`, `YBOLD_EXPECTED_SAFE_THRESHOLD`, `YBOLD_EXPECTED_SAFE_OWNERS`. At
   the snapshot, authorities are the governance contract / treasury / treasury and Safe values are 3 / 7. Run
   `forge script script/DeployYBoldYieldVault.s.sol:DeployYBoldYieldVault --rpc-url "$MAINNET_RPC" -vvvv` **without
   `--broadcast`** first. The script has no default mnemonic/signer fallback. Review CREATE2 predictions and
   constructor/initializer bytes before the separately authorized deployment process. Verify validator, implementation
   and proxy sources; record Solidity 0.8.28, Cancun, optimizer 10,000 runs and the actual artifact settings/constructor
   args.
2. **Independent checker:** read the EIP-1967 slot `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
   on the proxy; match implementation and code hash. Match validator immutability, UUPS UUID, locked direct
   initialization, all integration addresses/decimals/asset graph, role members/admins and initial zero liability/Normal
   state. Do not point anything at the implementation.
3. **Backend release owner:** follow `hero_boost_backend/docs/YBOLD_BACKEND_EVIDENCE.md`; use the existing release path,
   reviewed CDK diff and correct environment. Configure expected **proxy** for the target environment only. A mismatch
   deliberately blocks yield operations while the manager still references Beefy; graduation and CoW reconciliation
   remain independent. Never reuse mainnet addresses in Hoodi configuration.
4. **Indexer release owner:** follow `hero_boost_subgraphs/docs/YBOLD_INDEXING_RUNBOOK.md`. Publish only after replay
   evidence is approved, retain original history/start blocks, validate schema/API consumers before switching endpoints.
   Initial proxy state must be verified from the deployment artifact/chain; dynamic templates cannot see earlier events.
5. **Manager ADMIN via the approved governance/Safe route:** run read-only
   `forge script script/YBoldMigrationPreflight.s.sol:YBoldMigrationPreflight --rpc-url "$MAINNET_RPC" -vvvv`. Set
   `YBOLD_MIGRATION_ADMIN`, `YBOLD_EXPECTED_DEPOSIT_ID`, `YBOLD_MAX_DEPOSIT_SCAN`, `YBOLD_EXPECTED_OLD_PROTOCOL_VALUE`,
   `YBOLD_EXPECTED_TREASURY_ETH`, `YBOLD_EXPECTED_TREASURY_SHARES`, `YBOLD_VAULT`, `YBOLD_EXPECTED_PROXY` (from the
   reviewed deployment prediction), `YBOLD_EXPECTED_IMPLEMENTATION`, `YBOLD_EXPECTED_IMPLEMENTATION_CODEHASH`,
   `YBOLD_UPGRADE_AUTHORITY`, `YBOLD_RECOVERY_TREASURY`, `YBOLD_MAX_OLD_SHARE_DUST`, `YBOLD_MAX_OLD_VALUE_DUST`. Use
   current reviewed values, not blindly this snapshot's. Local admin impersonation tests authority mechanics, not the
   production governance contract's actual execution/signing route; rehearse that route separately.
6. Call manager **`setYieldVault(proxy)`**, value **0**. This atomically redeems old **protocol** principal into manager
   ETH before setting the proxy; failure reverts the switch. Then call **`depositPrincipalIntoYieldVault()`**, value
   **0**, only if manager's available ETH is nonzero. This reinvests manager idle principal; it does not invest treasury
   assets. Keep activation and the first new deposit in separate transactions for this release: the actual Graph replay
   proves that sequence, not dynamic-template capture of the first deposit in the same Safe multisend.
7. **Treasury Safe:** convert its ysyBOLD externally to ETH using independently reviewed fresh quotes, redeem limits and
   minimums. The reproducible fork uses ysyBOLD→yBOLD→BOLD→USDC→WETH→ETH. Approval/redeem/swap/unwrap can be a Safe
   batch; the fixture's calldata is evidence, **not reusable production calldata**. Fresh minima/deadlines and gas are
   mandatory. Do not use an unreviewed zap or arbitrary approval spender. Preserve a gas/operational reserve as
   approved.
8. **Treasury depositor:** call manager **`depositFunds()`**, with the approved tranche as ETH value. No arguments. It
   creates a fresh ID owned by the Safe with a fresh 30-day lock. Repeat only after the first tranche reconciles.
9. Re-run preflight with updated expected ID, active proxy and old dust caps. At the pin, residual old dust after switch
   is **121 old shares / 150 old value base units**; verify actual values rather than relaxing caps arbitrarily. Require
   adapter liability = manager protocol liability + sum of active IDs belonging to this proxy, and actual ysyBOLD >=
   tracked shares. Verify ETH, all approvals, emitted amounts and backend/indexer data at the same block.
10. Resume keeper on the approved existing cadence. Monitor stale feeds, peg/capacity, claimable yield, successful
    harvesting/CoW completion, role changes, pauses, upgrades and custody. Do not advance last-executed timestamps for
    skipped/failed jobs. Check yield economics regularly; no quarterly-only safety review.

## Emergency procedure

1. **Routine admin:** `pause()` and optionally `setEmergencyMode(true)` on the **proxy**, value 0. Deposits/yield claims
   stop; normal principal exits still work if venues/oracles permit. Do not silently widen loss/slippage limits.
2. Reconcile at one block: manager protocol principal, every active ID pointing at this proxy, adapter principal,
   tracked/actual ysyBOLD, ETH and approvals. Sum of ID+protocol liability must match adapter liability. Record
   donations separately. A genuine share shortfall aborts custody transfer and requires investigation.
3. **Treasury Safe, RECOVERY_ROLE:** call **`initiateRecovery()`**, value 0, once. This freezes deposits, yield claims
   and ordinary principal redemption; snapshots remaining liability; sets tracked shares to zero; transfers **exact
   accounted ysyBOLD shares** to treasury with no Yearn redemption, oracle or swap. Surplus donated shares remain on the
   proxy and cannot block recovery. Reconcile `RecoverySharesReconciled` and `RecoveryInitiated` with both custody
   balances. If all principal was already withdrawn but tracked yield shares remain, the same call transfers those
   shares and immediately completes recovery with a zero-liability snapshot; no funding or payout activation is then
   needed.
4. **Treasury:** liquidate recovered shares through separately approved venues, potentially over time. Loss is possible;
   custody transfer alone neither recovers ETH nor guarantees par. Never pay depositors directly while their IDs remain
   claimable. Keep recovered-asset proceeds and any approved treasury subsidy separately documented.
5. Agree the **final aggregate ETH settlement budget S** after liquidation; disclose loss/subsidy and the uniform rate.
   The liability L is in yBOLD base units. `rate=floor(S*1e18/L)`; each claim v receives `floor(v*rate/1e18)` wei. Rate
   is ETH per native principal, **not** an ETH-principal repayment ratio. Order cannot favor early claimants beyond
   floor dust.
6. **Treasury Safe:** call **`fundRecovery()`** on proxy with ETH value F > 0, no arguments. Only fixed treasury may
   fund; repeat funding before activation if needed. Then call **`activateRecoverySettlement(S)`**, value 0, only with S
   <= F and actual balance. Funding+activation can be one fully simulated Safe batch. Activation is one-time and final:
   no top-ups or rate changes afterward. A separately approved total-loss decision may activate **S=0** without fake
   funding; all IDs still settle through the manager for zero ETH. Any nonzero S rounding the rate to zero is rejected.
7. **Original depositors:** after their existing unlock, call manager **`retrieveFunds(id)`**, value 0. Manager calls
   proxy, receives settlement ETH, deletes the ID and pays the depositor. Repeat/double claims fail. No direct user
   payout bypass. **Manager ADMIN:** `retrievePrincipalFromYieldVault()` or `setYieldVault(reviewedReplacement)` settles
   protocol principal at the same rate and clears manager protocol accounting. New strategy activation does not move old
   user IDs.
8. Reconcile `principalSettled==principalSnapshot`, adapter principal 0, all corresponding user IDs deleted, manager
   protocol cleared, ETH paid equal sum of per-claim floor payments, and state **Settled**. Only then **Treasury Safe**
   may call **`sweepRecoveryExcess()`**, value 0, to retrieve rounding dust, uncommitted ETH and donated surplus shares.

An existing manager limitation remains: a depositor contract that rejects ETH callbacks (even zero-value callbacks)
cannot withdraw its own ID. Other claimants still settle, but the final completion/excess sweep waits on that ID. Do not
claim an unconditional forced-completion guarantee or directly pay it twice; resolve through separately reviewed
governance/user coordination. Changing the deployed manager is outside this release.

Recovery is already implemented in the initial release; an upgrade is not required to use it. For an unforeseen logic
flaw, independently audit a new implementation, run `yarn test:ybold:storage` against the **actual deployed
predecessor**, review all ERC-7201/ordinary storage, preserve claims and rehearse upgrade+recovery on a fresh fork.
Read-only `script/UpgradeYBoldYieldVault.s.sol` checks current/next hashes, UUID and Safe role and prints
`upgradeToAndCall(nextImplementation, reviewedInitializationBytes)`. Review proxy target/value0 and simulate as the real
Safe. The script's UUID check alone is **not** storage compatibility or an audit.

## Rollback limits and release gaps

Before funding, a stopped backend/indexer release can be rolled back through its normal release path. After manager
activation, old user IDs still point to their recorded vault; switching back cannot rewrite them. Deposits incur entry
costs and locks. Recovery custody, liquidation and a finalized loss rate are irreversible operational decisions; do not
unpause a recovered vault or reuse it for new deposits. Upgrades cannot guarantee recovery from loss of external assets.

This protects **future yBOLD positions only**. It neither upgrades the deployed Beefy adapter nor repairs an old blocked
withdrawal. Full historical index replay, actual target AWS/environment diff, fresh signing-time simulation and explicit
Gate 2 approval remain release gates even if local tests/CI pass. No test or AI audit proves the absence of exploits.
