## Audit result

I found no proven Critical or High severity issue. I found two Medium and two Low findings. The two Medium findings should be addressed before using the recovery system or release scripts as the production rollout gate.

This was a read-only source audit. I did not edit files, access `.env` or keys, deploy, broadcast, merge, or move funds.

### M-01 — Zero-liability state can strand strategy yield and donated ysyBOLD

A final healthy principal withdrawal can set `principalValue` to zero while intentionally leaving yield-bearing `principalShares` behind.

- Code: [YBoldYieldVault.sol:310](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:310)
- Recovery rejects this state: [YBoldYieldVault.sol:338](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:338)
- Core ysyBOLD cannot be rescued normally: [YBoldYieldVault.sol:452](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:452), [YBoldYieldVault.sol:620](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:620)
- Recovery surplus sweep is only reachable after settlement: [YBoldYieldVault.sol:388](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:388)
- Existing test confirms that a final withdrawal can preserve yield shares: [retrievePrincipal.t.sol:53](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/tests/YBoldYieldVault/retrievePrincipal/retrievePrincipal.t.sol:53)

Root cause: `initiateRecovery()` requires both `principalShares` and `principalValue` to be nonzero. That conflates “no outstanding principal liability” with “no assets requiring recovery.”

Caller trace:

```text
YieldManager.retrieveFunds
  → YBoldYieldVault.retrievePrincipal
  → principalValue becomes 0, yield shares remain
  → an integration failure prevents claimYield
  → recoverySafe.initiateRecovery reverts InvalidRecoveryState
```

Impact: protocol yield can become inaccessible through the intended recovery mechanism precisely when the Yearn exit path becomes unusable. Direct ysyBOLD donations to an otherwise empty strategy have the same custody gap. A UUPS upgrade remains an escape hatch, so this is stranding rather than irrecoverable theft.

Smallest fix: add an explicit zero-liability recovery path. When `principalValue == 0`, allow the recovery Safe to transfer all actual ysyBOLD to the designated recovery custody and transition directly to a surplus-only settled state. Define whether tracked residual yield belongs to the YieldManager or treasury rather than silently treating it as a donation.

### M-02 — Migration preflight does not pin the intended production configuration

The preflight validates implementation code, UUPS compatibility, roles, ysyBOLD, and operational state, but it does not validate:

- The deterministic expected proxy address.
- WETH, USDC, BOLD, yBOLD, routers, Curve pool or oracle addresses.
- Default slippage and maximum-loss values.
- The exact routine admin `...f83`.
- The recovery Safe’s exact seven-owner set, threshold `3`, modules or guard.

Relevant validation: [YBoldMigrationPreflight.s.sol:87](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/YBoldMigrationPreflight.s.sol:87). It then emits the manager-switch calldata at [YBoldMigrationPreflight.s.sol:61](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/YBoldMigrationPreflight.s.sol:61).

The deployment script checks more configuration, but derives security-critical role and Safe expectations from environment values and only checks Safe owner count/threshold, not the actual owner set or enabled modules: [DeployYBoldYieldVault.s.sol:60](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/DeployYBoldYieldVault.s.sol:60), [DeployYBoldYieldVault.s.sol:145](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/DeployYBoldYieldVault.s.sol:145).

Root cause: the release gate proves that the candidate is internally coherent, not that it is the specific approved mainnet configuration.

Caller trace:

```text
operator supplies proxy/config through environment
  → preflight accepts any compatible proxy with matching implementation/roles/ysyBOLD
  → generated setYieldVault calldata is executed by admin governance
  → deposits begin using that proxy’s unchecked routes, assets and oracles
```

Impact: an honest release/configuration mistake can select an unintended yet structurally valid proxy or routing/oracle graph. Depending on the error, this causes reverts, incorrect pricing protection, or assets entering the wrong integration. This does not rely on malicious treasury governance.

Smallest fix: make preflight consume a reviewed release manifest and require equality for the proxy, every dependency, both default risk parameters, routine admin, Safe address, owner-set hash, threshold, and approved module/guard state. Prefer hard-coded or signed release expectations rather than comparing deployment state to self-declared environment values.

The upgrade script is similarly minimal—it checks code hash and UUID but not storage-layout compatibility or post-upgrade invariants: [UpgradeYBoldYieldVault.s.sol:18](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/script/UpgradeYBoldYieldVault.s.sol:18). Keep the storage-layout checker and fork rehearsal mandatory in the release procedure.

### L-01 — Intentional distribution skips trigger harvesting every 15 minutes

The backend harvests before determining whether yBOLD distribution can run:

- Scheduler: [validator-graduator.ts:79](/private/tmp/seba-ybold-backend/lambdas/scheduled/validator-graduator/validator-graduator.ts:79)
- Distribution returns `false` for recovery, pause, or no claimable yield: [contract-calls.ts:88](/private/tmp/seba-ybold-backend/lambdas/scheduled/validator-graduator/contract-calls.ts:88)
- Timestamp remains unchanged on that result: [validator-graduator.ts:87](/private/tmp/seba-ybold-backend/lambdas/scheduled/validator-graduator/validator-graduator.ts:87)
- The test explicitly expects the timestamp to stay zero but does not assert that harvesting stops: [yield-maintenance.test.ts:147](/private/tmp/seba-ybold-backend/test/yield-maintenance.test.ts:147)

Root cause: `false` combines an intentional no-op with an execution failure, while the harvester transaction precedes the check.

Impact: while recovery/pausing/no-yield persists, each scheduler invocation can submit another independent harvest transaction instead of respecting the 12-hour cadence. The claimable precheck also uses exact zero while the contract suppresses claims below `1e12`, causing avoidable transactions for dust.

