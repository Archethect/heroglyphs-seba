# Hoodi Phase 4 — V2 staged, no migration

Status on 2026-11-12: **staging complete; Stage A/B not authorized or executed**. This is the isolated, mock-backed Hoodi V1→V2 financial rehearsal. The pre-existing apxETH Hoodi installation and all mainnet/production resources were left unchanged.

## Exact onchain checkpoint

The six owner-signed Safe batches in [HOODI_V2_STAGE_BATCHES.md](HOODI_V2_STAGE_BATCHES.md) succeeded and were checked for exact calldata, `ExecutionSuccess`, runtime code, proxy implementations, roles, and Safe nonces. The last batch is [0xf557…3ed8](https://hoodi.etherscan.io/tx/0xf557a12d01b12ae3aabf12f80f7c192cab891b44a2230c7e531ca25ca6243ed8), block **3,999,631**, hash `0x10ba2343544fedfdd3718cf48379c669c18ef2c18f75801f14596a0851e8c060`; Safe nonce is **13**. The complete receipt/code-hash chain is [HOODI_V2_STAGED_MANIFEST.json](HOODI_V2_STAGED_MANIFEST.json), linked to the exact bytes of the V1 manifest. Onchain contracts source is `e40e46cca58f5a63195848ae233a6e1f5deb2362`.

- V1 pool `0xB17e95B6f94c2028247be0Ab803f25fd19cfb679` **still points to V1 manager** `0x7743B769f61fACb3F90F9Ff2c17082350668a9BD`.
- V2 manager proxy `0x989F75ca5Ba3422b4392198cbc45C7Ec1587657A` is bound to the rETH and ysyBOLD vault proxies and the mock CoW module. Intake, execution, vault entries, and CoW execution are disabled. V2 custody, pending balances, and active orders are zero.
- V1 has zero live supporter claims and zero pending BOLD conversion. Its `principalValue=2000e18` is **synthetic mock V1 basis units, not 2,000 ETH**. No V1 funds were handed to V2.

## Backend and graph staging

The exact isolated AWS stack `HeroBoostBackendStackHoodiV1V2Rehearsal` was updated to the V2-aware, disabled artifact from backend commit `7b607d852ad07afbc8b43ef20a003619808e856f`. Read-only Hoodi preflight passed before and after deployment. The reviewed CDK diff changed only the disabled full-poller and manual-financial Lambda code plus `YIELD_V2_CONFIG`; it did not replace the state bucket, change EventBridge scheduling, or alter production stacks. CloudFormation finished `UPDATE_COMPLETE`. Post-deploy reads confirmed the full poller has **reserved concurrency 0** and its EventBridge rule is **DISABLED**. The V1 financial wrapper and bounded test quote endpoint remain available; V2 execution stays off.

Goldsky project `project_cmh1lybht009x5gp2fnth070b` hosts two **private, Hoodi-only** graphs: `seba-hoodi-v1-rehearsal/v0.0.1` and `seba-hoodi-v2-candidate/v0.0.2`. No existing mainnet graph or endpoint was changed. The first V2 candidate `v0.0.1` failed at the final `CowModuleConfigured` event: its manager data source lacked the CoW module ABI it bound in the handler. The subgraph manifest now declares that ABI, with a regression test; codegen/build passed and `v0.0.2` indexed beyond the checkpoint without errors. The failed `v0.0.1` was paused. The `v0.0.2` public endpoint returned HTTP 404; its authenticated private endpoint returned HTTP 200.

At the **same** block 3,999,631 and block hash, the independent graph/RPC parity checker reported:

```json
{"totalLegacyRecords":0,"activeLegacyIds":[],"onchainV1Verified":true,"onchainV2Verified":true,"cowOrders":0,"fullInvestedVerified":false}
```

The check compared both graph histories, pool/pybSeba state, active V1 claims, V2 manager/vault buckets and CoW module state against historical Hoodi RPC. The full offline subgraph tool suite passed **33/33**; the corrected graph also passed codegen/build and hosted indexing. This is a staged-state check, **not** proof that Stage A/B migration, CoW settlement, Rocket Pool investment, or ysyBOLD investment happened publicly.

## Stop gate

Do not change the pool manager pointer, execute the legacy handoff, enable V2 intake/execution, invoke the full validator poller, or point the backend at V2 until Stage A/B payloads and a separate approval are reviewed. The public CoW settlement and Yearn assets are mocks; real integration, pricing, and solver-fill risk remain governed by the fresh mainnet-fork rehearsal and release gates. The existing Hoodi apxETH installation remains separate.
