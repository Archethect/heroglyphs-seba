# Hoodi Phase 5 — Stage B review gate

This is **only** the isolated mock-backed Hoodi test stack. Do not use these addresses or calldata on mainnet, the
funded chain-1 test stack, or the pre-existing apxETH Hoodi installation. Stage A has already completed in
[transaction `0xf5e4…43c3f`](https://hoodi.etherscan.io/tx/0xf5e4a64426f442463477b9fcd8411a3ec54cc04b1b25a44e70e53cfd84243c3f).
One **test ETH** is parked in the old manager. The 2,000e18 mock Beefy shares redeemed are **not** 2,000 ETH.

## Exact approved snapshot

The byte-exact [Stage B approval manifest](HOODI_PHASE5_STAGE_B_MANIFEST.json) pins the Stage A receipt and block, the
subsequent state checkpoint, V1/V2/Safe identities, zero live old deposit IDs, **1,000,000,000,000,000,000 wei** to
import, 50/50 rETH/ysyBOLD investment assignment, and four **zero** approved residual-surplus caps. Its keccak256 UTF-8
byte hash is `0x178ad989af6fbe81a3651e7f84618c538ff992d3a2a4927a0ec84d11b6237c9d`. The handoff constructor and V2
`armLegacyImport` must both commit to this hash. No residual BOLD, sBOLD or router ETH is included in the import.

The owner signer is `0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f` on Hoodi chain 560048, executing through the 1-of-1
test Safe `0xAc52395a9D706696Cf36125A0664c0C6d2B06B7b`. The owner EOA alone is **not** an onchain admin of the cutover.
Never share its private key. The full backend poller schedule and reserved concurrency must remain disabled/zero; the
two dedicated Hoodi Goldsky graphs must remain healthy. Neither public test proves real CoW solver liquidity, Yearn
redemption, or production migration economics.

## Prepare and sign in two transactions

1. With clean reviewed source, run `node tools/hoodi-public-stage-b-plan.mjs ../../../.env` in this contracts worktree.
   It is read-only. The result must say `executionReady: true`, chain 560048, Safe nonce **14**, exact 1 ETH, all zero
   residual caps, and a successful `eth_call`/gas estimate. The plan uses a one-hour handoff expiry from its observed
   Hoodi block. **Do not reuse an expired plan** or a plan after a changed Safe nonce, state, identity, or checkpoint.
   The observed fork deployment gas was **3,242,561**, with a public preflight estimate around **3,450,882** before the
   25% gas margin; re-estimate each time.
2. Separately review the plan's `approvalManifestHash`, `configurationHash`, CREATE2 `expectedAddress`, expiry, owner,
   Safe, inner `CreateCall` target, outer `transaction.dataHash`, zero ETH value, and gas limit. For a direct
   owner-wallet call in Remix, use the plan's **outer** `transaction.to` (the Safe), `transaction.valueWei = 0`, and the
   complete outer `transaction.data` in low-level interaction. This is **not** an inner Transaction Builder payload.
   Confirm Hoodi chain in the wallet. The Safe deployment must produce `ExecutionSuccess`, nonce **15**, exact predicted
   handoff code and configuration hash. Submit the receipt hash for independent verification **before** attempting the
   cutover.
3. After the handoff deployment is verified and source-verified, run
   `node tools/hoodi-public-stage-b-exec-plan.mjs ../../../.env <saved-deployment-plan.json> <deployment-tx-hash>`. This
   independently reconstructs the exact constructor and CREATE2 calldata, checks the successful Safe receipt, verifies
   the handoff source on Hoodi Etherscan, repeats all live-state checks, and simulates the **complete** seven-call Safe
   batch at the current block. The batch must be: V2 `armLegacyImport(handoff, 1 ETH, expiry, manifest)` → handoff
   `assertPreMigration()` → V1 `setYieldVault(handoff)` → V1 `depositPrincipalIntoYieldVault()` → V2
   `setIntakeEnabled(true)` → pool `setYieldManager(V2 proxy)` → handoff `assertPostMigration()`. Every inner call is a
   zero-value CALL within one standard Safe MultiSend delegatecall. A failed Stage B leaves Stage A's parked ETH in V1.
4. Only after separate review/approval, sign the exact Stage B outer Safe transaction. Run
   `node tools/hoodi-public-stage-b-verify.mjs ../../../.env <saved-cutover-plan.json> <cutover-tx-hash>` to verify
   `ExecutionSuccess`, both handoff boundary events, one `LegacyPrincipalImported`, old manager ETH **zero**, V2 ETH **1
   ETH**, `pendingEth(1) = 0.5 ETH`, `pendingEth(2) = 0.5 ETH`, `pendingEth(0) = 0`, pool pointer V2, V2 intake enabled,
   V2 execution disabled, Safe nonce **16**, and all unmigrated residuals **zero**. Then reconcile the Hoodi V1/V2
   subgraphs to the receipt before changing backend/graph consumers. This still does not invest the two pending ETH
   buckets or enable automated execution.

Abort if any pinned code, proxy binding, Safe policy, owner pending nonce, live V1 claim/order, parked ETH, residual
cap, V2 empty-state invariant, graph health, or backend-disabled gate changes; if either simulation fails; if expiry is
near; or if calldata differs from the reviewed plan. Do not widen caps, skip assertions, or use mainnet/funded-chain
credentials to make the batch pass. A new handoff requires a new Safe review.

## Public Hoodi handoff deployment receipt (2026-11-13)

- [Safe transaction `0x95fd…c506`](https://hoodi.etherscan.io/tx/0x95fdf64d322dcbfbb8b75d8a53dce3574068d98dc7797c0239edf02ac97ac506)
  succeeded at block **4,007,290**, hash `0x3c98844b8e85de0c9e4b84b80ba1362e098a0cf8aa11bca8bf28d363f10a448a`. It
  matched the saved outer Safe calldata byte-for-byte, emitted `ExecutionSuccess`, and advanced Safe nonce to **15**.
  The predicted
  [handoff at `0x4909…eBD6`](https://hoodi.etherscan.io/address/0x490956f3750780613fb96190cb2b63ae7121ebd6#code) exists
  and its exact Solidity 0.8.28/IR/optimizer-200 source is verified.
- The immutable `CONFIGURATION_HASH` is `0xbf2639191d1c0dd39dbc5589a7e7a2db899785df2c6f326497eddd095e6d50e3`; the
  manifest commitment remains `0x178ad989af6fbe81a3651e7f84618c538ff992d3a2a4927a0ec84d11b6237c9d`. Its expiry is
  **2026-11-13 12:09:36 UTC**. The deployment moved **no ETH**. One test ETH remains parked in V1 until the separately
  signed seven-call cutover.
- At block **4,007,300**, the independent public Hoodi preflight read the exact deployment receipt/source and current
  V1/V2 accounting, then `eth_call`-simulated the full Safe cutover successfully. Estimated cutover gas was **783,200**,
  with a **979,000** gas-limit plan. This is a simulation, not a cutover receipt; recheck immediately before signing.

## Public Hoodi Stage B cutover receipt (2026-11-13)

- [Safe transaction `0x87c3…bbff`](https://hoodi.etherscan.io/tx/0x87c31363ced1aaba63c62292724d8f70acfd8ea05d113d1c40d3a54f9fb0bbff)
  succeeded at block **4,007,357**, hash `0xe586856f1771dc1b15815930cbfd9153e61faf1be1e46d6a5d25909bca3a1b4d`. The exact
  seven-call outer Safe calldata matched the reviewed plan. `ExecutionSuccess`, the handoff pre/import/post events, and
  one V2 `LegacyPrincipalImported` were independently verified. Safe nonce advanced to **16**.
- The old manager holds **0 ETH** and has no live supporter IDs. The V2 manager holds **1 test ETH**:
  `pendingEth(1) = 0.5 ETH` for the rETH protocol leg and `pendingEth(2) = 0.5 ETH` for the ysyBOLD protocol leg.
  `pendingEth(0) = 0`; the pool points to the V2 manager proxy, V2 intake is enabled, and V2 investment/harvest
  execution remains **disabled**. All four disclosed unmigrated-surplus balances are zero. This is a mock-backed Hoodi
  cutover, not evidence of real market settlement.
- Both dedicated Hoodi Goldsky graphs were healthy and indexed beyond block 4,007,357. Exact-block graph/RPC parity
  passed for the V1 pool/PYB state and V2 manager/vault/CoW state: zero live legacy records or IDs, zero CoW orders, no
  indexing errors. The parity helper now queries logs in bounded ranges because the dedicated Hoodi Alchemy endpoint
  rejects requests spanning more than 10,000 blocks. `fullInvestedVerified` remains **false**: the imported ETH is
  assigned, not yet invested in rETH or ysyBOLD.
- **Do not treat the public rehearsal as finished.** Backend/graph consumer cutover and both protocol investments remain
  separate gated steps. The isolated AWS full poller stays disabled until those steps are reviewed; no mainnet or
  funded-chain-1 resources are changed.

The byte-exact [Stage A manifest](HOODI_PHASE5_STAGE_A_MANIFEST.json) and
[cutover manifest](HOODI_PHASE5_CUTOVER_MANIFEST.json) record the public receipts and checkpoint hashes. Their
respective Keccak-256 file hashes are `0x28af8e0bcd84aac3beb5ed29534e1836dd20aef01ae43d51df1c97daf41efe15` and
`0x70716b0574e0504db5e0c2a7911389f051da109275863120cc8a40b1d4cc48b5`; the latter names the former as its
`previousManifestHash`. The backend's read-only Hoodi evidence verifier accepted this chain and the onchain Stage A/B
receipts. This verifies the cutover, not completion of V2 investments or backend release.

## Verification evidence so far

- Stage B planner/verifier unit tests: **5/5**; all Hoodi planner tests: **31/31**.
- Hoodi Foundry tests with the ignored `HOODI_RPC`: **27/27**. Running `forge test` without loading the RPC fails the
  three fork suites for missing `HOODI_RPC`; that is an environment failure, not a passing test.
- A fresh private Anvil fork at Hoodi block **4,007,185** executed the exact proposed handoff deployment and seven-call
  cutover, including both public-facing planners and the receipt verifier. It used **3,242,561** gas for deployment and
  **754,540** gas for cutover; Safe nonce reached 16, old ETH zero, V2 ETH 1 ETH, each pending investment bucket 0.5
  ETH, zero residual surplus, V2 intake enabled and execution disabled. This is **fork-only** evidence, not a public
  Hoodi Stage B receipt.
- The dedicated Hoodi Goldsky-to-RPC parity check passed at the Stage A block; the isolated AWS rehearsal stack is
  `UPDATE_COMPLETE`, its full-poller EventBridge rule is `DISABLED`, and the full-poller Lambda has reserved concurrency
  `0`.
