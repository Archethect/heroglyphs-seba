# Beefy to yBOLD migration runbook

Status: implementation and fork simulation only. Approval Gate 2 prohibits deployment, broadcasting, source
verification, fund migration, or merging until explicit approval. A review PR is permitted; it does not authorize
deployment.

The reviewed adapter is an OpenZeppelin UUPS implementation behind an ERC-1967 proxy from its first deposit. UUPS was
chosen over Transparent because the implementation already has role-based authorization, it avoids a second ProxyAdmin
contract, and it keeps the persistent deployment surface small. `ADMIN_ROLE` controls routine bounded settings; a
separate, self-administered `UPGRADER_ROLE` controls upgrades; the configured treasury holds `RECOVERY_ROLE`. Both
upgrade authority and treasury must be independently verified governance-controlled contract accounts (the approved
multisig/governance execution path), never EOAs.

The recovery implementation is present at launch. If a normal ETH exit is blocked, it can atomically freeze the adapter
and transfer exactly reconciled st-yBOLD shares to recovery custody without invoking Yearn, Curve, Uniswap, or an
oracle. The treasury must later liquidate or otherwise value those shares and fund a final uniform ETH settlement. This
is a trusted-treasury escape path, not a guarantee against Yearn/BOLD loss or treasury execution loss. Proxy governance
can ultimately replace the implementation and move all strategy assets despite the routine core-token rescue
restriction; review, signer separation, public simulation, and emitted events are the controls for that trust.

## Scope and fixed mainnet graph

The migration keeps the deployed Seba contracts and replaces only the `IYieldVault` adapter.

| Component             | Mainnet address                              |
| --------------------- | -------------------------------------------- |
| SebaPool              | `0xe3B17b4533b339d3CBC26F57199d3fb937129894` |
| YieldManager          | `0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269` |
| old Beefy adapter     | `0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba` |
| pybSeba               | `0x8D06a179486111E556A7C46E49352259B0279CD1` |
| known depositor/admin | `0x888D768764A2E304215247F0bA3457cCb0f0ab4f` |
| governance admin      | `0xf83b11b09EEc073ACE4481b2F4c8357e156714b3` |
| automator             | `0x8FbBC54D49b23F5b397dfE62AD2Fb0E09Cbe9379` |
| BOLD                  | `0x6440f144b7e50D6a8439336510312d2F54beB01D` |
| Curve BOLD/USDC       | `0xEFc6516323FbD28e80B85A497B65A86243a54B3E` |
| yBOLD                 | `0x9F4330700a36B29952869fac9b33f45EEdd8A3d8` |
| st-yBOLD              | `0x23346B04a7f55b8760E5860AA5A77383D63491cD` |

Release-specific addresses for the stateless config validator, implementation, and ERC-1967 proxy are derived by the
reviewed CREATE2 script and must be copied from the successful dry run. **Only the proxy address** may be supplied to
`YieldManager.setYieldVault`, `YBOLD_VAULT`, monitoring, or recovery calls. The implementation and validator never
receive principal.

The fresh fork snapshot is Ethereum block `26,196,493`: deposits 1–9 still belong to the known depositor and point to
the old adapter, but the staged unwind currently fails at deposit ID 4 with Curve's `Not enough coins removed`. The
failed transaction preserves that deposit and the old adapter's shares. **This is a release blocker:** there is no
successful full E2E migration proof at the fresh snapshot, and a historical success must not be treated as a live
execution quote. The complete staged-route test is pinned separately to historical block `25,831,161`; it leaves 119 old
Beefy shares and 147 old principal-value units, within the fixed 120-share/150-value dust limits. These bounds are
release assertions, not permission to ignore a larger residual.

## Required tools and environment

- Foundry with Solidity 0.8.28.
- An archive-capable Ethereum RPC. A fresh fork of the intended execution block must pass the full migration route
  before Gate 2 can be considered; the currently pinned fresh block does not.
- An Etherscan API key only for eventual source verification.
- Controlled signers for the known depositor and a current `ADMIN_ROLE` holder.
- Transaction simulation and protected submission for value-moving steps. The custody, deployment, and redeposit stages
  are intentionally separate; they are not one atomic bundle.

Set, without printing secrets:

