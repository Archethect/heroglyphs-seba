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
