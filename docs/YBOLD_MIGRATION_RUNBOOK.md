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

The reproducible fork snapshot is Ethereum block `25,831,161`. At that snapshot, deposits 1 through 9 belong to the
known depositor, point to the old adapter, and are unlocked. The manager has no pending BOLD conversion or open CowSwap
intent. The fork migration leaves at most 120 old Beefy shares and 150 old principal-value units; the observed result is
119 shares and 147 units. This accepted dust cannot be economically unwound through the old adapter.

## Required tools and environment

- Foundry with Solidity 0.8.28.
- An archive-capable Ethereum RPC.
- An Etherscan API key only for eventual source verification.
- Controlled signers for the known depositor and a current `ADMIN_ROLE` holder.
- A private bundle/simulation system capable of ordering transactions and keeping the migration out of the public
  mempool.

Set, without printing secrets:

```bash
MAINNET_RPC=...
ETHERSCAN_API_KEY=...
YBOLD_EXPECTED_DEPLOYER=0x...
YBOLD_ADMIN=0xf83b11b09EEc073ACE4481b2F4c8357e156714b3
YBOLD_MIGRATION_ADMIN=0xf83b11b09EEc073ACE4481b2F4c8357e156714b3
YBOLD_VERSION_SALT=0x...
YBOLD_VAULT=0x... # predicted/deployed adapter
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
calldata. With salt `0x00…01`, deployer `0x888D…ab4f`, and admin `0xf83b…14b3`, the 2026-10-13 dry run of this revised
adapter predicts `0x1bE31C869caCF38F595DDAF252F337744148E429`. Any input, compiler setting, or bytecode change must
produce and review a new prediction.

## Pre-migration inventory and abort conditions

Immediately before bundle construction, record block number and timestamp, then verify:

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

Abort on any mismatch, stale oracle, failed simulation, changed deposit ID, unexpected balance/dust, or output below a
signed minimum. The old adapter has no hard deposit pause; use an off-chain intake freeze and watch `depositId` until
the bundle lands.

## Exact private-bundle sequence

Before these steps, run the automator once if necessary to settle/cancel any Cow intent and require both pending fields
to be zero. Then submit in this order:

1. Known depositor calls `retrieveFunds(id)` for every ID 1 through 9. Each call is atomic; a failed Curve/Uniswap exit
   leaves that deposit record and old-adapter accounting unchanged.
2. Verify deposits 1-9 are deleted and reconcile ETH returned to the depositor against the old position exit simulation.
3. Governance admin calls `setYieldVault(newAdapter)`. This atomically retrieves protocol-owned principal from Beefy,
   zeros manager principal, and changes the active adapter.
4. Verify the manager holds the returned protocol ETH, points to the new adapter, and the old adapter is within the
   accepted 120-share/150-value dust bounds.
5. Governance admin calls `depositPrincipalIntoYieldVault()`. Verify nonzero manager principal, st-yBOLD shares in the
   new adapter, and zero residual core-token approvals.
6. The known depositor calls payable `depositFunds()` once per newly chosen tranche. Tranche count and sizes are the
   depositor's choice; they do not need to recreate the nine old records. Every new record receives a fresh 30-day lock.
7. Verify `newAdapter.principalValue == YieldManager.principalValue + sum(active new deposit amounts)` and
   `newAdapter.principalShares == st-yBOLD.balanceOf(newAdapter)`.
8. Resume intake only after all checks pass.

This is deliberately non-atomic across distinct authorized signers. Ordering, the off-chain freeze, private submission,
and per-step reconciliation bound the intermediate risk. There is no migration helper contract with temporary custody.

## Recovery and rollback limits

- Before `setYieldVault`, retry any failed old withdrawal after liquidity/oracle conditions recover. No accounting
  mutation survives a reverted call.
- After user withdrawals but before the switch, funds are held by the known depositor. Coordinate a later private
  bundle; do not redeposit into the old adapter unless abandoning the migration.
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
