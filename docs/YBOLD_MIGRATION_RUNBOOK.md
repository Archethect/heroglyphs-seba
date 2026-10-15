# Beefy to yBOLD migration runbook

Status: implementation and fork simulation only. Approval Gate 2 prohibits deployment, broadcasting, source
verification, fund migration, or merging until explicit approval. A review PR is permitted; it does not authorize
deployment.

Open release blocker: the deployed YieldManager accepts only ETH from `retrievePrincipal`. If Yearn redemption, either
swap venue, or the required oracle is unavailable, the adapter has no safe in-kind user exit. Emergency mode only
relaxes bounded Yearn loss tolerance; it cannot bypass those dependencies. This needs an explicit architecture/risk
decision before deployment, not an operational claim that emergency exits are guaranteed.

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

The fresh fork snapshot is Ethereum block `26,196,493`: deposits 1–9 still belong to the known depositor and point
to the old adapter, but the staged unwind currently fails at deposit ID 4 with Curve's `Not enough coins removed`.
The failed transaction preserves that deposit and the old adapter's shares. **This is a release blocker:** there is
no successful full E2E migration proof at the fresh snapshot, and a historical success must not be treated as a live
execution quote. The complete staged-route test is pinned separately to historical block `25,831,161`; it leaves
119 old Beefy shares and 147 old principal-value units, within the fixed 120-share/150-value dust limits. These
bounds are release assertions, not permission to ignore a larger residual.

## Required tools and environment

- Foundry with Solidity 0.8.28.
- An archive-capable Ethereum RPC. A fresh fork of the intended execution block must pass the full migration route
  before Gate 2 can be considered; the currently pinned fresh block does not.
- An Etherscan API key only for eventual source verification.
- Controlled signers for the known depositor and a current `ADMIN_ROLE` holder.
- Transaction simulation and protected submission for value-moving steps. The custody, deployment, and redeposit
  stages are intentionally separate; they are not one atomic bundle.

Set, without printing secrets:

```bash
MAINNET_RPC=...
ETHERSCAN_API_KEY=...
YBOLD_EXPECTED_DEPLOYER=0x...
YBOLD_ADMIN=0xf83b11b09EEc073ACE4481b2F4c8357e156714b3
YBOLD_MIGRATION_ADMIN=0xf83b11b09EEc073ACE4481b2F4c8357e156714b3
YBOLD_VERSION_SALT=0x...
YBOLD_EXPECTED_OLD_ACTIVE=9 # change to the exact count before each preflight rerun
YBOLD_VAULT=0x... # omit before adapter deployment; set only to the deployed address afterward
```

## Dry run and fork proof

Run these before preparing signatures:

```bash
forge build
forge test --match-path 'tests/YBoldYieldVault/**/*.t.sol'
forge test --match-contract YBoldMigrationForkTest --fork-url "$MAINNET_RPC"
forge script script/DeployYBoldYieldVault.s.sol:DeployYBoldYieldVault --rpc-url "$MAINNET_RPC" -vvvv
forge script script/YBoldMigrationPreflight.s.sol:YBoldMigrationPreflight --rpc-url "$MAINNET_RPC" -vvvv
```

Do not add `--broadcast` or `--verify` before Gate 2 approval. The preflight script is read-only and prints exact
calldata for the current stage. Before adapter deployment, leave `YBOLD_VAULT` unset; after deployment, set it to the
verified address. Set `YBOLD_EXPECTED_OLD_ACTIVE` to the independently reconciled number of remaining old user deposits
on every run: 9 initially, decreasing after each successful withdrawal, then 0 before the strategy switch. With salt
`0x00…01`, deployer `0x888D…ab4f`, and admin `0xf83b…14b3`, the 2026-10-13 dry run predicted
`0x1bE31C869caCF38F595DDAF252F337744148E429`; this is not a current deployment approval. Any input, compiler
setting, or bytecode change requires a new reviewed prediction.

The historical E2E uses actual ETH recovered from old user positions for its two redeposit tranches. Its yield
harvest later injects synthetic Yearn profit/BOLD and refreshes oracle mocks; it does not prove live CowSwap solver
settlement. The 1,000 ETH rejection test also uses test-only capital. Neither substitutes for an execution-day quote.

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
9. The new adapter bytecode, constructor graph, roles, 50 bps swap limits, 100 bps peg limit, zero normal Yearn loss,
   and 100 bps emergency Yearn loss match the reviewed artifact.