Smallest fix: return a tri-state result—executed, intentional no-op, or failure. Check recovery/pause and the on-chain `1e12` threshold before harvesting; advance the cadence for intentional no-ops but retain it after genuine failures.

### L-02 — A rejecting contract depositor can prevent recovery completion

`YieldManager.retrieveFunds()` deletes the deposit, retrieves funds, then calls the depositor directly—even for a zero-value total-loss settlement:

- [YieldManager.sol:184](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YieldManager.sol:184)
- Recovery liability update and payout: [YBoldYieldVault.sol:470](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/src/YBoldYieldVault.sol:470)
- Existing normal-path test demonstrates that a rejecting recipient rolls the withdrawal back: [retrieveFunds.t.sol:50](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/tests/YieldManager/retrieveFunds/retrieveFunds.t.sol:50)

Root cause: settlement accounting and delivery to an arbitrary depositor contract are atomic.

Caller trace:

```text
contract deposits through YieldManager
  → recovery settles at zero or nonzero rate
  → contract calls retrieveFunds
  → YieldManager updates adapter liability
  → callback to msg.sender rejects
  → entire transaction reverts, restoring the liability
```

Impact: such a deposit cannot settle, so recovery never reaches `Settled` and legitimate excess cannot be swept. The attacker cannot steal other users’ entitlement, but can hold global finalization open.

Smallest fix: separate liability settlement from arbitrary recipient execution. Record a withdrawal credit and let the owner withdraw to a chosen payable recipient. In recovery, do not sweep genuine unclaimed entitlements as excess.

## Accounting and custody conclusions

I did not find a manager-ID/protocol-principal mismatch in the intended flows:

- User liabilities remain in their individual deposit IDs.
- SebaPool’s protocol liability is tracked separately in `YieldManager.principalValue`.
- Both aggregate correctly into the strategy’s `principalValue`.
- Migration preflight compares the strategy value against the manager-side total.
- Historical user IDs retain their recorded vault, so switching the active vault does not redirect old withdrawals.

Recovery settlement is fixed-rate and payout-order independent. Per-claim floor rounding can leave less than one wei per liability as final excess, but I found no first-claimer advantage. Normal underwater withdrawals use proportional shares with upward rounding, limiting rounding loss to approximately one vault share per withdrawal.

Direct token donations do not inflate `principalValue` or `principalShares`. ysyBOLD donations remain outside tracked accounting and are swept only after recovery settlement. WETH, USDC, BOLD and yBOLD are transient core assets and cannot be rescued if accidentally transferred directly; that is a custody/design limitation worth documenting.

## Unproven leads and assumptions

- Graph dynamic data source: [yieldManager.ts:99](/private/tmp/seba-ybold-subgraphs/subgraphs/seba-ethereum/src/yieldManager.ts:99) creates the yBOLD template after `NewYieldVaultSet`. A Safe multisend that switches the vault and deposits into it in the same transaction may miss the adapter’s first `Deposited` event depending on dynamic-template activation semantics. The later manager event refreshes aggregate state, so this is presently a lead, not a proven accounting defect. Test the exact multisend ordering or deploy the known proxy as a static data source.
- Current optimized runtime bytecode is 23,753 bytes, leaving only 823 bytes below EIP-170. The current implementation fits, but future upgrades need an explicit size gate.
- Correctness depends on the pinned yBOLD/ysyBOLD contracts retaining standard transfer behavior and Yearn-compatible `deposit`/`redeem` semantics. The interfaces align with the [Yearn V3 technical specification](https://github.com/yearn/yearn-vaults-v3/blob/master/TECH_SPEC.md), but I did not independently query live bytecode at block `26248207`.
- The stated pin state—withdrawn IDs 1–9, protocol principal `3033332133271012792310`, treasury zero ETH and `156014003721394916792917` ysyBOLD—is asserted in [YBoldTreasuryRolloutFork.t.sol:127](/Users/simon.deschutter/.codex/worktrees/ybold-stack-review/hero_boost/tests/fork/YBoldTreasuryRolloutFork.t.sol:127), but was not independently read from an RPC in this review.

## Verification and test gaps

- Storage-layout comparison against the checked-in baseline reported no incompatibility.
- No implementation storage collision or unguarded UUPS authorization path was found.
- Backend TypeScript checking and targeted ESLint passed.
- The subgraph’s generated yBOLD ABI matches the current contract artifact: 18 indexed entries verified.
- Contract and subgraph diffs passed `git diff --check`.
- Forge, fork, graph-build, and Jest suites were not freshly executed because they require filesystem writes. Jest stopped before running tests when its cache attempted to write outside the read-only sandbox.
- The existing `lcov.info` predates the current source and is not evidence of current 100% coverage.
- No fresh live checks were made for oracle feed identity/freshness, Curve liquidity, Uniswap fee-tier liquidity, Safe owners/modules/guard, or the exact pinned balances.

The audit used the local [vault-accounting](/Users/simon.deschutter/.codex/skills/plamen/agents/skills/injectable/vault-accounting/SKILL.md), [token-flow-tracing](/Users/simon.deschutter/.codex/skills/plamen/agents/skills/evm/token-flow-tracing/SKILL.md), [storage-layout-safety](/Users/simon.deschutter/.codex/skills/plamen/agents/skills/evm/storage-layout-safety/SKILL.md), and [zero-state-return](/Users/simon.deschutter/.codex/skills/plamen/agents/skills/evm/zero-state-return/SKILL.md) checklists. This review does not establish that every exploit or integration failure has been eliminated.
