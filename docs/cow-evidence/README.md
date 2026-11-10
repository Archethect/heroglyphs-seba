# CoW read-only viability evidence — 2026-11-10

This directory contains **research, not executable production orders**. No order was submitted, signature created,
approval sent, contract deployed, or funds moved.

## Reproduce

```sh
node --test tools/cow/probe-quotes.test.cjs
node tools/cow/probe-quotes.cjs
COW_RESEARCH_SIGNING_SCHEME=presign node tools/cow/probe-quotes.cjs
```

The probe only POSTs to the fixed public `https://api.cow.fi/mainnet/api/v1/quote` endpoint. Redirects are rejected. No
signing or transaction library is imported. Optional `COW_RESEARCH_OWNER`/`COW_RESEARCH_RECEIVER` are public addresses,
not keys. Defaults use the existing treasury Safe for research, **not the eventual escrow**.

The response validator checks pair, owner, receiver, appData, sell kind, no partial fills, ERC20 balance modes, signing
scheme, positive integer quantities, exact gross input = sellAmount + feeAmount, a fresh quote/deadline, a quote ID, and
`verified: true`. It does not manufacture a production minimum or authorize a risk pack. ERC1271
verificationGasLimit=200,000 is a **research estimate**, not a measured or approved production value.

## Observations

At 10:47:24–27 UTC, ERC1271-mode (`onchainOrder:false`) requests for 0.01, 1 and 100 units of WETH and rETH all returned
HTTP 200 and `verified:true`. Raw public requests/responses are in
[2026-11-10-erc1271-quotes.json](2026-11-10-erc1271-quotes.json).

| Gross sell budget |  API quoted BOLD buyAmount | Network fee (sell token) |
| ----------------- | -------------------------: | -----------------------: |
| 0.01 WETH         |      20.725916241314172687 |     0.000086290626955468 |
| 1 WETH            |   2,090.634208406415859042 |     0.000263583378381712 |
| 100 WETH          | 208,994.041335172138659771 |     0.000311887530696196 |
| 0.01 rETH         |      24.380639599440423701 |     0.000081407330680299 |
| 1 rETH            |   2,458.072578736583219486 |     0.000262781085851019 |
| 100 rETH          | 245,676.189480904359144132 |     0.000338313998592158 |

All six responses also report `protocolFeeBps:"2"`. Current official orderbook SELL-quote code already reduces
`buyAmount` for its volume protocol fee; do not automatically subtract it twice. Network `feeAmount` is separate and
denominated in the sell token. Exact gross spend in these responses is `sellAmount + feeAmount`. A production order's
signed fee/amount semantics must match the tested integration, not blindly copy a research quote.

PreSign-mode quotes at 10:44:02–05 UTC also returned `verified:true` for all six sizes. Their separate raw evidence is
in [2026-11-10-presign-quotes.json](2026-11-10-presign-quotes.json). Signing mode and verification gas affect fees.

**Important current API distinction:** `priceQuality:"optimal"` ranks promised prices without simulation.
`priceQuality:"verified"` is the current default and prefers simulation-verified prices. Initial optimal-mode responses
were unverified; switching the explicit request mode produced verified responses. Do not silently accept
`verified:false`.

A separate read-only Uniswap Quoter + Curve `get_dy` probe at mainnet block **26,383,996** (hash
`0x381e7dec6a600c5ca9e2a4f8c1be7bb078623c352d1d3182f7235f044406a4ff`, 10:44:59 UTC block timestamp) returned the
following BOLD estimates on the current fixed paths:

| Input    |   Fixed-path BOLD estimate |
| -------- | -------------------------: |
| 1 WETH   |   2,091.661449467271329335 |
| 100 WETH | 209,011.527170030580184241 |
| 1 rETH   |   2,459.222796827278955246 |
| 100 rETH | 245,629.365984139132206782 |

These are different-time snapshots and the fixed probe does not include full executor oracle checks or user gas. They
**do not prove CoW always beats the fixed route**, and none is a durable execution quote. The preliminary evidence
supports implementing/testing both CoW pairs; intended sizes, fees and live fill reliability remain gates. Very small
trades show material fee drag (~0.8% network fee at 0.01 input in this sample).

## Verified chain identities