10. No new `FundsDeposited`, Cow intent, role change, pause, Yearn shutdown, or material liquidity change occurred while
    signatures were prepared.

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
   Beefy position into the manager, zeroes manager principal, and selects the new adapter. Verify the manager's ETH
   delta and the old adapter's ≤120-share/≤150-value dust limits. Rerun preflight in this legitimate idle-ETH state.
   Then governance calls `depositPrincipalIntoYieldVault()` and verifies nonzero protocol principal, st-yBOLD shares,
   and no residual core-token approvals.
4. **Redeploy treasury ETH.** After a fresh live quote for each amount, treasury releases the agreed ETH to the known
   depositor, who calls payable `depositFunds()` in separately simulated tranches of their choosing. Do not assume a
   single transaction can pass the adapter's 50 bps execution bound: a separate fork stress test proves that a
   synthetic 1,000 ETH single tranche reverts with Uniswap's `Too little received`. This is a risk-bound test, not
   a claim that the actual recovered user ETH would fail in one transaction. Tranches do not recreate the old records;
   each successful deposit gets a fresh 30-day lock. Reconcile treasury outflow, depositor receipt, each new deposit
   ID, and remaining treasury ETH after every tranche. Never exceed the ETH actually recovered from old withdrawals.
5. Verify `newAdapter.principalValue == YieldManager.principalValue + sum(active new deposit amounts)` and
   `newAdapter.principalShares == st-yBOLD.balanceOf(newAdapter)`. Resume intake only after all checks pass.

The test uses a stand-in treasury address solely to prove custody separation; it does not specify the live treasury
signer. There is no migration helper contract with temporary custody. Use protected execution where appropriate, but
do not rely on a multi-day private bundle or assume unchanged liquidity between stages.

## Recovery and rollback limits

- Before `setYieldVault`, retry any failed old withdrawal after liquidity/oracle conditions recover. No accounting
  mutation survives a reverted call.
- After user withdrawals but before the switch, funds are with the known depositor until the independently approved
  treasury transfer, then held in treasury. Preserve transaction and balance proofs at each custody boundary; do not
  redeposit into the old adapter unless abandoning the migration.
- If `setYieldVault` fails, the manager remains on Beefy and protocol accounting rolls back.
- If protocol deposit into yBOLD fails, the manager holds ETH and the admin can retry or set the old adapter again. A
  rollback to Beefy is only reasonable before new user yBOLD deposits and after a fresh fork simulation.
- If a new user deposit fails, prior successful tranches remain valid and the failed ETH transfer/accounting reverts.
- During a Yearn liquidity incident, pause deposits/claims and enable emergency mode only after governance accepts up to
  1% Yearn redemption loss. Principal retrieval remains callable, but it can still revert if Yearn, Curve, Uniswap,
  WETH, BOLD, USDC, or Chainlink is unavailable. There is no in-kind exit through the deployed YieldManager.
- Old dust is known and accepted. Core WETH, USDC, BOLD, yBOLD, and st-yBOLD cannot be governance-rescued.

## Post-migration monitoring

- Check strategy share/value reconciliation, manager principal, active deposit records, and core-token allowances after
  every material step.
- Target weekly harvest evaluation, with daily monitoring. Execute only when expected unlocked yield exceeds gas and
  swap costs; there is no hardcoded quarterly cadence.
- Monitor Yearn shutdown/capacity/liquidity, st-yBOLD share price and reports, Curve BOLD peg/EMA and liquidity,
  Chainlink freshness, Cow intent age, pending conversion, pybSeba `totalAssets`, and role changes.
- Prove yield delivery by observing `YieldClaimed`, `YieldDistributed`, Cow settlement/finalization,
  `BoldConversionFinalised`, and pybSeba `Topup`, then reconcile BOLD/sBOLD/pybSeba deltas.

## Deployment and verification preview (Gate 2 only)

After explicit approval, first repeat one final simulation without `--broadcast`, compare the predicted CREATE2 address
and bytecode, then use the project-standard command shape:

```bash
forge script script/DeployYBoldYieldVault.s.sol:DeployYBoldYieldVault \
  --rpc-url "$MAINNET_RPC" --account "$MAINNET_DEPLOYER_NAME" \
  --sender "$YBOLD_EXPECTED_DEPLOYER" --chain mainnet --broadcast --verify -vvvv
```

Verification must use the exact compiler, optimizer, source commit, salt, and constructor arguments from the successful
simulation. Do not execute this preview until Gate 2 is approved.