```bash
MAINNET_RPC=...
ETHERSCAN_API_KEY=...
YBOLD_EXPECTED_DEPLOYER=0x...
YBOLD_ADMIN=0xf83b11b09EEc073ACE4481b2F4c8357e156714b3
YBOLD_UPGRADE_AUTHORITY=0x... # reviewed governance/multisig contract; never an EOA
YBOLD_RECOVERY_TREASURY=0x... # reviewed recovery multisig/treasury contract; never an EOA
YBOLD_MIGRATION_ADMIN=0xf83b11b09EEc073ACE4481b2F4c8357e156714b3
YBOLD_VERSION_SALT=0x...
YBOLD_EXPECTED_OLD_ACTIVE=9 # change to the exact count before each preflight rerun
YBOLD_EXPECTED_IMPLEMENTATION=0x... # dry-run implementation, not the manager's vault
YBOLD_VAULT=0x... # ERC-1967 proxy only; omit before deployment
```

## Dry run and fork proof

Run these before preparing signatures:

```bash
forge build
forge test --match-path 'tests/YBoldYieldVault/**/*.t.sol'
forge test --match-contract YBoldMigrationForkTest --fork-url "$MAINNET_RPC"
forge coverage --match-path 'tests/YBoldYieldVault/**/*.t.sol' --report summary
forge inspect YBoldYieldVault storage-layout
forge script script/DeployYBoldYieldVault.s.sol:DeployYBoldYieldVault --rpc-url "$MAINNET_RPC" -vvvv
forge script script/YBoldMigrationPreflight.s.sol:YBoldMigrationPreflight --rpc-url "$MAINNET_RPC" -vvvv
```

Do not add `--broadcast` or `--verify` before Gate 2 approval. The preflight script is read-only and prints exact
calldata for the current stage. Before adapter deployment, leave `YBOLD_VAULT` unset; after deployment, set it to the
verified **proxy** address and set `YBOLD_EXPECTED_IMPLEMENTATION` to the implementation printed by the same dry run.
The preflight reads the EIP-1967 implementation slot and rejects an implementation address passed as `YBOLD_VAULT`. Set
`YBOLD_EXPECTED_OLD_ACTIVE` to the independently reconciled number of remaining old user deposits on every run: 9
initially, decreasing after each successful withdrawal, then 0 before the strategy switch. With salt `0x00…01`, deployer
`0x888D…ab4f`, and admin `0xf83b…14b3`, the 2026-10-13 dry run predicted `0x1bE31C869caCF38F595DDAF252F337744148E429`;
that obsolete direct-adapter prediction predates the proxy/recovery change and must not be used. Any input, authority,
compiler setting, or bytecode change requires three new reviewed predictions (validator, implementation, proxy).

The historical E2E uses actual ETH recovered from old user positions for its two redeposit tranches. Its yield harvest
later injects synthetic Yearn profit/BOLD and refreshes oracle mocks; it does not prove live CowSwap solver settlement.
The 1,000 ETH rejection test also uses test-only capital. Neither substitutes for an execution-day quote.

### Focused coverage evidence

Command:

```bash
forge coverage --match-path 'tests/YBoldYieldVault/**/*.t.sol' --report summary
```

Review result:

| Changed onchain file           | Lines   | Statements | Branches | Functions |
| ------------------------------ | ------- | ---------- | -------- | --------- |
| `src/YBoldYieldVault.sol`      | 276/276 | 378/378    | 58/58    | 37/37     |
| `src/YBoldConfigValidator.sol` | 36/36   | 42/42      | 6/6      | 4/4       |

There are no exclusions inside either changed production contract. The command intentionally focuses on the yBOLD unit
suite; Foundry's aggregate row also lists unrelated legacy contracts, deployment scripts, helpers, and mocks as
uncovered. Those entries are not included in the 100% changed-onchain coverage claim. Fork tests are separate evidence
and are not used to inflate unit coverage. The focused suite passes 79/79 tests with the configured 1,000 fuzz runs. A
separate full-repository archive smoke run passes 242/242 tests with legacy fuzzing explicitly bounded to one case; it
is regression evidence, not the basis of the changed-code coverage claim.

### Mainnet-fork evidence

`forge test --match-contract YBoldMigrationForkTest` passes 12/12 against an archive-capable RPC. The evidence is
deliberately classified:

- Real fork behavior: proxy initialization, live yBOLD/st-yBOLD deposits, healthy round-trip withdrawal, governance
  upgrade with storage preservation, pause/core-rescue behavior, real YieldManager user IDs and protocol-principal
  settlement/switch, interrupted-unwind resume, and the historical complete migration rehearsal.
- Fault injection: Curve EMA imbalance, Uniswap router failure, Yearn `maxRedeem == 0`, stale Chainlink rounds, and
  synthetic st-yBOLD profit. These prove fail-closed and recovery mechanics, not that those faults exist at the pinned
  block.
