# Contract verification — 22 October 2026

No transaction was broadcast, signed, deployed on a public network, or merged. Fork deployments and authority
impersonation are local test operations, not proof of signer availability.

## Reproduction

Foundry 1.5.1 (`b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2`), Solidity 0.8.28, OpenZeppelin contracts/upgradeable 5.2.0,
upgrades-core 1.46.0. Install the locked dependencies with `yarn install --frozen-lockfile --ignore-scripts`. For fork
commands, provide `MAINNET_RPC` privately; do not print credentials.

```sh
# Complete repository regression suite, including legacy fork-dependent fixtures
forge test -vv

# Current treasury-start and serialized release-script fork scenarios
forge test --match-contract 'YBoldTreasuryRolloutForkTest|YBoldReleaseScriptsTest' -vv

# Exact offline CI coverage command: no RPC or invariant/fork fixture is required
env -u MAINNET_RPC forge coverage --match-path 'tests/YBoldYieldVault/**/*.t.sol' --no-match-path 'tests/YBoldYieldVault/invariant/**' --report summary --report lcov

# Combined contract/script/fork coverage; smaller sequence search only for instrumentation
FOUNDRY_INVARIANT_RUNS=128 FOUNDRY_INVARIANT_DEPTH=64 FOUNDRY_INVARIANT_FAIL_ON_REVERT=true forge coverage --match-contract 'YBold.*Test' --report summary --report lcov

# Independent, larger sequence campaign (not a coverage claim)
FOUNDRY_INVARIANT_RUNS=1024 FOUNDRY_INVARIANT_DEPTH=128 FOUNDRY_INVARIANT_FAIL_ON_REVERT=true forge test --match-contract YBoldAccountingInvariantTest -vv

# Fresh optimized build, actual OpenZeppelin validation, baseline/V2 storage checks, EIP-170 check
node tools/ybold/check-storage-layout.cjs
```

## Observed results

- Complete suite after all final role/script-negative checks: **262 passed, 0 failed, 0 skipped**, 55 suites in 282.31
  seconds, default 1,000 cases per fuzz test (`foundry-full.log`).
- Current treasury-start fork: **10/10 passed**. Serialized release-script fixture: **1/1 passed**; its internal cases
  are sequential because `vm.setEnv` mutates the host process. This fixture lives under `tests/fork/`, not the offline
  unit-test directory.
- Exact offline coverage selection: **86/86 passed**. Combined coverage selection: **111/111 passed**.
- Larger sequence campaign: **2/2 invariants passed**, each 1,024 runs × 128 actions = 131,072 calls, **262,144 calls
  total and zero unexpected handler reverts**. Each sequence also attempts final reconciliation through
  `afterInvariant`.
- OpenZeppelin upgrade-safety validation: **SUCCESS**. Storage compatibility against PR baseline
  `6010890862f15b98a12535e716258fb1263c02b9`, including ERC-7201 namespaces: **PASS**. Current → append-only V2 fixture:
  **PASS**; deliberately incompatible existing-slot control: **rejected**. Optimized adapter runtime: **23,873 / 24,576
  bytes**.
- Changed contract/test formatting: Prettier **PASS**. Adapter/interface Solhint: **0 errors**, four retained warnings
  (state-count and the existing public WETH/USDC/BOLD naming convention).

## Coverage

Production counts are identical under the exact offline command and combined command. No production line or branch
exclusions were used.

| File                                   |   Lines | Statements | Branches | Functions |
| -------------------------------------- | ------: | ---------: | -------: | --------: |
| `src/YBoldYieldVault.sol`              | 285/285 |    390/390 |    61/61 |     37/37 |
| `src/YBoldConfigValidator.sol`         |   36/36 |      42/42 |      6/6 |       4/4 |
| `script/DeployYBoldYieldVault.s.sol`   |   77/77 |      89/89 |    72/75 |       2/2 |
| `script/UpgradeYBoldYieldVault.s.sol`  |   18/18 |      21/21 |    16/16 |       1/1 |
| `script/YBoldMigrationPreflight.s.sol` |   86/86 |      93/95 |  105/105 |       3/3 |
| `script/YBoldReleaseChecks.sol`        |   17/17 |      19/20 |    10/10 |       1/1 |

The only uncovered script branches are the false arms of `VALIDATOR_ADDRESS`, `IMPLEMENTATION_ADDRESS`, and
`PROXY_ADDRESS` in `DeployYBoldYieldVault.s.sol` (lines 114, 118, 122 at this revision). Each compares the result of a
successful CREATE2 against the independently computed address from the identical deployer, salt, and init code. Reaching
a mismatch requires violating CREATE2 determinism/tooling assumptions, not supplying a different valid deployment input.
Both create-new and reuse-existing paths are tested by calling the full script twice in one local fork. These three
defensive assertions remain in the raw denominator: deployment-script branch coverage is **96.00%, not 100%**. Script
statement counts are reported as measured, not rounded up.

