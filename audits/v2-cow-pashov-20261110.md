# 🔐 Security Review — heroglyphs-seba CoW revision

---

## Scope

|  |  |
| --- | --- |
| **Mode** | filename |
| **Files reviewed** | `src/v2/YieldManagerV2.sol` · `src/v2/NativeSupporterVault.sol` · `src/v2/RethSupporterVault.sol`<br>`src/v2/YsyBoldSupporterVault.sol` · `src/v2/SebaV2DirectExecutor.sol` · `src/v2/cow/SebaCowIntentModule.sol`<br>`src/v2/cow/SebaCowOrderEscrow.sol` · `src/v2/LegacyProtocolPrincipalHandoff.sol` · `src/v2/LegacyIntakeStopper.sol`<br>`script/v2/DeploySebaV2.s.sol` |
| **Confidence threshold (1-100)** | 75 |
| **Passes** | 3 (pass 2 ran 11/12 agents) |
| **Memory** | 0 records before this scan · 13 after · `2d77f42` |

---

## Findings

[90] **1. One valid public legacy claim can veto the zero-claim cutover**

`LegacyProtocolPrincipalHandoff._noLegacyClaims` · Confidence: 90 · seen in 2/3 runs · NEW

Before Stage A, anyone may open a legacy supporter deposit. Only that depositor can withdraw it after the existing lock; the claim retains its original `vaultAtDeposit` even after the Safe points new deposits at a stopper. `_noLegacyClaims` nevertheless rejects every nonzero deposit amount, so the holder can indefinitely prevent the exact Stage B handoff while keeping a valid claim. This is the user-approved zero-live-claims release gate, not a hidden theft path. The runbook must coordinate/verify claim closure before Stage A and abort if any remain; permitting independently serviceable claims would require separate approval.

---

[75] **2. Public residual donations can exceed an immutable migration cap**

`LegacyProtocolPrincipalHandoff._conversionsClear` · Confidence: 75 · seen in 1/3 runs · NEW

The old router accepts ETH while inactive. With approved `maximumRouterEth = 0`, a one-wei transfer makes its balance exceed the cap and prevents Stage B. The same check covers BOLD/sBOLD residuals. Repeated donations require fresh Safe review and a newly configured handoff. The exact residual cap is a deliberate reviewed-snapshot condition; allowing surplus without a new approval would change that policy.

---

[75] **3. Repeated full-history scans can eventually exceed a Safe-batch gas envelope**

`LegacyProtocolPrincipalHandoff._noLegacyClaims` · Confidence: 75 · seen in 2/3 runs · NEW

The handoff scans historical deposit IDs from 1 through `oldDepositId` in precheck, import and postcheck, including closed positions. Public deposits grow this bound permanently. Specialist estimates exceeded 9,200 gas per historical ID across the three scans; thousands of IDs could consume a block-sized budget even with no live claims. Current mainnet `depositId=9` at block 26384421 does not exhibit the problem. A full Safe-batch gas simulation at the actual cutover state is mandatory; a bounded/verifiable migration proof would be a future design change.

---

[75] **4. Donated Beefy shares invalidate the old-adapter share snapshot**

`LegacyProtocolPrincipalHandoff.assertPreMigration` · Confidence: 75 · seen in 1/3 runs · NEW

An ordinary ERC-20 transfer of one Beefy share atom to the old adapter increases its physical balance while tracked `principalShares`/`principalValue` remain unchanged. `assertPreMigration` requires `balanceOf(oldVault) == actualBeefyShares`, so Stage B reverts until a newly reviewed snapshot/handoff is approved; repeated transfers can repeat the delay. No unauthorized principal loss was proved. A relaxed design would explicitly account for excess shares as disclosed unmigrated surplus.

---

[75] **5. Public ETH donations repeatedly invalidate the exact old-manager snapshot**

`LegacyProtocolPrincipalHandoff.assertPreMigration` · Confidence: 75 · seen in 1/3 runs · NEW

After Stage A, the old manager's public `receive()` accepts ETH. One wei changes its balance without changing the immutable `oldIdleEth`, so Stage B's precheck reverts; the `deposit()` exact-`msg.value` check also rejects importing the changed balance. An attacker can repeat this after each newly approved snapshot. This delays migration but does not leave the old manager armed: the Stage B Safe batch rolls back atomically. The approved runbook deliberately aborts and requires a fresh handoff on drift; a different design would segregate unsolicited ETH and import only the approved amount.

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [90] | One valid public legacy claim can veto the zero-claim cutover |
| 2 | [75] | Public residual donations can exceed an immutable migration cap |
| 3 | [75] | Repeated full-history scans can eventually exceed a Safe-batch gas envelope |
| 4 | [75] | Donated Beefy shares invalidate the old-adapter share snapshot |
| 5 | [75] | Public ETH donations repeatedly invalidate the exact old-manager snapshot |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **Destination preflight omits CoW protocol capital** — `LegacyProtocolPrincipalHandoff._destinationReady` · seen in 3/3 runs · NEW — Code smells: `pendingProtocolBold` and active CoW orders are not checked alongside other manager inventory — An earlier Safe-enabled destination can pass the pristine-destination assertion; no unprivileged creation or custody loss was proved. Harden after frozen audit.
- **Authorized mid-settlement close can strand later output** — `SebaCowOrderEscrow.close` · seen in 3/3 runs · NEW — Code smells: input allowance is consumed before output transfer in GPv2 settlement — A cooperating solver and contract operator could close after pre-donating the minimum; later output becomes Safe-only surplus. No unprivileged profit path was proved; retain operator/Safe recovery disclosure.
- **Exact live orderbook acceptance remains unverified** — `SebaCowOrderEscrow.initialize` · seen in 3/3 runs · NEW — Code smells: gross presigned sell budget with zero signed fee — Fork settlement and public quotes do not prove this exact format can be posted and filled by live solvers. Keep deployment disabled and PRs draft until a separately approved production-shaped rehearsal.
- **An unavailable direct executor view stopped independent CoW maintenance** — `yield-v2-client.ts.managerState` · seen in 1/3 runs · NEW — Code smells: uncaught direct-only getter failure in shared manager state — Backend now disables direct actions while preserving CoW finalization; tested. Attacker control over the view failure was not proved.
- **Yearn dynamic redemption capacity was missing from direct harvesting** — `yield-v2-maintenance.ts.convertCarry` · seen in 3/3 runs · NEW — Code smells: static cap permits amounts above live `maxRedeem(manager)` — Routine harvest could repeatedly revert; a failing regression preceded the backend fix. Exact preview drift remains the user's explicit policy.
- **A ysyBOLD view failure stops unrelated maintenance** — `yield-v2-maintenance.ts.convertCarry` · seen in 1/3 runs · NEW — Code smells: source-specific external read escapes the loop — The backend stops healthy rETH orders and donations after a ysyBOLD view fails; attacker control over that failure remains unproved.
- **A paused-but-finalized order was reported as blocked** — `yield-v2-maintenance.ts.maintainYieldV2` · seen in 1/3 runs · NEW — Code smells: summary mode stayed `blocked` after a successful finalize action — Backend summary is corrected and tested; no balance misaccounting was shown.
- **Rocket Pool dynamic capacity was missing from direct servicing** — `yield-v2-maintenance.ts.serviceLeg` · seen in 2/3 runs · NEW — Code smells: static cap permits amounts above live `getMaximumDepositAmount()` — Routine deployment could repeatedly revert; a failing regression preceded the backend fix. No fund extraction path was established.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