- Synthetic capital: treasury ETH funding and the 1,000 ETH stress input. Funding proves fixed-rate payout mechanics; it
  does not prove st-yBOLD liquidation price or depth.
- Fresh-block blocker: the test passes by proving that the current old Beefy unwind reverts at deposit ID 4 with
  `Not enough coins removed` and leaves its ID/shares/accounting unchanged. This is an unresolved migration blocker, not
  a successful current-block end-to-end migration.

## Pre-migration inventory and abort conditions

Before the first withdrawal, record block number and timestamp, then verify:

1. `YieldManager.yieldVault()` is the old Beefy adapter.
2. `depositId()` is still 9; deposits 1-9 have the expected depositor, old adapter, amount, and expired unlock time.
3. Sum the nine deposit amounts and record the manager and old-adapter principal values/shares.
4. `pendingBoldConversion() == 0` and `activeRouterUid() == 0x00`.
5. The depositor and migration admin roles are still controlled and able to sign.
6. yBOLD and st-yBOLD are not shut down, both accept deposits, and both can redeem the simulated amounts at zero loss.
7. Curve coin 0 is BOLD, coin 1 is USDC, its moving-average price is within 1%, and live quotes satisfy the configured
   0.50% WETH/USDC execution limit and the BOLD nominal floor (1% accepted peg deviation plus 0.50% execution loss).
8. ETH/USD age is at most one hour and USDC/USD age is at most 23 hours.
9. Validator, implementation, and proxy bytecode and constructor arguments match the reviewed artifacts; the EIP-1967
   slot equals `YBOLD_EXPECTED_IMPLEMENTATION`; only the proxy has initialized roles/configuration; implementation
   initialization is locked; default limits are 50 bps swaps, 100 bps peg, zero normal Yearn loss, and 100 bps emergency
   Yearn loss.
10. Admin, upgrade, and recovery authorities match the approved contract accounts. Upgrade authority is not an EOA, does
    not hold routine `ADMIN_ROLE` merely by being upgrader, and is the role admin for recovery. Recovery state and every
    recovery-accounting field are zero/`Normal`.
11. No new `FundsDeposited`, Cow intent, role change, pause, upgrade, recovery event, Yearn shutdown, or material
    liquidity change occurred while signatures were prepared.

Before each later stage, rerun the applicable checks against live state: remaining old IDs and ETH actually recovered
during unwind; treasury custody and a zero remaining-old count before the switch; manager-held ETH and old-adapter dust
immediately after the switch; new adapter shares/value and new deposit IDs after redeployment. Re-simulate every
value-moving transaction at its intended amount and current block.

Abort on any mismatch, stale oracle, failed simulation, changed deposit ID, unexpected balance/dust, or output below a
signed minimum. The old adapter has no hard deposit pause; use an off-chain intake freeze and watch `depositId` until
the switch is complete.

## Staged migration sequence

Before these steps, run the automator once if necessary to settle/cancel any Cow intent and require both pending fields
to be zero. Do not assume the following steps are atomic. Keep a signed ledger of deposit ID, principal, simulated
minimum ETH, transaction hash, actual ETH received, and custody transfers.

1. **Unwind to ETH.** The known depositor calls `retrieveFunds(id)` for each old ID 1–9. After each transaction,
   reconcile the deleted record and actual ETH received, update `YBOLD_EXPECTED_OLD_ACTIVE`, and rerun preflight. A
   failed Curve/Uniswap exit reverts that call without deleting the record. Transfer only the reconciled withdrawn ETH
   to the approved treasury custody address; verify the receipt and treasury balance independently. This is a custody
   transfer, not a `YieldManager` function, and requires its own authorized signer and transaction review.
2. **Hold and deploy.** The treasury holds the ETH while the release is prepared. Do not infer that the ETH is in the
   manager or available to the new adapter. Confirm all nine old records are gone and the preflight expected-old count
   is 0. Deploy and verify the reviewed yBOLD adapter only after Gate 2 approval; compare code, constructor graph,
   roles, salt, and predicted address. Set `YBOLD_VAULT` to the deployed address and rerun preflight.
3. **Switch protocol position.** Governance calls `setYieldVault(newAdapter)`. This retrieves only the protocol-owned
   Beefy position into the manager, zeroes manager principal, and selects the new **proxy**. Verify the manager's ETH
   delta and the old adapter's ≤120-share/≤150-value dust limits. Rerun preflight in this legitimate idle-ETH state.
   Then governance calls `depositPrincipalIntoYieldVault()` and verifies nonzero protocol principal, st-yBOLD shares,
   and no residual core-token approvals.
