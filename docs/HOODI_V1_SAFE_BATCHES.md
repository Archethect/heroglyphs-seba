# Public Hoodi V1 Safe batches (testnet only)

The isolated 1-of-1 Hoodi rehearsal Safe is `0xAc52395a9D706696Cf36125A0664c0C6d2B06B7b`; its sole owner is
`0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f`. The successful bootstrap receipt is
`0x3ac6307b93523487a9d39c079801994e6363d445f13554483f6540279d31fdf6`. These instructions do **not** apply to mainnet,
the existing Hoodi apxETH installation, or any production service. No private key belongs in a terminal, repo, chat or
Remix file.

## Why these are Safe batches

The deployed Safe's sole EOA owner can call `execTransaction` directly with a prevalidated owner signature (`v=1`). The
official Hoodi Safe MultiSend delegatecall executes the six, five, three, three and seven zero-value calls below
atomically. No separate `approveHash` transaction or custom proxy is needed. This has been tested on a local Hoodi fork
anchored at the Safe-creation receipt. A local fork is evidence of EVM execution, not a guarantee about later live
state.

| Safe nonce | Batch            | Purpose                                                                                    | Local fork estimated gas |
| ---------- | ---------------- | ------------------------------------------------------------------------------------------ | -----------------------: |
| 0          | `dependencies-a` | Mock WETH, USDC, BOLD, sBOLD and two Safe-controlled test feeds                            |                3,348,996 |
| 1          | `dependencies-b` | Mock Uniswap, Curve, Beefy, harvester and EthFlow                                          |                2,421,591 |
| 2          | `core-a`         | Unchanged V1 ETH→BOLD router, PYBSeba and SebaPool                                         |                4,462,494 |
| 3          | `core-b`         | Unchanged V1 Beefy adapter, YieldManager and RocketPoolBackPay                             |                5,596,218 |
| 4          | `bindings`       | Set pool/PYB/manager pointers; grant manager roles and revoke bootstrap Safe manager roles |                  226,878 |

The V1 **core runtime** is the mainnet-era source, but Hoodi dependencies are mocks. For this isolated rehearsal the
Safe holds `ADMIN_ROLE` from each core constructor, rather than the mainnet Aragon authority; the EOA receives only the
test automator and mock-solver privileges. There is therefore no interim EOA `ADMIN_ROLE` to renounce. The Safe owns one
intentionally seeded PYBSeba dust share, as in the constructor. None of this reconstructs live mainnet balances,
external liquidity or supporter claims.

## Before signing each batch

From the contracts V1/V2 Hoodi worktree, run the read-only planner using the ignored local `.env` file and the exact
next Safe nonce, starting with `0`:

```bash
cd /Users/simon.deschutter/Projects/heroglyphs/hero_boost/.worktrees/seba-hoodi/contracts
node tools/hoodi-public-v1-next.mjs /Users/simon.deschutter/Projects/heroglyphs/hero_boost/.env 0 | jq '{executionReady,chainId,observedAt,signer,safe,batch,transaction:(.transaction | del(.data)),abortIf}'
```

The planner refuses the wrong chain, changed Safe policy/code, wrong Safe nonce, unexpected existing/missing V1 code,
unexpected runtime hashes in prior batches, an unsuccessful `eth_call`, insufficient gas balance or pending EOA nonce.
It prints no RPC URL, contains no signer and never sends. **Stop if `executionReady` is false**; it means the contracts
source tree is not pinned and clean. Re-run at the live head immediately before signing. The calldata is large, so never
retype it from chat. Copy only the generated full `execTransaction` calldata to the macOS clipboard:

```bash
node tools/hoodi-public-v1-next.mjs /Users/simon.deschutter/Projects/heroglyphs/hero_boost/.env 0 | jq -r '.transaction.data' | pbcopy
```

Change only the final batch index after the prior receipt has been checked. The full data hash shown in the summary must
match the bytes you submit. The transaction's recipient is always the rehearsal **Safe**, value **0 ETH**, and sender
the verified owner EOA. Use the fresh planner `gasLimit` as a ceiling; do not force a lower limit. A changed nonce,
recipient, amount, code hash, owner, gas availability or failed simulation is an abort, not a reason to edit calldata.
No mainnet RPC, wallet network or address is involved.

## Remix with browser wallet

1. In [Remix](https://remix.ethereum.org), use **Deploy & Run → Environment → Browser Extension** and verify that the
   wallet is on **Hoodi, chain ID 560048**, with account `0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f`.
2. In the Remix editor create a local `.abi` file containing the exact JSON in
   [`tools/hoodi-safe-raw.abi`](../tools/hoodi-safe-raw.abi). This is an interface-only file; **do not deploy it**.
   Select the file, then in Deploy & Run choose **Add Contract** at the existing Safe address above. Loading an existing
   address costs no gas.
3. Expand that attached contract under **Deployed Contracts → Low level interaction**. Set Remix **Value = 0 ETH**.
   Paste the full copied `transaction.data` into its **calldata** field, then inspect the wallet confirmation: sender,
   Hoodi chain, Safe recipient, zero ETH value and gas limit. The calldata begins with the Safe `execTransaction`
   selector, not the MultiSend selector. Do not use the **Deploy** button.
4. Before approving, compare the exact bytes with the planner output and its `transaction.dataHash`. If the wallet
   cannot show or preserve full calldata, stop and use a wallet path that can; do not infer correctness from a short
   preview. Submit **only one batch** and send its transaction hash back for read-only verification before the next.

Remix documents
[adding a contract from an ABI and Browser Extension](https://remix-ide.readthedocs.io/en/latest/run.html) and
[Low level interactions](https://remix-ide.readthedocs.io/en/latest/udapp.html). Remix UI labels may change; if the
attached ABI does not expose the low-level calldata field, stop rather than improvise another transaction route.

## Receipt gate

For each submitted transaction, verify chain 560048, `to` Safe, `from` owner, value 0, calldata hash equal to the
preflight, receipt status 1 and Safe `ExecutionSuccess` (receipt status alone can hide an inner Safe failure). Check
Safe nonce advanced by exactly one and all expected CREATE2 addresses hold the pinned runtime bytecode. Before moving
past nonce 4, also verify pool/manager/PYB pointers, manager-only router/adapter roles, Safe-only core admin and zero
manager deposits/principal/pending conversion. Only then proceed to isolated V1 backend and Goldsky graph. The read-only
receipt gate checks these facts for each submitted hash:

```bash
node tools/hoodi-public-v1-verify.mjs /Users/simon.deschutter/Projects/heroglyphs/hero_boost/.env 0 <Hoodi-transaction-hash>
```

All five public contract batches have now passed this gate. Their exact hashes, block evidence, deployed addresses and
runtime hashes are in [`HOODI_V1_PUBLIC_MANIFEST.json`](HOODI_V1_PUBLIC_MANIFEST.json). Safe nonce is 5; do **not**
replay any batch. The V1 financial lifecycle and backend/Goldsky release remain separate pending gates.
