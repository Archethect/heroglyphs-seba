# Hoodi Phase 5 — Stage A review gate

This is the isolated, mock-backed Hoodi V1→V2 rehearsal only. It does not authorize or affect mainnet, the funded
chain-1 test stack, or the pre-existing apxETH Hoodi installation. Stage B is a separate approval after Stage A's actual
ETH output is measured.

## Read-only preflight (2026-11-13)

- The deployed source/receipt manifest and current code hashes still match. Hoodi Safe nonce is 13, sole owner is
  `0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f`, threshold 1, with no module or guard. V1 pool still points to V1
  manager; old manager has zero live supporter IDs, no conversion/order, no idle ETH, and an unchanged `2000e18` **mock
  basis**, not 2,000 ETH. The adapter holds `2000e18` mock Beefy shares. V2 remains disabled and empty. Recheck all
  these facts at signing time.
- Both fixed-price Hoodi feed reports are stale. Never call the old exit alone. The four-call Safe batch refreshes each
  report to its observed Hoodi block timestamp, deploys the immutable intake stopper with CreateCall/CREATE2, then calls
  V1 `setYieldVault(stopper)`. A failure in any call rolls back the whole batch.
- The isolated AWS rehearsal stack is `UPDATE_COMPLETE`; its full poller EventBridge rule is disabled and reserved
  concurrency is zero. Both Hoodi Goldsky graphs report healthy/synced. At block 4,006,601, hash
  `0xb1268ac2f139bc10f9958385f27b0811786ab8b4783e04a328077bd0fec8f6b7`, the independent graph/RPC parity check passed
  for V1 history and empty V2 ledgers with zero active legacy IDs.
- A fresh loopback Anvil fork of Hoodi block 4,006,658 executed the exact proposed Safe calldata successfully: 327,398
  gas used; one synthetic test ETH parked in the old manager; old adapter principal/shares zero; Safe nonce 14; pool
  still on V1; V2 still disabled. The receipt verifier independently matched the adapter's `PrincipalRetrieved` ETH
  output to parked ETH. This is **not** a public Hoodi transaction or evidence of a real Beefy exit.
- The Stage A planner tests and existing CI Node suite pass (102/102). Hoodi Foundry tests pass (27/27). No Solidity
  source or deployed runtime changed for this planner.

## Signing and receipt procedure

1. Immediately before signing, run `node tools/hoodi-public-stage-a-plan.mjs ../../../.env` in this contracts worktree.
   Its output must say `executionReady: true`, `chainId: 560048`, Safe nonce `13`, no live claims/order, and a
   successful `eth_call`/gas estimate. It is read-only and prints no RPC credential. Do not reuse a plan after 15
   minutes.
2. Review the four inner calls, the predicted stopper address, the outer Safe recipient, zero ETH value, entire
   `transaction.dataHash`, gas limit, and owner wallet. Use the outer `transaction.data` **only** for a direct
   owner-wallet call to the Hoodi Safe's `execTransaction`; do not paste that outer payload as an inner Safe Transaction
   Builder call. Confirm chain and calldata hash in the wallet/simulator. A new Safe nonce or any failed preflight
   requires regeneration and review, not a bypass.
3. After the owner submits the Hoodi transaction, run
   `node tools/hoodi-public-stage-a-verify.mjs ../../../.env <tx-hash>`. It checks the exact four-call payload,
   `ExecutionSuccess`, report age, deployed stopper code, zero adapter shares, old manager ETH equal to the adapter
   withdrawal event, Safe nonce 14, unchanged pool pointer, and V2 still disabled. If any check fails, stop.
4. Publish the actual Stage A receipt and fresh balances. Only then prepare a separately reviewed Stage B handoff using
   the **measured** ETH, residual inventory, approved caps, and a fresh complete Safe-batch gas simulation.

Abort if the backend starts financial maintenance, either graph lags/errors, a supporter claim or V1 order appears,
oracle refresh/exit simulation fails, code/roles/Safe policy drift, wallet has a pending transaction, gas is unsafe, or
the full calldata differs. A completed Stage A cannot be rolled back into the mock Beefy position merely by reverting
Stage B; ETH remains parked in the old manager while intake is stopped.
