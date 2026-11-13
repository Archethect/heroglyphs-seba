# Hoodi V1→V2 phase-2 security review (10 November 2026)

## Scope and method

This is an AI-assisted review, not a professional audit or a guarantee of safety. It freezes the following source
commits, before any fixes from this review:

| Repository | Commit                                     | Scope                                                                                                                                                               |
| ---------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Contracts  | `8e31a73595539f098b7274521ae209db3efd5dd6` | All 38 in-scope production Solidity files (5,644 source-bundle lines), including retained V1 contracts, V2 vaults/manager, CoW module/escrow and two-stage handoff. |
| Backend    | `486c21b765b6081c3df95cfd2b6478a4db4911b0` | Hoodi release/evidence gates and V1/V2 financial maintenance.                                                                                                       |
| Subgraphs  | `78b80e2859d3abe3561b3bb184ebccc70bced098` | Mainnet/Hoodi V1/V2 mappings and Hoodi replay parity.                                                                                                               |

The contracts review used
[Pashov's Solidity auditor v4.1](https://github.com/pashov/skills/tree/eacfc09b365d2697b83355909d0300607e596ffc/solidity-auditor)
at `eacfc09b365d2697b83355909d0300607e596ffc`: three passes, each with all 12 specialist lenses. The source bundle's
SHA-256 was `6b4db937e9111126852c2390ec0b52278092d815a265578af3e3b0a0124d26c1`. Runtime concurrency permitted three
specialists at once, so each pass ran in batches rather than the upstream simultaneous-agent arrangement. Passes 2 and 3
were explicitly given previous observations to seek distinct findings. A separate EthSkills general/precision checklist
cross-check found no additional substantiated V2 issue. The older `audits/v2-cow-pashov-20261110.md` reviewed a
different commit and had only 11/12 specialists in pass 2; it is not evidence for this frozen head.

Independent backend and subgraph reviews were read-only and ran targeted suites (backend 85/85, subgraph 32/32). These
are not a 36-specialist Pashov audit of TypeScript/AssemblyScript. No Daybreak run was available to this review. No
production transaction, testnet deployment, fund movement or merge occurred. Live mainnet role membership and current
balances were **not** reverified in this review: the local RPC client crashed and direct HTTP could not resolve the
Alchemy host in the sandbox. The 23 October baseline records a backend automator role on the deployed pool/manager, but
release must refresh this onchain.

## Material findings and leads

1. **High, privileged-key exposure retained from deployed V1:** `SebaPool.graduateValidator` accepts caller-chosen
   recipient and unbounded attestation points from `AUTOMATOR_ROLE`; `PYBSeba.distributeShares` mints that many
   redeemable shares. A compromised role holder can drain nearly all existing sBOLD backing by minting excessive shares
   to itself and redeeming. This is not an unprivileged V2 exploit. SebaPool and pybSeba remain deployed and
   authoritative after the V2 YieldManager cutover, so this is **not** a temporary migration risk. The user explicitly
   accepted this continuing legacy authority on 10 November 2026 and requested no V1 contract change. The V2 backend is
   being changed to use a separate signer, but the mainnet scheduled Lambda still has access to both secrets; this
   prevents accidental signer reuse, not compromise of the shared runtime.
2. **High migration/accounting exposure retained from deployed V1:** `EUSDUSDCBeefyYieldVault.retrievePrincipal`
   computes shares for a manager's fixed-value claim from current Beefy PPS despite shared principal shares. After a PPS
   fall, an early claimant can consume shares backing later claims; two equal 100-share claims at half PPS can leave the
   second with zero shares and a divide-by-zero exit. After a PPS rise, exit/harvest order can leave economically
   material unclaimed adapter shares. The handoff accepts exact-snapshotted adapter residue without attributing it to
   users versus protocol. V2 cannot repair deployed V1 accounting. The release must reconcile all live claims and
   residue, not label an unexplained value as dust. The PPS-rise numerical example is code-traced; reproduce against
   fresh fork state before assigning a live amount.
3. **Migration readiness gap:** `LegacyProtocolPrincipalHandoff._destinationReady` does not reject an already-recovering
   destination vault. A Safe mistake can import legacy ETH but block investment in that leg until recovery; Safe buffer
   recovery remains possible. Add an explicit normal-state preflight and negative test before cutover.
4. **Known snapshot/gas constraints:** Public transfers can change old-manager ETH or old-adapter/router residuals and
   invalidate the exact Stage B snapshot. The approved Safe batch arms and imports atomically, so no attacker can
   interleave _after_ arming in that prescribed path. Pre-batch drift requires fresh approval; independently arming
   outside the batch can strand a one-shot candidate. The legacy historical-ID scan is linear and needs a fresh
   actual-state Safe-batch gas simulation. Existing user claims must be closed before cutover, as approved.
5. **Accepted CoW trust/liveness assumption:** V2 uses the V1-style offchain quote/minimum model. A compromised operator
   or bad quote can set a poor positive minimum within per-order caps; there is no independent onchain fair-value or
   cumulative limit. Fork settlement proves mechanics, not live orderbook acceptance or solver fill reliability. Keep
   CoW execution disabled until live order-format acceptance, quote policy and alerting are approved.
6. **Backend release integrity:** Hoodi manual `maintain-v2` returns only `invoked` when summary mode is `execute`, even
   if individual actions failed or remain pending; per-action hashes/errors are hidden. Hoodi Stage A/B evidence accepts
   any matching successful receipt plus current pool pointer, without proving the intended handoff/import events or
   exact capital. Both need failing tests, a narrow fix and real receipt/replay proof.
7. **Subgraph release integrity:** A CoW module configured before `CowModuleConfigured` is dynamically indexed can leave
   its indexed enable/cap state falsely zero. The current Hoodi sequence binds first, but the mainnet bootstrap does not
   enforce that order. Hoodi V1 parity checks permanent deposit records but omits active `YieldDeposit` and
   `LegacyVaultLedger` state. These need a replay mutation test and either enforced bind-before-configure or state-read
   initialization plus a release gate. The legacy `totalYieldBearing` scalar only follows the current vault and is not a
   cross-vault source of truth if live old-vault claims remain.
8. **Legacy exit liveness:** The old Beefy exit still depends on fresh ETH/USD and USDC/USD oracle reads; switching the
   current vault does not change old deposits' `vaultAtDeposit`. No current oracle outage was established. V2 in-kind
   exits do not use that path.

Pass 3 found no distinct additional issue. “No additional issue found” is not proof of absence. The findings above
describe the frozen pre-fix heads; the disposition below records subsequent changes and verification separately.

## Post-fix disposition

| Finding                                 | Disposition on the changed worktrees                                                                                                                                                                                                                                                                                      |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1, retained graduation authority        | Explicitly accepted by the user as a continuing legacy risk after cutover. No V1 source or test change. V2 uses a distinct operator key, but the mainnet scheduled Lambda can still read both secrets; this is not runtime isolation. Refresh actual roles and signer identities before release.                          |
| 2 and 8, deployed Beefy accounting/exit | No V1 change. Zero live claims, exact adapter-share and ETH reconciliation, and a working current-block exit remain hard Stage B gates. Do not classify unexplained residue as harmless dust.                                                                                                                             |
| 3, V2 recovery readiness                | Fixed: preflight and import reject either destination vault outside `Normal`; postassertion rejects a recovery transition within the prescribed atomic Safe batch. Red/green unit tests cover both legs and all non-normal states; a pinned mainnet-fork Safe-batch regression covers Stage B. No storage slot was added. |
| 4, snapshot drift/gas                   | Existing exact-snapshot design retained. Reapprove drifted values and simulate the complete actual-state Safe batch, including the linear legacy-ID scan, before signing.                                                                                                                                                 |
| 5, CoW quote/solver liveness            | Existing V1-style quote/minimum policy retained by explicit user direction. No live orderbook fill or fair-value guarantee is claimed; keep execution disabled until acceptance and caps are approved.                                                                                                                    |
| 6, backend release evidence             | Fixed: per-action V2 status/hash reporting, receipt-emitter/event/amount validation for Stages A/B, and separated V2 signer loading/IAM for the isolated Hoodi manual Lambda. Independent review found and retested a read-only-staging signer-loading bug before closure.                                                |
| 7, subgraph bootstrap/parity            | Fixed: mainnet dynamic binding seeds current CoW caps/flag from onchain getters; Hoodi must bind before configuration and fails closed otherwise. Active V1 claims and ledger totals now reconcile to permanent records; CoW caps/flag compare to RPC state. Mutation and Matchstick regressions pass.                    |

Verification on changed worktrees: the exact CI Foundry suite excluding Hoodi passed **456/456**; the separate Hoodi
fork suite passed **22/22**. The V2 unit/fork subset passed **305/305**; fresh mainnet migration passed **8/8** at
snapshot block 26,385,980 (parent hash `0xb25c236943bc9bba1c41c36dda82464e41c4790b65096499adc70905d94ea647`), importing
1,533,727,945,293,608,179 actual wei without synthetic capital. The exact CI-profile coverage gate reports **100% lines,
branches and functions for all ten V2 onchain targets**, the Hoodi mock target and the V2 deployment-script target; the
read-only tooling suite passed **98/98**. An earlier broad run had 475 passes and one transient RPC DNS setup failure in
`RecoveryStackForkTest`; that suite passed separately **3/3** on retry, and the subsequent complete CI split passed.
Backend build and both scoped lints pass; Hoodi unit tests **77/77** and V2 Jest tests **280 passed, four local-fork
cases skipped**, with 100% coverage only for the configured V2 source set. Subgraph mainnet codegen/build and Matchstick
**44/44**, plus replay/manifest Node tests **33/33**, pass. Independent targeted post-fix reviews found no further
concrete V2 issue. These checks are not a fresh 36-specialist Pashov run on the changed heads, a professional audit,
public Hoodi replay, or live CoW settlement proof.

A final Slither scan emitted 31 V2 detector entries, including three High `arbitrary-send-erc20` pattern alerts. An
independent read-only triage checked every entry against its caller, fixed token/recipient, exact balance delta and
reentrancy guards, and found no concrete exploitable V2 path. The scan is **not** warning-free: these findings are
retained as reviewed static-analysis output rather than silently excluded.

## Phase gate

Do not treat the three PRs or public Hoodi migration as release-ready from this review alone. The legacy automator
authority is accepted as a continuing risk, with no V1 code change. The narrow V2 fixes, local tests and targeted
independent post-fix reviews are complete; the skipped local backend fork cases and hosted cross-repository replay are
not. The V1 PPS/residue issue remains a live reconciliation gate, not a proposed V1 implementation change. A fresh
onchain role/balance snapshot, actual-state Safe-batch gas simulation and production-shaped CoW orderbook acceptance
remain separate external gates. Do not deploy or move funds during this fix phase without a new explicit approval.