All feasible negative release guards are tested: authority addresses; exact threshold/owner set/module list/guard;
reviewed proxy inventory; code, UUID and implementation hash; roles and their administrators; every pinned integration
and default risk parameter; stale custody/manager expectations; active old/other-vault IDs; partially deleted IDs;
protocol/user liability reconciliation; share shortfalls and old-adapter dust limits. [`ybold.lcov`](./ybold.lcov)
contains the combined raw counters. Unrelated legacy contracts and test helpers are not included in the production 100%
claim.

## What the current fork actually proves

Pin: block **26,248,207**, hash `0xf5e4c17803a895df4694de95ccfd727f0687c296ec04b0430b447527af8fb528`, **2026-10-22
12:38:59 UTC**. Treasury `0x888D768764A2E304215247F0bA3457cCb0f0ab4f` is the verified 3-of-7 upgrade/recovery Safe;
routine admin is the separate existing governance contract `0xf83b11b09EEc073ACE4481b2F4c8357e156714b3`.

The treasury starts with **0 ETH** and **156,014.003721394916792917 ysyBOLD**, not liquid ETH. The test uses those
actual shares: ysyBOLD → yBOLD → BOLD → Curve USDC → Uniswap WETH → ETH. Actual local-fork result:
**71.037406571234590178 ETH**, before transaction gas. This is a pin-specific simulated result, not an execution quote
or par guarantee.

Old user IDs 1–9 are already deleted. Switching the real manager successfully exits its remaining old protocol principal
at this pin; measured old-adapter residue is **121 shares / 150 native principal units**. The manager then redeposits
the protocol ETH and two actual-capital user tranches through the new proxy. New user principal is
**171,285.696337397184669268 yBOLD**, protocol principal **3,103.618434529769371749 yBOLD**, tracked receipt balance
**158,540.401915728379729566 ysyBOLD**. These units must not be added to ETH amounts.

The healthy path covers the existing 30-day user lock, protocol withdrawal and deletion of both new user IDs. Yearn's
naturally unlocked remaining yield shares can be recovered after principal reaches zero. Emergency cases cover
unavailable Yearn, unusable Curve, a failing swap venue and stale oracle; rollback of failed ordinary exits; exact share
custody transfer; real liquidation of recovered shares; actual-proceeds ETH funding; full-proceeds and 80%-of-proceeds
uniform-rate settlements; zero-ETH total-loss settlement; duplicate claims; final liabilities and dust; authorized
upgrade and preserved position state.

## Deliberate limits and unresolved constraints

- Exit failures are explicitly injected faults. Future oracle refreshes retain original prices and are not predictions.
  Treasury share liquidation and funding in the current-fork recovery tests use actual fork assets: **no synthetic
  treasury ETH top-up or minted capital**. “Full proceeds” means allocation of the measured proceeds, not restoration of
  original ETH at par. The 80% case deliberately allocates only 80% of proceeds to claims; it is a settlement-mechanics
  stress case, not a claim that Yearn suffered that loss.
- Archival tests at blocks 25,831,161 and 26,196,493 retain historical unwind/yield-harvest regressions; the archived
  ID-4 liquidity failure is **not** presented as today's state or current E2E result. Historical yield-report and
  BOLD-conversion tests explicitly use synthetic profit/conversion inputs.
- The unit sequence model has four liability buckets, mocked integrations and synthetic capital/profit/loss. It tests
  conservation, donation handling, terminal-state transitions, payout ordering and eventual mechanical reconciliation;
  it does not prove market liquidity, future prices, real signer execution or all interleavings of every privileged
  setter. An empty external ERC-4626 donation can make a new mint round to zero; the exact expected revert is checked
  for atomic accounting/ETH preservation, and a deterministic regression covers it.
- The unchanged YieldManager calls the depositor even for a zero-ETH payout. A contract rejecting that call keeps **its
  own** ID claimable and delays `Settled`/excess sweep; other users and protocol principal can still settle. A
  real-manager fork regression proves this limitation. No manager/pool change or direct treasury payout bypass was
  introduced.
- Unaccounted donations with no tracked position remain outside the normal core-token rescue path; trusted upgrade
  authority is the fallback. Treasury recovery does not guarantee assets survive a loss in Yearn/BOLD, nor constrain a
  malicious future implementation controlled by the upgrade authority.
- `medusa --version` and `echidna --version` both returned `command not found`. The Fizz skill's full campaign is
  blocked at its tooling gate. **No Medusa, Echidna or Halmos campaign is claimed.** Foundry's sequence search is
  separately identified above. Optional installation references:
  [Medusa](https://secure-contracts.com/program-analysis/medusa/docs/src/getting_started/installation.html),
  [Echidna](https://secure-contracts.com/program-analysis/echidna/introduction/installation.html).

Raw local `.log` files are retained but ignored; multi-megabyte Foundry coverage-anchor warnings are not intended for
the review diff.