4. **Redeploy treasury ETH.** After a fresh live quote for each amount, treasury releases the agreed ETH to the known
   depositor, who calls payable `depositFunds()` in separately simulated tranches of their choosing. Do not assume a
   single transaction can pass the adapter's 50 bps execution bound: a separate fork stress test proves that a synthetic
   1,000 ETH single tranche reverts with Uniswap's `Too little received`. This is a risk-bound test, not a claim that
   the actual recovered user ETH would fail in one transaction. Tranches do not recreate the old records; each
   successful deposit gets a fresh 30-day lock. Reconcile treasury outflow, depositor receipt, each new deposit ID, and
   remaining treasury ETH after every tranche. Never exceed the ETH actually recovered from old withdrawals.
5. Verify `newAdapter.principalValue == YieldManager.principalValue + sum(active new deposit amounts)` and
   `newAdapter.principalShares == st-yBOLD.balanceOf(newAdapter)`. Resume intake only after all checks pass.

The test uses a stand-in treasury address solely to prove custody separation; it does not specify the live treasury
signer. There is no migration helper contract with temporary custody. Use protected execution where appropriate, but do
not rely on a multi-day private bundle or assume unchanged liquidity between stages.

## Normal incident procedure

1. Stop new off-chain intake and identify whether Yearn redemption, Curve, Uniswap, WETH, or oracle availability is
   failing. Record block, calldata, revert data, all active new deposit IDs/amounts/unlock times, manager protocol
   principal, adapter `principalValue`, `principalShares`, actual st-yBOLD balance, and proxy implementation slot.
2. Routine admin calls `pause()` and, only if the reviewed loss tolerance is needed, `setEmergencyMode(true)`. This
   freezes deposits and yield claims but deliberately leaves ordinary principal retrieval available. Re-simulate a
   normal exit; use it if it succeeds within approved bounds.
3. Do not change swap/peg/loss bounds merely to force a bad exit. Abort normal recovery attempts on stale/invalid
   oracles, output below policy, unexpected role/implementation changes, or accounting mismatch.
4. When dependencies recover, ordinary users still call `YieldManager.retrieveFunds(id)` after the existing 30-day lock;
   protocol principal uses `retrievePrincipalFromYieldVault()` or the retrieval embedded in `setYieldVault()`.

## Treasury recovery procedure

This path is irreversible through ordinary adapter functions once shares leave the proxy.

1. Obtain explicit incident approval from the recovery and governance signers. Independently prove
   `principalShares == stYBOLD.balanceOf(proxy)`,
   `principalValue == manager.principalValue + sum(active new-ID amounts)`, `recoveryState == Normal`, and the EIP-1967
   implementation/roles match the reviewed release. Abort on any mismatch, donation, missing record, unknown signer, or
   unexpected implementation.
2. Simulate `initiateRecovery()` at the intended block. The recovery authority calls it through the **proxy**. It pauses
   the adapter, enables emergency mode, snapshots all remaining principal, zeroes tracked shares, and transfers the
   exact snapshotted st-yBOLD shares to `recoveryTreasury`. Reconcile `RecoveryInitiated`, treasury balance delta,
   snapshot, shares, proxy balance zero, and frozen deposit/claim/ordinary-redemption behavior before proceeding.
3. The treasury liquidates or manages st-yBOLD outside Seba. This operation is not guaranteed to return par and is not
   proven by synthetic fork funding. Publish actual proceeds, fees, realized loss/gain, and the proposed settlement.
   Never pay depositors directly while their manager IDs remain claimable.
4. Select one final `settlementEth`. Its rate is `floor(settlementEth * 1e18 / principalSnapshot)` and is uniformly
   applied to user IDs and protocol principal. Disclose the resulting pro-rata loss/gain and rounding before signatures.
   The treasury calls `fundRecovery()` one or more times; only authenticated funding received through that function
   counts. Require proxy ETH balance and cumulative authenticated funding both cover `settlementEth`.
5. After independent funding reconciliation, the recovery authority calls `activateRecoverySettlement(settlementEth)`
   once. This fixes the rate permanently for that recovery. Abort before this call if funding, rate, disclosure,
   liabilities, or approvals differ. After activation, topping up or repricing is not part of the ordinary flow; a
   further proxy upgrade would be a new, separately reviewed governance action.
