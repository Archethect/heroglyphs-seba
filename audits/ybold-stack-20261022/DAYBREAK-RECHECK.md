## Final recheck result

No proven Critical or High issue was found. The four initial findings classify as follows:

| Finding | Classification | Current severity |
|---|---|---|
| M-01 Zero-liability recovery | Mitigated with residual limitation | Low residual |
| M-02 Release configuration pinning | Mitigated with residual limitation | Medium release-control gate |
| L-01 Backend harvest cadence | Fixed in current backend source | — |
| L-02 Rejecting recipient callback | Unresolved | Low |

### Initial findings

**M-01 — Mitigated with residual limitation**

The principal fix is sound. Recovery now permits `principalValue == 0` when tracked `principalShares` remain, transfers those tracked shares without consulting Yearn, and transitions directly to `Settled`: [YBoldYieldVault.sol:338](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:338), [YBoldYieldVault.sol:349](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:349), [YBoldYieldVault.sol:361](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:361). The regression scenario is encoded at [recovery.t.sol:13](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/tests/YBoldYieldVault/recovery/recovery.t.sol:13), but was not executed during this review.

Residual limitation: unsolicited core-token donations are not generally recoverable from an otherwise empty adapter. In particular, an adapter holding only donated ysyBOLD still has `principalShares == 0`, so `initiateRecovery()` reverts; normal rescue rejects every core asset; and surplus sweeping is reachable only after entering `Settled`: [YBoldYieldVault.sol:340](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:340), [YBoldYieldVault.sol:396](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:396), [YBoldYieldVault.sol:460](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:460), [YBoldYieldVault.sol:628](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:628). Direct WETH, USDC, BOLD, yBOLD, and donation-only ysyBOLD custody is therefore documented, not fixed.

**M-02 — Mitigated with residual limitation**

The new release checks materially improve the gate:

- Governance, treasury, threshold, exact seven-owner ordering, empty module list, and zero guard are pinned in [YBoldReleaseChecks.sol:21](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/YBoldReleaseChecks.sol:21).
- Dependencies, feeds, roles, risk parameters, and operating state are pinned in [YBoldMigrationPreflight.s.sol:99](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/YBoldMigrationPreflight.s.sol:99).
- Deployment deterministically derives and validates the implementation/proxy configuration in [DeployYBoldYieldVault.s.sol:69](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/DeployYBoldYieldVault.s.sol:69) and [DeployYBoldYieldVault.s.sol:139](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/DeployYBoldYieldVault.s.sol:139).

The remaining weakness is that the expected proxy, implementation address, and implementation hash are still supplied by the same operator environment being checked: [YBoldMigrationPreflight.s.sol:100](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/YBoldMigrationPreflight.s.sol:100), [YBoldMigrationPreflight.s.sol:103](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/YBoldMigrationPreflight.s.sol:103). The upgrade script follows the same model for current and next artifacts: [UpgradeYBoldYieldVault.s.sol:21](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/UpgradeYBoldYieldVault.s.sol:21).

Consequently, these scripts are strong consistency checks but are not independently anchored to a signed or immutable artifact manifest. This remains a Medium release gate if the preflight is treated as standalone authorization. It is operationally mitigated only when Gate 2 independently approves and records the exact proxy, implementations, hashes, and calldata.

**L-01 — Fixed**

At the final snapshot, backend commit `8310ac123c59ab217fa461d25a16009d8847944a` is clean and contains the cadence fix. Harvesting has a separate persisted checkpoint and advances it only after confirmed success; a distribution no-op no longer causes another harvest transaction on every poll: [validator-graduator.ts:82](/private/tmp/seba-ybold-backend/lambdas/scheduled/validator-graduator/validator-graduator.ts:82). Recovery/paused strategies fail closed before a harvest transaction, and dust below the onchain `1e12` threshold skips distribution: [contract-calls.ts:90](/private/tmp/seba-ybold-backend/lambdas/scheduled/validator-graduator/validator-graduator-helpers/contract-calls.ts:90), [contract-calls.ts:125](/private/tmp/seba-ybold-backend/lambdas/scheduled/validator-graduator/validator-graduator-helpers/contract-calls.ts:125).

Intentional skips can still cause repeated read-only checks, but not repeated harvesting transactions.

**L-02 — Unresolved**

`YieldManager.retrieveFunds()` still deletes the deposit, settles the adapter, and calls the arbitrary depositor atomically—even when `funds == 0`: [YieldManager.sol:184](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YieldManager.sol:184), [YieldManager.sol:190](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YieldManager.sol:190), [YieldManager.sol:197](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YieldManager.sol:197).

A rejecting depositor therefore rolls back its recovery settlement and can keep the vault out of `Settled`, delaying the final sweep. The current fork test explicitly preserves this limitation rather than fixing it: [YBoldTreasuryRolloutFork.t.sol:154](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/tests/fork/YBoldTreasuryRolloutFork.t.sol:154).

### Named branch checks

- **Exact-share donation accounting:** Correct when recovery is enterable. Recovery requires actual shares to be at least tracked shares, transfers exactly the tracked amount, leaves surplus donations outside liabilities, and sweeps them only after settlement: [YBoldYieldVault.sol:342](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:342), [YBoldYieldVault.sol:350](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:350), [YBoldYieldVault.sol:399](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:399).
- **Zero-rate payout:** Correct inside the adapter. An explicit zero settlement is allowed, while a nonzero settlement that rounds to a zero rate is rejected. Claims clear principal without consuming ETH: [YBoldYieldVault.sol:378](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:378), [YBoldYieldVault.sol:385](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:385), [YBoldYieldVault.sol:478](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:478). End-to-end completion remains subject to L-02.
- **Storage preservation:** The current `YBoldYieldVault` delta adds no storage fields or reorders existing fields. The checked-in checker compares the baseline, current implementation, ERC-7201 namespaces, and an append-only V2 fixture: [check-storage-layout.cjs:14](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/tools/ybold/check-storage-layout.cjs:14), [check-storage-layout.cjs:43](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/tools/ybold/check-storage-layout.cjs:43). This is source-level evidence only; the checker was not freshly executed. The upgrade script itself does not prove layout compatibility.

### Lead

The dynamic subgraph template is still created only after `NewYieldVaultSet`: [yieldVaultState.ts:58](/private/tmp/seba-ybold-subgraphs/seba-ethereum/src/yieldVaultState.ts:58). Same-transaction activation plus first deposit remains unproven, not a demonstrated indexing defect. The runbook correctly gates this by requiring separate transactions: [YBOLD_INDEXING_RUNBOOK.md:44](/private/tmp/seba-ybold-subgraphs/docs/YBOLD_INDEXING_RUNBOOK.md:44).

### Release gates

- The contracts tree remains dirty and contains material untracked release files. It is not yet pinned to a final commit. The reviewed `YBoldYieldVault.sol` blob was `9da415cc02d5d49d980f4be3ab71c917ceb4eceb`.
- Freeze and independently approve the exact proxy/implementation hashes and calldata outside the operator-supplied environment.
- Run fresh contract, storage, fork, backend, and subgraph checks against the frozen commits. I did not execute them and did not treat existing logs as current pass evidence.
- Complete the original-start-block subgraph replay and fresh live Safe/state/venue checks before release.

This was a single-agent, source-only recheck—not a full Pashov harness execution and not a guarantee that all exploit paths have been eliminated.