Mainnet block **26,383,986**: `0xc5c0e921c19e4d597983137da0fd9f96269ef884aa0e89040ff91e66092869f4`, 2026-11-10 10:42:59
UTC. Public read-only RPC reported chainId=1.

- WETH `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`: symbol WETH, decimals 18, runtime 3,124 bytes.
- rETH `0xae78736Cd615f374D3085123A210448E74Fc6393`: symbol rETH, decimals 18, runtime 8,800 bytes.
- BOLD `0x6440f144b7e50D6a8439336510312d2F54beB01D`: symbol BOLD, decimals 18, runtime 6,591 bytes.
- Settlement `0x9008D19f58AAbD9eD0D60971565AA8510560ab41`: runtime 16,165 bytes.
- Settlement `vaultRelayer()` returned `0xC92E8bdf79f0507f65a392b0ab4667716BFE0110`: runtime 4,590 bytes.
- Settlement `authenticator()` returned `0x2c4c28DDBdAc9C5E7055b4C863b72eA0149D8aFE`.
- Settlement `domainSeparator()` returned `0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943`.

The official deployment list matches these CoW addresses. Settlement and relayer are non-upgradeable; the solver
allowlist/authenticator is upgradeable. Approve the relayer, **not a solver or settlement directly**. Read-only
historical `eth_call`, `eth_getCode`, and `eth_getStorageAt` at block 26,255,461 succeeded through
`https://eth.drpc.org`; publicnode's credential-free endpoint rejected archive calls.

## Settlement constraints that tests must preserve

- Positive sell and buy amounts, fixed receiver and appData, exact token pair, ERC20 balance modes and FOK sell
  semantics.
- CoW order `filledAmount` alone is not durable settlement evidence: invalidation sets it to max uint256, and authorized
  settlement interactions may clear expired-order storage back to zero. Preserve source accounting and isolated order
  custody; do not interpret a later zero as proof that no fill ever occurred.
- Cancellations race fills. Revocation/expiry cannot justify both refund and settled-output credit.
- ERC1271 must pin the exact order digest. A quote for the Safe does **not** prove that a new custom escrow signature
  implementation is accepted; the escrow does not yet exist on mainnet.
- API `verified:true` is provider simulation evidence, not orderbook acceptance or an actual live solver fill. Fork
  tests with local solver impersonation must remain labeled as such.
- WETH avoids repeated Eth-flow wrapping/refund custody. ERC1271/PreSign orders do not use CoW's fast path.

## TDD evidence for the probe

Command: `node --test tools/cow/probe-quotes.test.cjs`, Node v22.23.4.

1. RED before implementation: exit 1, `Cannot find module './probe-quotes.cjs'`; 0 passed / 1 failed.
2. GREEN after implementation: exit 0, **10 passed / 0 failed / 0 skipped**.
3. Added strict redirect-rejection assertion first: RED, 9 passed / 1 failed (`undefined !== 'error'`).
4. Added `redirect:"error"`: GREEN, **10 passed / 0 failed / 0 skipped**.
5. Real public API execution: exit 0; six ERC1271-mode responses passed the same validator with `verified:true`.

This is research-tool verification, not full onchain coverage or stack E2E evidence.

## Primary sources

- [CoW core deployment and security reference](https://docs.cow.fi/cow-protocol/reference/contracts/core)
- [Signing schemes](https://docs.cow.fi/cow-protocol/reference/core/signing-schemes)
- [Native tokens / recurring WETH versus Eth-flow](https://docs.cow.fi/cow-protocol/tutorials/cow-swap/native)
- [Fast-path limitations for contract orders](https://docs.cow.fi/cow-protocol/concepts/order-types/fast-path-orders)
- [Current quote request/response schema](https://github.com/cowprotocol/services/blob/main/crates/model/src/quote.rs)
- [Current protocol fee adjustment](https://github.com/cowprotocol/services/blob/main/crates/orderbook/src/quoter.rs)
- [Settlement fill/invalidation/storage behavior](https://github.com/cowprotocol/contracts/blob/main/src/contracts/GPv2Settlement.sol)
- [PreSign and ERC1271 validation](https://github.com/cowprotocol/contracts/blob/main/src/contracts/mixins/GPv2Signing.sol)