6. After their unchanged 30-day lock, original depositors call normal `YieldManager.retrieveFunds(id)`. The manager
   deletes the ID atomically, calls the proxy, receives fixed-rate ETH, and forwards that ETH to the depositor. A revert
   restores the ID. This preserves existing accounting and prevents treasury/direct double payment.
7. Governance settles protocol principal through `retrievePrincipalFromYieldVault()` or `setYieldVault()`. Claim order
   cannot change the fixed rate. Reconcile each `RecoveryPrincipalSettled`/`PrincipalRetrieved` event, deleted ID,
   manager/proxy ETH delta, `principalSettled`, and `ethPaid`.
8. Only after `recoveryState == Settled`, `principalValue == 0`, every affected ID is deleted, manager protocol
   principal is zero or switched, and paid totals match the fixed-rate ledger may recovery governance call
   `sweepRecoveryExcess()`. This returns only rounding dust or deliberately uncommitted excess to the treasury.

## Rollback limits

- Before `setYieldVault`, retry any failed old withdrawal after liquidity/oracle conditions recover. No accounting
  mutation survives a reverted call.
- After user withdrawals but before the switch, funds are with the known depositor until the independently approved
  treasury transfer, then held in treasury. Preserve transaction and balance proofs at each custody boundary; do not
  redeposit into the old adapter unless abandoning the migration.
- If `setYieldVault` fails, the manager remains on Beefy and protocol accounting rolls back.
- If protocol deposit into yBOLD fails, the manager holds ETH and the admin can retry or set the old adapter again. A
  rollback to Beefy is only reasonable before new user yBOLD deposits and after a fresh fork simulation.
- If a new user deposit fails, prior successful tranches remain valid and the failed ETH transfer/accounting reverts.
- Before `initiateRecovery`, pause/emergency changes can be reversed after dependencies recover. After share transfer,
  ordinary redemption cannot resume and the treasury must complete liquidation/funding or governance must approve a new
  implementation. After rate activation, the ordinary path cannot change rate or add settlement funding.
- Core WETH, USDC, BOLD, yBOLD, and st-yBOLD remain blocked from routine `rescueToken`. Nevertheless, UUPS upgrade
  governance can replace all logic and therefore can ultimately move every asset. Treat compromise of that authority as
  total strategy compromise.
- This mechanism protects only positions deposited into the new yBOLD proxy. It does not retrofit the deployed Beefy
  adapter, unblock old deposit ID 4, or recover value lost inside Yearn/BOLD before treasury custody.

## Post-migration monitoring

- Monitor the proxy implementation slot and `Upgraded`, role, pause, emergency, and recovery events. Alert immediately
  on any unplanned change.
- Check strategy share/value reconciliation, manager principal, active deposit records, and core-token allowances after
  every material step.
- Target weekly harvest evaluation, with daily monitoring. Execute only when expected unlocked yield exceeds gas and
  swap costs; there is no hardcoded quarterly cadence.
- Monitor Yearn shutdown/capacity/liquidity, st-yBOLD share price and reports, Curve BOLD peg/EMA and liquidity,
  Chainlink freshness, Cow intent age, pending conversion, pybSeba `totalAssets`, and role changes.
- Prove yield delivery by observing `YieldClaimed`, `YieldDistributed`, Cow settlement/finalization,
  `BoldConversionFinalised`, and pybSeba `Topup`, then reconcile BOLD/sBOLD/pybSeba deltas.

## Deployment and verification preview (Gate 2 only)

After explicit approval, first repeat one final simulation without `--broadcast`, compare all three CREATE2 addresses
and bytecodes, verify storage layout against the reviewed artifact, then use the project-standard command shape:

```bash
forge script script/DeployYBoldYieldVault.s.sol:DeployYBoldYieldVault \
  --rpc-url "$MAINNET_RPC" --account "$MAINNET_DEPLOYER_NAME" \
  --sender "$YBOLD_EXPECTED_DEPLOYER" --chain mainnet --broadcast --verify -vvvv
```

Verify `YBoldConfigValidator`, then `YBoldYieldVault` with the validator constructor argument, then the `ERC1967Proxy`
with implementation plus initializer calldata. Verification must use the exact compiler, optimizer, source commit, salt,
and constructor arguments from the successful simulation. Record the EIP-1967 slot and publish the proxy as the only
strategy address. The reviewed adapter storage occupies slots 0–19; the V2 preservation test appends its marker at slot
20 and proves all V1 configuration, roles, shares, and principal survive. Future implementations must append state after
slot 19 and must not reorder or extend the stored recovery struct in place. Do not execute this preview until Gate 2 is
approved.
