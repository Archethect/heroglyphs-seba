# Hoodi Phase 6: public V2 protocol-leg investment

On 2026-11-13 the **isolated** Hoodi V1→V2 financial rehearsal invested both previously imported 0.5 ETH protocol legs.
This did not alter the pre-existing Hoodi apxETH stack or any mainnet/production resource. The V2 manager, vaults, Safe,
and dependencies are pinned in [`HOODI_PHASE5_CUTOVER_MANIFEST.json`](HOODI_PHASE5_CUTOVER_MANIFEST.json).

| Step               | Hoodi receipt                                                                                                   | Result                                                                                                                                                                           |
| ------------------ | --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Safe configuration | [0x99b0…5bd8](https://hoodi.etherscan.io/tx/0x99b0fa0b4e1e044db0ffca96ea63706e3226f5536579998152897d3ac4f45bd8) | Exact simulated 11-call batch; Safe nonce 16→17; capped executor/CoW, native entries, and manager execution enabled; separate V2 operator authorized. No protocol capital moved. |
| Operator gas       | [0xac79…cce8](https://hoodi.etherscan.io/tx/0xac7944cb4510fcdd195017c79bff90ebd3b237e22ab043335e669169317bcce8) | Admin EOA intentionally sent 1 Hoodi ETH to dedicated operator `0x15d16F4783e41c865C324d39170D00EED1f27770`; this is gas funding, not protocol principal.                        |
| rETH investment    | [0xad6d…817f](https://hoodi.etherscan.io/tx/0xad6d005c2fb7ab114400d1d7b14e10883a112cf456dd30da64a2c3c53383817f) | Backend spent the rETH leg's 0.5 ETH through real Hoodi Rocket Pool at block 4,007,740.                                                                                          |
| Open order         | [0x1821…8c2e](https://hoodi.etherscan.io/tx/0x1821e949c13d7f3e732df2ee4fb9b4985f891d1b37587dd3446d30be19938c2e) | Backend isolated the ysyBOLD leg's 0.5 WETH in one source-1 escrow, minimum 990 synthetic BOLD.                                                                                  |
| Synthetic fill     | [0x135e…b2cc](https://hoodi.etherscan.io/tx/0x135e3977e1f3bb3c3fdccf63a6e269c5eb0e89cb8d32fa2946ee6495f52db2cc) | Admin EOA, the immutable mock solver, spent the escrow WETH and minted 1,000 mock BOLD.                                                                                          |
| Finalize order     | [0x692c…7d89](https://hoodi.etherscan.io/tx/0x692c61eb0dacb2c4e1e457d687c992d9a236308ef10bff303bc4499c3f1b7d89) | Backend closed the fully filled order and attributed 1,000 BOLD only to protocol principal.                                                                                      |
| ysyBOLD investment | [0xc754…3c21](https://hoodi.etherscan.io/tx/0xc7546d62b3f4c533e9afb02ea36aca0f329123c903df6b36d5354ed7154d3c21) | Backend deposited that BOLD into the mock Yearn path and credited 1,000 ysyBOLD shares/basis to the protocol bucket at block 4,007,762.                                          |

At final block **4,007,762** (`0x652c05f43fc91f11f1fe934b99a69269de28cb13339d14274ec7e41fcef071f7`): the rETH protocol
bucket held `481431536185306049` rETH wei with `499749999999999999` wei recognized ETH basis; the ysyBOLD protocol
bucket held `1000e18` shares and `1000e18` yBOLD basis. Both match exact vault token balances. Supporter buckets,
pending manager ETH/BOLD/sBOLD, manager ETH, escrow WETH/BOLD, and active orders were zero. A third manual backend
invocation returned `no-op`, with no duplicate transaction.

Read-only receipt and token-balance checks passed. The private Goldsky V1/V2 graphs matched the chain at the exact final
block, including both buckets and the filled/accounted order; the subgraphs worktree preserves the hash-linked public
evidence and full-invested parity command in `tools/hoodi-replay/README.md`. The Hoodi fork migration suite passed 9/9
tests, and the isolated backend unit suite passed 81/81. The public sequence was **rETH first**; the older local-only
backend protocol probe assumes ysyBOLD first and must not be cited as proof of this public order.

This is a mock-backed testnet wiring test, **not** proof of a live CoW solver fill, BOLD/ysyBOLD mainnet liquidity, real
Yearn economics, or a loss-free migration. Public supporter deposits/withdrawals and validator/backpay processing were
not exercised here; their fork tests and release gates remain separate. The full Hoodi validator poller stays disabled
with reserved concurrency zero. No mainnet deployment or fund movement occurred.

## Follow-up fork drills; no public transactions

At public Hoodi block **4,008,210** (`0x36ef344bf31f0d1cfed95f52eeb129f44caf36266f14026935267a006b553b55`),
`tests/hoodi/publicstate/Phase6Drills.t.sol` forks the exact deployed V2 proxies and dependencies. Four tests pass: real
Hoodi Rocket Pool mint into an rETH supporter position plus synthetic Yearn ysyBOLD supporter entry and post-lock native
exits despite entry pauses; a reward order that cannot finalize early and returns its exact ETH source after expiry; a
separately mock-filled reward order that completes an sBOLD donation without crediting protocol BOLD; and same-token
ysyBOLD recovery with fully funded fixed budgets at a deliberate 50% loss. The recovery test checks unauthorized
initiation, underfunding, the original user lock, protocol/user claim closure, and no second user claim. Safe actions in
these tests use Foundry impersonation, and test users are locally funded. They do not prove a signed public Safe
operation or create public supporter positions. The pre-existing nine-test Hoodi migration/failure suite, backend
81-test Hoodi unit suite, and subgraph 44-test mapping suite also pass. Public supporter positions, reward donation
receipts, and a destructive public recovery drill remain separate decisions; this report does not mark all of Phase 6
complete.
