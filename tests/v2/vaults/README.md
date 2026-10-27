# Native vault verification evidence

Scope: `NativeSupporterVault`, `RethSupporterVault`, `YsyBoldSupporterVault` and their interfaces. This is not a
full-stack audit or migration-success claim. No deployment, broadcast, production service change or real funds movement
was performed.

## Behavior and ABI

Both fixed-token UUPS proxies hold their own supporter positions and a segregated protocol bucket. rETH principal uses
recognized ETH basis; ysyBOLD principal uses recognized yBOLD basis. Entry and harvest start disabled. Native exits do
not redeem Yearn, burn rETH, swap or call USD feeds. Economic impairment permits proportional exits and blocks
affected-leg entry; physical custody shortage requires recovery. Owner checks and original 30-day supporter locks
remain.

Bucket indices are **0 supporter / 1 protocol**. `deposit()` returns `(localId,basis)`, `depositProtocol()` returns
`basis`, withdrawals return actual native tokens. `collectYield()` transfers only carry to fixed manager and atomically
calls `onYieldReceived(bucket,tokens)`. Concrete initializers have exactly four address arguments: Safe, manager proxy,
asset, and RocketStorage registry/rETH or yBOLD/ysyBOLD respectively.

Recovery exports exact accounted tokens to the fixed Safe and freezes ordinary operations. Full authenticated funding
precedes one-time fixed budgets. `fundRecovery()` returns exported backing; public `repairRecovery()` is irrevocable
donation. Safe-only `fundRefundableRecovery()` is separately recorded and requires full original return first. Only its
unused portion can become a treasury refund; public donations cannot. `RecoveryBucket` appends `refundableRepairTokens`
after the original fields (flattened return index 14). `RecoveryRefundableFunded` is a distinct funding event, not
duplicated as `RecoveryFunded`.

## TDD evidence

- The initial deposit test failed because the new vault source did not exist, then passed after implementation; this
  first RED was a missing-feature compile failure, not exploit proof.
- A behavioral negative control changed Yearn's API after deposit: expected failure did not occur. Runtime accounting
  now rejects a version other than reviewed 3.0.4; regression is green.
- A public 20-token recovery repair was incorrectly refunded to treasury in a behavioral RED. After explicit refundable
  funding was separated, treasury receives 0 and all unused donated backing goes to manager; regression is green.
- A report with block 0 was accepted under an unlimited lag bound in a behavioral RED. Missing report-block data is now
  rejected independently; regression is green.

## Reproduction and measured coverage

Solidity 0.8.28, Cancun, OpenZeppelin 5.2.0, Foundry 1.5.1-stable (`b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2`). Normal
builds use optimizer 10,000 and no CBOR metadata. Coverage uses Foundry's default unoptimized instrumentation, not the
production runtime-size settings.

```sh
forge test --match-path 'tests/v2/vaults/**' --no-match-contract VaultNativeForkTest --offline
RUST_LOG=error forge coverage --match-path 'tests/v2/vaults/**' \
  --no-match-contract VaultNativeForkTest --report lcov \
  --report-file /private/tmp/seba-v2-vault-coverage.info --offline -q
```

The fork suite is run separately below, not silently skipped. No vault source files are excluded from coverage.
Unmodified OpenZeppelin code, interfaces without executable code, tests and unrelated contracts are **not included in
this source-specific percentage**. The abstract zero-denominator guard uses an explicitly documented invalid-adapter
negative control; production adapters normalize their canonical zero-supply convention.

| Source                | Executable lines | Foundry branches | Functions |
| --------------------- | ---------------: | ---------------: | --------: |
| NativeSupporterVault  |          328/328 |            66/66 |     47/47 |
| RethSupporterVault    |            34/34 |              7/7 |       5/5 |
| YsyBoldSupporterVault |            14/14 |              3/3 |       3/3 |

Corresponding raw LCOV fields:

```text
SF:src/v2/NativeSupporterVault.sol FNF:47 FNH:47 LF:328 LH:328 BRF:66 BRH:66
SF:src/v2/RethSupporterVault.sol FNF:5 FNH:5 LF:34 LH:34 BRF:7 BRH:7
SF:src/v2/YsyBoldSupporterVault.sol FNF:3 FNH:3 LF:14 LH:14 BRF:3 BRH:3
```

The complete unit/property/invariant run reports **76 passed, 0 failed, 0 skipped**. Four fuzz searches run 1,000 cases
each: entry-rate credit, healthy principal preservation, impaired withdrawal-order bounds, and fixed recovery-budget
order bounds. The funded handler invariant runs 256 sequences / 16,384 calls with 0 reverts, mixing entry, exit, carry
collection, rate gain/loss, repair, pauses and recovery. Counters and a deterministic mixed-transition test prove
successful state changes; calls after terminal states intentionally become no-ops. An injected token-custody leak fails
the same invariant as a negative control. `.tree` files describe the public-method branches, with shared-helper negative
cases including fee/rebase/reentry deltas, overflow, authorization, locks, shortage and escrow isolation.

## Pinned mainnet component forks

```sh
# MAINNET_RPC must point to an authorized archive-capable endpoint. Never log credentials.
node tools/v2/run-foundry.mjs --env-file /path/to/private.env \
  test --match-contract VaultNativeForkTest -vv
```

**3 passed, 0 failed, 0 skipped**, pinned block **26,255,470**, with optional explicit `SEBA_V2_FORK_BLOCK` override for
a separately labelled fresh rehearsal:

1. Entire actual treasury rETH (>40 rETH) and ysyBOLD (>100,000 shares) deposited into local proxies; basis/floor/ceil
   matched deployed canonical getters. Native exits after unlock reconcile every token and basis without artificial
   token funding.
2. Explicitly fault-injected burn, both Yearn-redemption routes and USD-feed failures leave real-token native exits
   working; rejected manager callback does not enter withdrawal path.
3. Explicitly fault-injected Yearn canonical-view failure exports and returns real ysyBOLD custody, activates a
   disclosed 10% token-haircut exceptional budget, settles native tokens and leaves the rETH vault usable.

Safe account impersonation, artificial 30-day time advancement and `mockCallRevert` are local test techniques, not
production signing or fresh-market evidence. Treasury funding is returned actual exported native tokens, not a synthetic
ETH top-up. Fault injection is not proof a real venue is currently broken. These component tests do not establish
complete manager/executor/Safe-migration/backend/indexer E2E success or recovery at par.

## Checks and operational boundaries

Prettier check and semantic NatSpec lint pass. Optimized deployed runtimes: rETH 21,501 bytes; ysyBOLD 21,073 bytes,
below EIP-170. Large test-harness initcode warnings concern embedded local fixtures, not these production
implementations. The bundled forge-std exposes legacy `snapshot/revertTo`; tests using them pass on the pinned Foundry
version but emit deprecation warnings.

Independent peer review and the full release audit remain separate gates. Safe upgrade authority can move all assets
despite today's native-token sweep restriction. Recovered manager buffers do not automatically pause public vault
entry/harvest: explicitly coordinate those flags when retiring a manager, preserving native exits. Leaf manager binding
is fixed; restoring automatic donation delivery after terminal manager recovery requires a reviewed same-manager upgrade
or separately reviewed migration, not an ordinary relink.

Focused peer review of the manager found no unprivileged principal debit in callback/finalization or cross-leg paths.
Agreed release limits: an armed exact legacy import cannot be rearmed after amount/expiry drift without a fresh disabled
candidate or reviewed upgrade; current executor routes consume every input or revert, so accidental unassigned
core-token transfers remain upgrade-only rather than becoming classified rewards. Validate real multisig/code/token
identities and reciprocal graph at release; `code.length` alone does not authenticate a multisig. This focused review is
not a completed twelve-lane Pashov audit.
