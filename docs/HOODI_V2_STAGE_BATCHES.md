# Hoodi V2 staging: six Safe batches, no migration

This is **Phase 4 only** of the isolated Hoodi rehearsal. The existing Hoodi apxETH stack and every mainnet/production
resource are out of scope. The V1 pool must continue to point at the V1 manager after all six batches. Do not start
Stage A or Stage B from this document.

The sole signer is the Hoodi admin EOA `0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f`, executing through the
already-verified 1-of-1 Hoodi Safe `0xAc52395a9D706696Cf36125A0664c0C6d2B06B7b`. Each transaction is `execTransaction`
sent **to the Safe**, with **0 ETH value** and one prevalidated owner signature. The Safe then calls the standard
CreateCall/MultiSend contracts. Do not send creation bytecode directly from Remix. Use the full generated calldata, not
a truncated chat transcription.

| Batch                 | Expected Safe nonce before | Contents                                                   | Local fork gas used |
| --------------------- | -------------------------: | ---------------------------------------------------------- | ------------------: |
| 0 `yearn-mocks`       |                          7 | BOLD→mock yBOLD→mock ysyBOLD                               |           1,376,539 |
| 1 `manager`           |                          8 | V2 implementation, initialized ERC1967 proxy               |           5,412,297 |
| 2 `reth-vault`        |                          9 | rETH vault implementation, initialized proxy               |           3,769,529 |
| 3 `ysybold-vault`     |                         10 | ysyBOLD vault implementation, initialized proxy            |           3,667,389 |
| 4 `executor-and-cow`  |                         11 | direct executor, mock CoW settlement, CoW intent module    |           5,868,034 |
| 5 `disabled-bindings` |                         12 | manager binds both vaults and disabled executor/CoW module |             350,704 |

These are **fork** gas observations at Hoodi block 3,999,532, not fixed public gas limits. The read-only planner
recomputes current `eth_call`, `estimateGas`, a 25% gas limit buffer, fee ceiling, owner balance and Safe/EOA nonces
immediately before each signature. It refuses wrong chain, nonce, owner/threshold/modules/guard,
Safe/CreateCall/MultiSend code hash, V1 state/code drift, occupied future CREATE2 addresses or mismatched prior runtime
hashes. A dirty source makes `executionReady=false`. Only sign after reviewing a clean, pinned source and the fresh
planner output.

The source planner is [`tools/hoodi-public-v2-next.mjs`](../tools/hoodi-public-v2-next.mjs); the exact-data receipt
verifier is [`tools/hoodi-public-v2-verify.mjs`](../tools/hoodi-public-v2-verify.mjs). Use the existing ignored local
file containing `HOODI_RPC`, or supply `HOODI_RPC` in the process environment; never print, commit or paste the
endpoint/key. From this contracts worktree:

```sh
node tools/hoodi-public-v2-next.mjs /absolute/path/to/ignored-hoodi.env 0
# After the owner signs batch 0, verify its transaction hash before planning batch 1:
node tools/hoodi-public-v2-verify.mjs /absolute/path/to/ignored-hoodi.env 0 0x<actual-hash>
```

Repeat with batch indices 1–5, **sequentially**. In Remix use Injected Provider on Hoodi chain `560048`, the admin EOA
account, `At Address` for the verified Safe, and the low-level interaction field for the **entire** `transaction.data`.
Do not use the EOA’s direct contract-creation UI. Compare `transaction.dataHash`, `transaction.to`, `valueWei=0`, gas
limit and Safe nonce before signing. A normal transaction receipt status alone is insufficient: require Safe
`ExecutionSuccess`, exact input bytes, the expected runtime hashes and the next Safe nonce from the verifier. If any
check fails, stop; do not skip a batch or retry old calldata blindly.

Before the first signature, the public V1 baseline must still be: pool manager
`0x7743B769f61fACb3F90F9Ff2c17082350668a9BD`, `depositId=0`, `principalValue=2000e18` **synthetic V1 basis units**,
`pendingBoldConversion=0`, Safe nonce 7, no EOA pending transaction. The mock Yearn tokens are 1:1 and the mock CoW
settlement is not a live solver. This public Hoodi stage proves wiring and indexing, **not** live Yearn/CoW fill quality
or mainnet asset recovery.

After batch 5, independently reconcile: all 11 runtime hashes and creation receipts; implementation slots for the three
proxies; Safe-only treasury; vaults bound to the manager; zero V2 protocol/supporter custody, pending ETH/BOLD and order
inventory; `intakeEnabled=false`, `executionEnabled=false`, both vault `entriesEnabled=false`, executor/module
`enabled=false`; and the unchanged V1 pool pointer and claims. Only then may a new `v2-staged` evidence manifest be
signed off for the isolated V2-aware backend and new dual-era Goldsky candidate. Keep the V1 backend and V1 graph
available during this stage. **Stop and report Phase 4 before any migration.**

Verification performed before public signing:
`node --test tools/hoodi-public-*.test.mjs tools/hoodi-safe-createcall.test.mjs` (17/17); full six-batch local
Hoodi-fork execution and exact receipt verification at block 3,999,532 (six `ExecutionSuccess` events, Safe nonce 7→13,
all switches disabled, pool pointer unchanged). `forge build` passed. The V2 Solidity suite ran 259 non-fork tests
successfully; eight mainnet-fork tests could not run in this Hoodi-only shell because `MAINNET_RPC` is intentionally
absent. Existing earlier mainnet-fork evidence remains separate and is not a current public Hoodi transaction.
