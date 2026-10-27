# Seba YieldManager V2 specification

Status: specification for review, 23 October 2026. No V2 implementation, deployment, transaction approval or
production-readiness claim is made by this document.

This is the approved design record. The branch now contains its implementation; current evidence, audit status and
remaining gates are in [the implementation/release review](V2_IMPLEMENTATION_AND_RELEASE.md). Implementation-plan
statements below describe the specification stage, not the current branch's completion status.

## 1. Decision and scope

Replace the deployed manager for **future SebaPool rewards** with a new manager coordinating two native-token vaults.
Supporters deposit directly into their chosen vault. Each vault owns its positions and separately accounts for protocol
capital; the manager does not duplicate supporter accounting.

| Product       | Deposit and withdrawal token  | Protected principal basis             | Yield donated to Seba                         |
| ------------- | ----------------------------- | ------------------------------------- | --------------------------------------------- |
| rETH vault    | rETH                          | Protocol-reference ETH value at entry | Recognized growth above remaining ETH basis   |
| ysyBOLD vault | ysyBOLD, also called st-yBOLD | Recognized yBOLD value at entry       | Recognized growth above remaining yBOLD basis |

These are **not fixed-token-count savings accounts**, ETH redemption guarantees or loss insurance. For example, 100 rETH
deposited at 1.10 ETH/rETH creates 110 ETH of basis; at 1.20 ETH/rETH the principal withdrawal is approximately 91.6667
rETH. The remaining recognized growth is donated.

User decisions incorporated:

- Public deposits from launch; no treasury-only whitelist.
- Donate recognized yield to Seba validators, as today; retain the 30-day per-position lock.
- Keep the existing reward split: 50% immediate BOLD/sBOLD rewards; split only the invested half, initially equally
  between rETH and ysyBOLD. Overall: **50/25/25**.
- Future protocol investment weights are configurable. No automatic or governance rebalancing of existing holdings or
  already assigned pending cash.
- Treasury may withdraw its own unlocked supporter positions and redeposit manually, creating new positions and locks.
  This does not authorize moving other supporters' capital or treating treasury positions as protocol capital.
- Safe administration, upgrades and recovery for V2; bounded backend operations only.
- An economic loss blocks new entries into the affected leg but permits proportional remaining-token exits, without a
  treasury repayment guarantee.
- Recovery settles in the leg's normal token, not ETH.
- Yield not yet reflected in the external protocol's exchange rate follows the token returned on withdrawal. Seba
  receives recognized yield, not every future/unreported profit entitlement.
- Existing Aragon authority on deployed contracts remains. Its indirect powers and overlaps must be disclosed; the whole
  system is **not Safe-only**.
- If canonical valuation fails during recovery, the Safe may explicitly approve independently reconciled token budgets,
  with published evidence. This is a visible, trusted exception, not an automatic price fallback.

Required now: new manager, two vaults, bounded conversion execution, complete recovery, legacy protocol-capital handoff,
backend/indexer/UI compatibility, tests, audits and release procedures. Excluded: public ETH/yBOLD entry, supporter
position transfers, partial supporter withdrawals, NFTs for positions, common portfolio NAV, cross-leg hedging, new
borrowing/leverage, rebalance engines, changes to validator graduation/backpay, replacement of SebaPool/pybSeba, and
retrofitting Beefy recovery.

This supersedes the **unreleased ETH-in/ETH-out yBOLD adapter rollout design** for this V2 proposal. Existing code,
tests and reports remain historical evidence, not proof of V2 behavior. The unrelated dirty rETH branch and uncommitted
standalone prototype are not approved implementation baselines.

## 2. Evidence baseline and current state

Mainnet pin: **26,254,527**, hash `0xf9842dc4a3e72a98e5ed601053f38e64e053205e67c00c0d9c2cb7216fa37054`, timestamp
**2026-10-23 09:47:59 UTC / 11:47:59 Europe/Brussels**. All values are observations, not standing quotes or deployment
approvals. Refresh identities, balances, roles and execution conditions before implementation rehearsals and again
before release.

| Item                                                 | Address / pinned state                                                                              |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| SebaPool, retained                                   | `0xe3B17b4533b339d3CBC26F57199d3fb937129894`                                                        |
| Legacy YieldManager, retained for legacy obligations | `0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269`                                                        |
| Legacy Beefy adapter                                 | `0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba`                                                        |
| Treasury Safe / V2 authority                         | `0x888D768764A2E304215247F0bA3457cCb0f0ab4f`; 3-of-7, no enabled modules, zero guard at pin         |
| Aragon DAO, existing authority retained              | `0xf83b11b09EEc073ACE4481b2F4c8357e156714b3`                                                        |
| Existing pybSeba / sBOLD                             | `0x8D06a179486111E556A7C46E49352259B0279CD1` / `0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11`         |
| Canonical rETH                                       | `0xae78736Cd615f374D3085123A210448E74Fc6393`                                                        |
| ysyBOLD / its yBOLD asset                            | `0x23346B04a7f55b8760E5860AA5A77383D63491cD` / `0x9F4330700a36B29952869fac9b33f45EEdd8A3d8`         |
| yBOLD's BOLD asset                                   | `0x6440f144b7e50D6a8439336510312d2F54beB01D`                                                        |
| Legacy manager protocol principal                    | `3033332133271012792310` **legacy vault-native units**, not ETH or yBOLD                            |
| Legacy manager user IDs                              | IDs 1–9 have zero/cleared current records; retain their history and legacy withdrawal compatibility |
| Legacy pending conversion / active UID               | Zero / zero; verify actual router custody and order state too                                       |
| Treasury holdings                                    | 45.546510171738065920 rETH; 156,014.003721394916792917 ysyBOLD                                      |

The treasury rETH has protocol-reference value 53.485962222244898421 ETH at the pin; its ysyBOLD converts to
171,628.175477181556763156 yBOLD. Neither figure is an executable ETH sale quote or original-cost profit calculation.
Treasury token holdings are not residual manager protocol principal and must not be imported as such.

The fresh snapshot's JSON is delivered alongside this spec. Supplementary integration observations, not all fields
present in that JSON: rETH protocol rate 1.174315266319423064 ETH/rETH; Rocket Pool registry deposit pool
`0xCE15294273CFb9D9b628F4D61636623decDF4fdC`; current mint fee 5 bps, minimum 0.01 ETH, reporting frequency 86,400
seconds. Both Yearn tokens report API **3.0.4**. ysyBOLD has remaining locked profit at the pin: full unlock timestamp
1792766147 is later than pinned timestamp 1792748879.

Reviewed source snapshots, not claims about deployed backend versions:

| Repository                                        | Reviewed state                                                                           |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Contracts review worktree                         | `codex/ybold-stack-review`, `e8b6233d099aac1fd2303b280d6c99a5131a4865`                   |
| Contracts origin/main baseline previously checked | `0d2c922d4df05c38d934bc481e020ef7dd79dab0`; refresh at implementation start              |
| Backend compatibility review                      | `codex/ybold-recovery-compat`, `cdacf42ca2b83de437e62ea28f6d435370bf9a24`                |
| Subgraph compatibility review                     | `codex/ybold-recovery-indexing`, `cba81058aeff11d50813ae1040db896168a2014d`              |
| Frontend                                          | Repository not located/reviewed; owner and repository required before full-stack release |

## 3. Architecture and compatibility

```text
Existing SebaPool --depositFunds(ETH)--> YieldManagerV2 proxy
                                      | pending direct-reward ETH (50%)
                                      | pending rETH ETH (initially 25%)
                                      | pending ysyBOLD ETH (initially 25%)
                                      +--> fixed-route executor --> protocol buckets

Public supporter --rETH----> RethSupporterVault proxy
                            | supporter positions + supporter bucket
                            | protocol bucket (separate basis and custody accounting)
                            +--> recognized carry --> V2 reward coordination

Public supporter --ysyBOLD-> YsyBoldSupporterVault proxy
                            | supporter positions + supporter bucket
                            | protocol bucket (separate basis and custody accounting)
                            +--> recognized carry --> V2 reward coordination

Reward conversions --> BOLD --> sBOLD --> existing pybSeba.topup(amount)
```

### 3.1 Contract responsibilities

1. **YieldManagerV2:** pool-only payable `depositFunds()`; pending ETH assignment; future weights; bounded protocol
   deployment; classified yield inventory; completed sBOLD donation attribution; one-shot legacy import. It queries
   vault protocol totals instead of duplicating liabilities. It has no public supporter ETH-deposit path.
2. **RethSupporterVault:** one fixed token, ETH basis; public positions, isolated protocol/supporter buckets, native
   withdrawals and complete recovery.
3. **YsyBoldSupporterVault:** one fixed token, yBOLD basis; same lifecycle with the correct Yearn conversions. Not an
   ETH adapter and not falsely presented as ERC-4626: yield donation, locks and positions differ from fungible ERC-4626
   shares.
4. **V2 execution component:** small, fixed typed entry/harvest/conversion paths; no arbitrary target, receiver, token,
   delegatecall or calldata route. Prefer a non-upgradeable, transient-balance executor replaceable only by the Safe
   after allowance reconciliation. It never owns principal positions. Prove code-size/headroom before freezing
   decomposition; do not inherit the old 23,873-byte adapter just to reuse swap helpers.
5. **LegacyProtocolPrincipalHandoff:** minimal immutable, exact-amount, one-shot adapter for the legacy manager's
   protocol ETH. This exists only if the reviewed migration mechanism in section 10 is approved.

Use interfaces, Solidity 0.8.28, full NatSpec and repository formatting/testing conventions. Share small proven
math/helpers where sound; do not introduce a generic strategy/plugin framework. Names above are proposed targets, not
files already implemented.

### 3.2 Existing contracts

- **SebaPool:** no code upgrade; call its existing `setYieldManager(newProxy)` once approved. Its sweep still calls only
  `depositFunds()`, which V2 implements with compatible payable/no-return semantics. Validator subscriptions,
  graduation, rewards, NFTs and backpay stay untouched.
- **pybSeba:** retain address, asset and pool-controlled share distribution. Its permissionless `topup(uint256)` pulls
  approved sBOLD; V2 needs no privilege to mint/distribute validator shares. Approve only the exact top-up amount and
  clear residual approval. The existing event is `Topup`, not `TopUp`.
- **Old YieldManager:** immutable deployment remains live. V2 is compatible with the pool intake, **not every old
  manager getter/function**. Old position IDs retain their original manager, adapter, owner, amount and unlock. No fake
  onchain upgrade or renumbering.
- **Beefy and existing rETH deployments:** no retrofit, adoption or migration by implication. A new V2 vault is not the
  experimental standalone rETH product merely because both hold rETH.

## 4. Accounting specification

### 4.1 Units and buckets

Each vault has exactly two buckets: `SUPPORTER` and `PROTOCOL`. For each bucket track:

- `B`: outstanding nominal native principal basis, ETH wei or yBOLD wei.
- `Q`: accounted quantity of the vault's token, including unharvested carry.
- Informational cumulative entered basis, removed basis, transferred principal tokens, harvested tokens, explicit repair
  tokens and realized withdrawal loss. Counters never substitute for live liabilities.

Supporter positions record `(owner, basis, unlockAt, status)` under monotonically increasing local IDs; IDs are never
reused. External identity is `(chainId, vaultProxy, positionId)`. Positions are nontransferable and withdrawn in full.
Use a sufficiently wide timestamp, with checked conversion/addition; no 32-bit truncation.

Required identities:

```text
B_supporter = sum(basis of all open supporter positions)
B_protocol  = remaining protocol basis recorded in this vault
actual token balance >= Q_supporter + Q_protocol   [ordinary-operation custody check]
unassigned surplus = actual balance - Q_supporter - Q_protocol
```

Never add ETH basis to yBOLD basis. No cross-bucket borrowing, priority claim or automatic subsidy. Treasury-owned
supporter positions belong in `SUPPORTER`, not `PROTOCOL`.

### 4.2 Canonical value and rounding

`V(q)` is the external protocol's currently recognized native value of `q` custody tokens. rETH uses Rocket Pool's
canonical ETH/rETH conversion; ysyBOLD uses the deployed outer vault's yBOLD conversion. This is not DEX spot value or a
USD oracle.

Define `F(b)` as the authoritative floor-rounded token conversion of basis `b`, and `C(b)` as the conservative
ceiling-rounded principal reserve. Use full-precision math and the actual deployed conversion rules/total-assets and
effective-supply semantics. Do not invert a rounded display exchange rate, assume all decimals equal, or add an
arbitrary broad dust tolerance. Prove `C(B)` is sufficient under the same coherent conversion snapshot; for nonzero
total loss, do not divide by zero.

For coherent positive totals, the exact rational conversions are:

| Asset         | Totals                                                        | `V(q)`         | `F(b)`         | `C(b)`        |
| ------------- | ------------------------------------------------------------- | -------------- | -------------- | ------------- |
| rETH          | `N` = reported network ETH, `S` = reported rETH supply        | `floor(q*N/S)` | `floor(b*S/N)` | `ceil(b*S/N)` |
| ysyBOLD 3.0.4 | `A` = cached `totalAssets()`, `T` = effective `totalSupply()` | `floor(q*A/T)` | `floor(b*T/A)` | `ceil(b*T/A)` |

rETH's canonical `getRethValue(b)` supplies the floor inverse. Yearn's `convertToShares(b)` floors and
`previewWithdraw(b)` rounds up in the positive-assets case. Yearn `totalSupply()` already removes unlocked self-shares;
do not subtract them again. Preserve each protocol's zero-supply 1:1 convention, but distinguish positive supply with
zero backing: Yearn's inverse getter may return zero, and Rocket Pool's may revert. Neither behavior means the principal
reserve is zero. Validate these rules against deployed-compatible source and fork reads before coding.

```text
healthy                    := V(Q) >= B
economic deficit           := max(B - V(Q), 0)
protected token reserve R  := B == 0 ? 0 : (healthy ? C(B) : Q)
harvestable token carry    := Q - R
```

If `B > 0` and canonical value is successfully reported as zero, the bucket is wholly impaired: reserve is all `Q`,
harvestable is zero. Compute the inverse only for a healthy bucket; this also avoids unnecessary overflow in extreme
impairment. A reverted/unavailable view is a different fault, not a zero price.

Use the same rate snapshot within one operation; reject inconsistent source data. Native principal exits do not require
fresh ETH/USD or USDC/USD feeds. Successful but old Rocket Pool reports are not replaced with a DEX price: freeze
entries/harvest on approved report-age limits, disclose the reported valuation and preserve ordinary in-kind exits where
canonical conversion remains usable. Unavailable/invalid conversion requires affected-leg recovery, not a guessed par
payout.

### 4.3 Supporter entry

`deposit(q, minBasis, deadline)` pulls the fixed token from the caller directly into the chosen vault. The **spender is
that vault proxy**, not the manager. Only the caller becomes owner. Check deadline, enabled entries, valid canonical
accounting, custody integrity and no deficit in either bucket of that leg before accepting funds.

Measure actual received tokens. Require an exact standard-token transfer for the fixed supported assets; reject
fee-on-transfer/rebasing behavior rather than supporting arbitrary assets. Credit `b = V(qReceived)`, reject zero
quantity/basis and enforce `b >= minBasis`. Increase this bucket's `Q` and `B` only by those actual values; create the
caller's position with `unlockAt = now + 30 days`.

Also require a nonzero immediate healthy payout under that snapshot (`F(b) > 0`) and the separately approved minimum
position size. For example, one rETH token atom can credit one ETH wei while its inverse rounds back to zero; reject
that immediately unwithdrawable entry. Later impairment/extreme rate growth can still make a tiny payout zero; retain
its claim for explicit recovery instead of consuming it for zero through the ordinary path.

Entry at today's rate protects today's recognized value, not the token's historical purchase price. Existing carry and
unsolicited tokens cannot enlarge new principal. No fee is charged to supporter principal in this version. A failed call
rolls back transfer, position and counters together.

### 4.4 Ordinary withdrawals

Only the position owner may withdraw after its lock. Read pre-withdrawal bucket totals `(B,Q)` and position basis `b`:

```text
if V(Q) >= B: qOut = F(b)                         # final claim uses same rule
else:         qOut = floor(Q * b / B)            # pro-rata remaining backing
              if b == B: qOut = Q                # closes depleted bucket exactly

B' = B - b
Q' = Q - qOut
```

Enforce caller `minTokensOut` and deadline. Ordinary zero-output withdrawals revert without consuming the position; an
explicitly approved zero-budget recovery can close a total-loss claim. Mark the position closed/update accounting before
the external transfer under a reentrancy guard; a transfer failure reverts everything. Pay only the owner, never a
backend-selected recipient.

Healthy last withdrawal must not receive all `Q`: carry and rounding dust remain for donation. Underwater exits cannot
pay early users nominal par from later users' assets. Integer rounding can vary payouts by token atoms; specify and
prove a tight bound under all claim orders, with no economically meaningful early-claim advantage. Do not describe
variable-rate ordinary exits as fixed recovery-rate settlement.

No irreversible loss index/write-down in this version. If 100 native basis has backing worth 90 and a 50-basis claim
exits for approximately 45, remaining basis is 50 with backing 45. Future growth repairs that remaining deficit before
new yield is harvested. The exited 5-unit loss is historical, not another deduction from remaining principal.

Protocol withdrawal applies the **same bucket math**, without a supporter lock, only through a Safe-authorized method
with the fixed treasury recipient. It cannot consume supporter `Q`. There is no privileged user-position withdrawal,
unlock override or live-position rebalance method.

### 4.5 Harvest, donations and repairs

For each bucket independently, harvest at most `Q - R`, never reducing `B`, position locks or protected backing. Do not
harvest the impaired bucket. An unavailable sibling leg must not be called or consulted. Ordinary entry/harvest pauses
must not block otherwise valid withdrawals.

Collected tokens become explicitly tracked yield inventory, not principal. The vault transfer and manager's
authenticated inventory credit occur atomically, with actual balance-delta checks and calls accepted only from the
registered vault; a bare transfer is not sufficient accounting. Successful BOLD/sBOLD conversion donates 100% of this
inventory; it never passes through the fresh-reward 50/50 split. Conversion failure must either atomically revert
collection or leave exact classified inventory for retry, with no phantom completed donation.

Unsolicited transfers are unassigned surplus, never the next depositor's principal. Safe-only
`recognizeSurplus(bucket, amount, purpose)` may visibly classify surplus as a repair or donated yield; it cannot
silently rewrite `B`. `repair(bucket, amount)` pulls explicitly contributed tokens and increases only that bucket's `Q`,
not its basis. No automatic use of protocol capital/carry to repair supporters, or vice versa.

Physical custody shortage (`balance < Q_supporter + Q_protocol`) is **not** a rate/PPS loss. Normal payouts would race
to consume another bucket's tokens. Block ordinary affected-leg operations and enter recovery/reconciliation. The other
token vault remains usable. On detection in a reverting operation, do not falsely claim a persistent pause event/state
change; expose the condition in views and make the explicit recovery transaction persist it.

### 4.6 Locked and unreported yield

Only recognized growth during custody is available to donate. Yearn 3.0.4 uses cached asset accounting and effective
supply affected by profit unlocking; do not model it as current `master` 3.1.0. A native ysyBOLD withdrawal necessarily
transfers remaining future-unlock rights with returned shares. Similarly, not-yet-reported Rocket Pool yield may follow
returned rETH. Do not delay exits until every profit unlocks: repeated reports could prevent withdrawal indefinitely.

No post-withdrawal claim against those future profits exists. After recovery fixes same-token entitlements, later token
appreciation likewise belongs to recipients. Frontend and disclosures must say this plainly.

## 5. Protocol intake, deployment and reward delivery

### 5.1 Assignment at receipt

Only configured SebaPool may call `depositFunds()`; positive ETH required. No external calls into a venue are necessary
during this intake, so a broken investment route need not break pool sweeping.

For receipt `M`, invested weights `wR + wY = 10,000`:

```text
directRewardETH += floor(M / 2)
I = M - floor(M / 2)
pendingRethETH += floor(I * wR / 10_000)
pendingYsyETH  += I - floor(I * wR / 10_000)
```

Default weights `(5,000,5,000)`. Emit actual assigned amounts and config version. Odd wei go deterministically to the
invested half, then ysyBOLD remainder. Weights 0/10,000 and 10,000/0 must work. Changing weights affects future receipts
only; assigned ETH is already a leg-specific protocol asset. An unavailable route leaves its pending ETH untouched; no
spillover, second reward split or forced allocation change.

Forced/unclassified ETH is not automatically pool income or user principal. Track it separately and require explicit
Safe classification. Maintain `actual ETH >= all pending assigned ETH + any classified ETH yield inventory`; conversion
spend decrements exactly one authorized source bucket.

### 5.2 Initial typed routes

Prefer synchronous fixed-route execution for V2 to avoid inheriting the legacy router's global CoW-order state. Validate
this choice at intended size and costs on a fresh fork; poor execution is a release blocker, not permission to install
arbitrary aggregator calldata.

| Purpose                     | Route and accounting                                                                                                                                               |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Protocol rETH investment    | Assigned ETH → current registry Rocket Pool deposit pool → actual rETH → protocol bucket. Credit actual rETH's canonical ETH basis, not gross ETH before mint fee. |
| Protocol ysyBOLD investment | Assigned ETH → WETH → USDC → BOLD → yBOLD → ysyBOLD → protocol bucket. Credit actual final shares' yBOLD basis.                                                    |
| Immediate pool rewards      | Assigned direct-reward ETH → WETH → USDC → BOLD → sBOLD → existing pybSeba.                                                                                        |
| rETH carry                  | Harvested rETH → WETH on a verified fixed venue → USDC → BOLD → sBOLD → pybSeba. No compulsory native burn/withdrawal queue.                                       |
| ysyBOLD carry               | Harvested ysyBOLD → yBOLD → BOLD → sBOLD → pybSeba. **No BOLD→USDC→ETH→BOLD roundtrip.**                                                                           |

Do not require USD feeds, Curve liquidity or Yearn redemption for native supporter withdrawal. ysyBOLD carry redemption
requires Yearn availability, but not Curve/ETH/USD when no swap occurs. External failures may delay donations without
changing principal entitlements.

Protocol deposit records gross assigned ETH spent, actual acquired tokens/basis and execution costs in their correct
units. An estimate of market slippage is informational; do not subtract ETH from yBOLD basis or book gross ETH as an
intact claim after a fee-bearing rETH mint. Apply the same healthy-entry, nonzero basis/inverse payout and custody
checks to protocol credit; pending ETH is not permission to bypass a leg's entry freeze.

The executor returns only this call's outputs and leftovers to the manager; it cannot sweep other callers' dust or spend
a second classified bucket. Reconcile exact input/output balance deltas, refunds and intermediate tokens. Use ERC20 WETH
on Uniswap rather than leaving native refunds unaccounted. Any partial exact-input consumption is debited by actual
spend; remaining input stays assigned to the original purpose. No operator gas fee/reimbursement from protected
principal.

### 5.3 Execution bounds

Execution routes require real deadlines, caller minima and independent contract-enforced floors. Price-dependent routes
additionally require positive/complete/fresh relevant feed rounds and BOLD peg protection. Do not add USD-feed
dependencies to native exits or the direct ysyBOLD-to-BOLD donation path. Use fixed verified token/venue identities,
full-precision decimal normalization and exact bounded approvals cleared after use. A backend cannot lower onchain
safety limits by supplying zero minima. Do not use current spot output as the sole minimum.

Normal Yearn redemption maximum accepted loss is **0 bps**, explicit for both layers. No automatic emergency tolerance
widening. Inability to redeem yield does not authorize redeeming principal.

Yearn 3.0.4's `maxRedeem(owner, maxLoss)` overload ignores its loss argument; a successful limit query with zero is not
proof of a zero-loss redemption. Pass zero to the actual redemption calls and test their realized outcomes.

Numeric release parameters remain **unapproved implementation gates**: maximum rETH mint fee; per-swap slippage/impact
and BOLD peg caps; venue/pool fee tiers; source-specific oracle freshness; Rocket Pool report-age/data-block-lag bounds;
per-operation ETH/token caps; acceptable dust bounds and minimum viable harvest size. Prior adapter values (50 bps
swaps, 100 bps peg, 100 bps emergency Yearn loss) are not silently approved V2 settings. Recommend conservative values
with current full-size fork evidence for user review; do not guess during implementation.

Rocket Pool currently reports daily; a 1-hour USD-feed window must not be copied to its balance report. Registry changes
require code/identity checks and explicit operational review, never a remembered obsolete deposit-pool address. Prove
same-block mint/transfer behavior and any current transfer-delay hooks on a fork rather than assuming them.

## 6. Proxy, roles and trust boundaries

### 6.1 Proxy choice and deployment discipline

Use standard **OpenZeppelin UUPS + ERC1967Proxy** for the manager and both custody vaults from day one. This reuses the
reviewed stack's upgrade pattern with three small explicit proxies rather than introducing another admin-proxy
framework. No custom proxy. Authorize upgrades only to the treasury Safe; backend/routine configuration cannot grant
itself upgrade/recovery authority.

Lock implementation constructors with `_disableInitializers()` and initialize proxies atomically. Use upgrade-safe
storage, explicit storage-layout artifacts and an upgrade test preserving real positions, locks, buckets, pending ETH,
roles and recovery state. Validate UUPS compatibility, forbid unsafe initializer/reinitializer access and require
separately audited migration code for any future state reinterpretation.

Bootstrap sequence: initialize manager with fixed pool/treasury/token identities and inflows disabled; initialize both
vault proxies with their fixed asset/basis identity and manager proxy; bind the pair once in manager while empty,
validate reciprocal links, then deploy/configure the executor. No public entry or pool activation until all links, roles
and code verification pass. Routine admin cannot relink a funded vault; changing its binding requires reviewed
upgrade/state migration.

Every script, manifest, backend config, approval spender and graph source uses **proxy addresses**. Verify
implementations, proxies, ERC-1967 slots, initializer calldata and all linked addresses. A verified implementation alone
is insufficient.

### 6.2 Authority matrix

| Actor                       | May do                                                                                                                                                                        | Must not do through routine roles                                                                                                      |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Public supporter            | Deposit native token into chosen vault; withdraw own unlocked position; permissionless read/preview                                                                           | Withdraw another owner, bypass lock, choose arbitrary asset/receiver, move another leg                                                 |
| Treasury Safe               | V2 role administration; future weights/approved limits; entry/harvest pause; protocol withdrawal to treasury; surplus classification/repair; upgrades; recovery/final budgets | Present these powers as trustless or promise repayment; bypass claim accounting with direct user payouts                               |
| Bounded backend operator    | Deploy already assigned protocol ETH; collect bounded carry; execute typed conversions/top-ups within caps, to fixed destinations                                             | Upgrade, change roles/weights/venues/caps/recipients, start recovery, set settlement budgets, withdraw principal, reassign pending ETH |
| Manager proxy               | Credit protocol buckets from actual tokens; coordinate reward inventory                                                                                                       | Own or rewrite supporter position records, use supporter principal as conversion input                                                 |
| Existing Aragon DAO/plugins | Retain current deployed-contract admin paths, including manager pointer/role powers where granted                                                                             | Be described as having no influence just because it lacks direct V2 upgrade role                                                       |

Implement an explicit role-admin graph: Safe-only authority manages operator grants and all V2 privilege roles; no
operator/self-admin escalation or orphaned deployer grants. Roles can be distinct even though one Safe holds
admin/upgrade/recovery today. Verify actual 3-of-7 owners at release; do not infer Safe security merely from its
address.

**Overlap retained by user decision:** both Safe and Aragon hold legacy admin permissions. The DAO currently has a
2-of-6 multisig execution route and a separate admin-plugin route controlled by EOA
`0x5ebaaa3e84f9595fbf787a71c3caad97d370bc28`. The latter means the 2-of-6 policy is not the only DAO execution route.
Aragon can redirect future pool sweeps or interfere with legacy servicing through retained permissions. It also retains
pybSeba administration: `setSebaPool()` can replace the caller permitted to distribute/mint pybSeba shares. Therefore
the final donated-sBOLD/share-distribution system remains subject to this authority and potential dilution; the overlap
is not confined to future ETH intake. It cannot normally debit an existing V2 supporter position, but its inherited
system powers remain relevant. Do not revoke these authorities without separate approval.

**Ultimate trust:** the Safe's upgrade authority can replace logic and move all strategy assets, notwithstanding today's
core-token rescue restriction. No timelock or independent veto is promised. External Rocket Pool/Yearn/Liquity/token
governance also remains trusted. Normal core-token rescue is forbidden; accidental noncore tokens may be rescued only to
treasury with events and no overlap with accounted inventory.

## 7. Pause and loss behavior

| Condition                                         | New entries                                                   | Carry/conversion                                                            | Existing principal claims                                           |
| ------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Normal                                            | Public/approved protocol deployment enabled                   | Bounded                                                                     | Native token, normal rules                                          |
| Entry/harvest pause                               | Blocked for affected component                                | Paused as selected                                                          | Remain available if accounting/custody usable                       |
| Economic deficit in either bucket                 | Block whole affected leg's new capital                        | No impaired-bucket harvest; healthy bucket carry remains separately bounded | Pro-rata in impaired bucket; unaffected bucket/other leg usable     |
| Curve/DEX/USD oracle/Yearn redemption unavailable | Only dependent investment routes blocked                      | Dependent routes fail closed; inventory preserved                           | Native exits still work if required token accounting/transfer works |
| Canonical conversion unavailable/invalid          | Affected leg blocked                                          | Affected leg blocked                                                        | Recovery required; no guessed exchange rate                         |
| Actual custody shortage                           | Affected leg blocked                                          | Affected leg blocked                                                        | Recovery/reconciliation; no first-caller race across buckets        |
| Recovery custody exported                         | Affected vault permanently closed to ordinary entries/harvest | No new carry claim                                                          | Only funded recovery settlement after activation and original locks |

No automatic cross-leg failover, principal liquidation or tolerance widening. The Safe may pause entries quickly, but
bounded operator roles must not have an arbitrary asset-withdrawal freeze or rescue power. Recovery is terminal for that
vault instance; reopening is a separately specified upgrade/new deployment, not a convenient unpause.

## 8. Built-in same-token treasury recovery

Implement and test this path now; an unspecified future upgrade is not the plan. It protects against route/accounting
availability failure, **not losses in the underlying assets or token transfer censorship**.

### 8.1 Lifecycle and custody snapshot

State progression: `NORMAL -> RECOVERY_CUSTODY -> SETTLEMENT_ACTIVE -> SETTLED`. Entry/harvest pause and observed
economic deficit are independent from this terminal recovery progression.

Safe-only `beginRecovery(manifestHash)`:

1. Atomically stop ordinary deposit, principal withdrawal, repair and harvest for the affected vault. No position
   mutation can race the snapshot.
2. Snapshot each bucket's `B`, `Q`, entered/withdrawn/harvested/repair counters, current position-ID boundary,
   unassigned surplus and any available canonical valuation. Preserve existing owner/unlock records; no per-position
   onchain iteration.
3. Check physical custody. With normal custody, export **exact accounted Q** in the native token to the fixed Safe;
   handle unassigned surplus separately, never minting claims for it. This does not call Yearn redemption, Rocket Pool
   burn, a swap or USD feed.
4. If physical balance is below total accounted Q, use the explicit shortage mode: export actual available accounted
   tokens and assign the shortfall proportionally to both buckets' pre-shortage Q, with deterministic rounding. Record
   expected, actual and attributed amounts. No discretionary protocol-first allocation. Unassigned surplus is zero under
   this shortage condition.
5. Record export totals and keep positions/basis claimable only via recovery. Export does **not** close positions or
   mark users paid.

Record an immutable recovery-instance ID, onchain snapshot and **initial evidence-manifest hash** committing chain,
proxy, snapshot state, per-bucket basis/custody, destination and evidence location. Activation later commits a separate
**final classification/budget-manifest hash**, exactly once. That final manifest references the same instance and
snapshot and includes final budgets, classification mode, repairs/donations and loss rationale; initial evidence is
never overwritten. Emit a complete reconciliation event set. Token transfer failure reverts recovery; if the underlying
token itself is frozen, no strategy upgrade can guarantee a successful token transfer.

### 8.2 Final budget and funding

Set separate immutable final token budgets `N_supporter` and `N_protocol`, with denominators `B0_supporter` and
`B0_protocol`. This is token-per-native-basis settlement; never convert both legs to a single ETH rate.

Ordinary classification uses current canonical valuation of each bucket's reconciled exported backing **plus
authenticated bucket-tagged repair tokens**, at activation. Returning exported tokens is funding, not a second repair:
never count the same token amount twice in the backing cap.

- Healthy: principal-token cap is `min(reconciledQ + repairQ, F(B0))`.
- Underwater, including a successfully reported zero native value: cap is all reconciled/repaired backing for that
  bucket, without evaluating an undefined inverse.
- Identified excess is donated yield, not an automatic principal bonus.

If valuation calls are unavailable, a **distinct Safe-only exceptional classification** may attest fixed per-bucket
budgets and the public reconciliation manifest. It must emit an unmistakable exceptional-mode event; it is never an
operator-triggered fallback, cached/par oracle, or hidden tolerance bypass. The user expressly accepts treasury
discretion over principal/yield classification in this case. Unclassified upside must be identified in the manifest;
allocating it to principal requires an explicit disclosed donation, not a claim that it was mechanically proven
principal.

No automatic cross-bucket subsidy. A final budget cannot exceed its reconciled attributed backing plus separately tagged
voluntary repair funding for that bucket. The Safe can voluntarily make a loss whole, but is not obliged. Any manual
reclassification is observable and cannot erase positions or move another bucket's escrow.

Treasury funds the vault in **rETH or ysyBOLD** through a bucket-tagged funding function measuring actual tokens
received. Unsolicited transfers do not authenticate funding or allow activation. Before one-time activation require full
funding for both published budgets, explicit approval of any shortfall versus the reconciled cap, the final immutable
budget-manifest hash, and all custody/basis checks. Partial funding must never open a first-come settlement. Explicit
zero budgets are permitted for total-loss settlement; no fake positive funding requirement.

For an empty bucket `B0 == 0`, require principal budget zero; its backing is yield/surplus, not newly created liability.
Recognition, yield reserves and claim escrows remain separated until accounted.

Before activation, tagged funders can add a voluntary contribution only to the chosen bucket; contributions do not
create principal or imply a right to someone else's escrow. Authenticate and record any refundable overfunding
separately. Funding arriving after activation cannot alter the fixed budgets/rates and is not silently redistributed to
early or late claimants.

### 8.3 Claims, rounding and completion

For every supporter position with original basis `b`:

```text
qSettlement = floor(N_supporter * b / B0_supporter)
```

Use the same fixed numerator/denominator for every claim, regardless of payout order, current token PPS or later yield.
Original 30-day lock and owner check remain. Close the position and reduce outstanding basis once, atomically with its
token transfer. Zero-budget claims explicitly close for zero without a token call that would fail for amount zero. No
direct treasury payment while a vault position remains open.

Protocol claim uses its own budget/basis and the same rounding rule; it can settle the aggregate protocol bucket to the
fixed treasury recipient. No payout from supporter escrow. Already closed positions are absent from B0 and cannot claim
again. Normal withdrawal, second recovery, reactivation, rate changes and double claims revert.

Do not favor the final claimant with residual escrow dust. Keep exact paid-token and closed-basis totals. Only when
**all liabilities of the affected vault are closed** may finalization allocate rounding dust/excess to the
recognized-yield inventory and return authenticated voluntary overfunding to treasury, with events. No sweeper may debit
a live settlement reserve. Do not confuse donated yield with a treasury excess refund.

Activation fixes token quantities and ends Seba's claim on subsequent appreciation of allocated settlement tokens.
Long-unclaimed positions keep their escrow; no expiry/confiscation is introduced. A rejecting/blocked token recipient
can strand its own entitlement, not other users' claims; do not make completion contingent on a governance shortcut that
deletes it.

### 8.4 Manager-owned buffers

The manager must also have a built-in Safe-only recovery for its own pending protocol ETH and classified
yield/intermediate-token buffers. Freeze its intake/deployment/conversion before exporting these exact reconciled assets
to the fixed treasury, and emit purpose/leg/source totals. This does not withdraw from either vault, close supporter
positions, clear protocol basis held in a vault, or authorize offchain user payouts. Native vault withdrawals must
remain usable independently of a stopped manager. Restoring pool intake after a manager-buffer recovery requires a
separately approved, verified route/configuration; do not relabel exported cash as still invested.

## 9. Public APIs, views and events

The following is a semantic ABI contract for implementation. Exact structs/selectors must be frozen with the
implementation review and propagated to all repositories; these are not executable transaction payloads.

| Component / operation                                               | Access and required behavior                                                                                                    |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Manager `depositFunds()` payable                                    | Configured pool only; classify fresh ETH without venue execution                                                                |
| Manager `setFutureInvestmentWeights(rethBps, ysyBps)`               | Safe; sum exactly 10,000; increment version; never rewrite pending cash                                                         |
| Manager `deployProtocolPrincipal(leg, ethAmount, minima, deadline)` | Bounded operator/Safe; spend assigned leg ETH only; actual backing credits                                                      |
| Manager `convertRewards(source, amount, minima, deadline)`          | Bounded typed source; 100% yield donation path, not principal input                                                             |
| Manager `donateSBold(amount)`                                       | Exact classified sBOLD to fixed pybSeba, canonical completed-donation event                                                     |
| Manager `importLegacyPrincipal()` payable                           | Exact authorized one-shot path only; 100% protocol assignment                                                                   |
| Manager `recoverBuffers(manifestHash)`                              | Safe only; frozen intake/execution; export only its reconciled pending/protocol-yield assets to treasury, never vault principal |
| Vault `deposit(tokens, minBasis, deadline)`                         | Public; fixed asset; caller-owned local position                                                                                |
| Vault `withdraw(id, minTokensOut, deadline)`                        | Position owner; full claim; original lock; ordinary or active recovery semantics                                                |
| Vault `depositProtocol(tokens, minBasis, deadline)`                 | Manager only; pull exact approved tokens; protocol bucket, no supporter position                                                |
| Vault `withdrawProtocol(basis, minTokensOut, deadline)`             | Safe only; fixed treasury receiver; same bucket rules                                                                           |
| Vault `collectYield(bucket, maxTokens)`                             | Bounded operator/Safe; fixed manager destination; decrement Q and credit classified inventory atomically                        |
| Vault `repair(bucket, tokens)` / `recognizeSurplus(...)`            | Explicit donor repair / Safe surplus classification; no basis mint; validate intended donor/token/bucket                        |
| Vault `beginRecovery(manifestHash)`                                 | Safe only; fixed custody recipient; deterministic shortage handling                                                             |
| Vault `fundRecovery(bucket, tokens)`                                | Explicit contributor funding; actual delta; no authority to activate/change rate                                                |
| Vault `activateSettlement(budgets, manifestHash)`                   | Safe only; valid canonical classification and full funding                                                                      |
| Vault `activateExceptionalSettlement(budgets, manifestHash)`        | Safe only; explicit manual-classification attestations, limits and funding                                                      |
| Vault `finalizeRecovery()`                                          | Safe; no outstanding basis; reconcile all reserves/dust before any excess release                                               |
| All proxies `upgradeToAndCall(...)`                                 | UUPS, Safe upgrade role only; storage checks and reviewed initializer                                                           |

Expose immutable identity/configuration, active executor, tokens/basis decimals, roles, state, position, both bucket
totals, deficit/harvestable/withdrawal previews, pending ETH/yield inventory, weight version and recovery
snapshot/rates/funded/paid/outstanding totals. Views distinguish unavailable valuation from zero value and show
sufficient raw values for independent reconstruction; frontend preview never promises execution.

Every material state change emits proxy-address events containing relevant leg, bucket, native token/basis units and
actual quantities. Required event families: position opened/closed; protocol credited/withdrawn; realized loss; carry
collected; explicit repair and surplus classification; receipt assignment and actual protocol deployment;
weights/limits/roles/pause/upgrade; classified inventory change and completed donation; recovery
snapshot/export/shortage; tagged funding; final/exceptional classification and manifest; claim paid/closed; recovery
reconciliation/dust/excess. Avoid an event-only deficit checkpoint that can be mistaken for a permanent price guarantee.

Use transaction hash plus log index as event identities. Events and indexed entities must distinguish principal
movement, harvested-but-not-donated inventory and completed validator donation.

## 10. Legacy migration specification

### 10.1 Three different migrations

1. **Treasury native holdings:** rETH and ysyBOLD already held by the Safe can be deposited directly into the new public
   vaults after separate asset/amount approval. No ETH unwind/rebuy is necessary. These become treasury-owned supporter
   positions with a new 30-day lock.
2. **Legacy supporter positions:** preserve existing old-manager claims and original vault/locks. At the pin all current
   IDs are cleared, but refresh this fact. Do not copy them into V2 or pay them directly from treasury. Keep old
   ABI/address/UI service until every legacy obligation is closed. The initial release requires **zero live legacy
   supporter claims at final cutover**. If any reappear, stop until they withdraw or a separate servicing plan is
   approved: switching the old manager's active adapter also changes its harvest target, even though recorded old
   positions remain withdrawable through `vaultAtDeposit`.
3. **Residual legacy protocol principal:** still exists at the pinned state. It must exit through the real old Beefy
   path and reach V2 as **100% protocol capital**, not through the fresh-reward 50/50 split.

### 10.2 Dedicated one-shot handoff

The old manager's `retrievePrincipalFromYieldVault()` returns ETH to the **old manager**, not treasury. There is no
generic old-manager ETH sweep. Its `depositPrincipalIntoYieldVault()` forwards idle ETH minus pending conversion and
adds the adapter's returned native scalar; unlike normal deposits, it accepts zero. This allows a narrowly constrained
handoff adapter to forward exact approved ETH to V2 and return zero, leaving old protocol principal zero.

Required safeguards: immutable chain ID, exact old manager, V2 proxy destination, exact approved ETH amount, expiry and
one-shot state; no arbitrary destination/call/approval/token rescue; V2 accepts only the registered one-shot
source/amount. Emit imported ETH and the 100%-protocol pending allocation. The import's invested weights are explicitly
approved at import; no direct-reward allocation is applied. Lock/seal the handoff permanently after use.

Arm this exact-source/amount import inside the final atomic Stage B batch while ordinary pool/supporter inflows remain
disabled. The import must work during that reviewed bootstrap state; it is not a generic payable deposit or an
operator-controlled pause bypass. Disable the arm permanently on successful import. A changed amount/destination/expiry
requires fresh approval.

This deliberately exceptional zero return must be documented and audited against the actual old bytecode/source. Normal
old public `depositFunds()` rejects zero and must revert the entire attempted handoff, transfer and position mutation.
Do not deploy this mechanism merely because the spec describes it: independent review and exact fresh-fork rehearsal are
mandatory gates.

### 10.3 Preflight and atomic cutover

Before building final signed calldata:

1. Refresh block/hash, source identities, pool pointer, Safe owners/threshold/modules/guard, all admin/automator grants,
   old IDs and old vault principal/share balances. Assert zero live old supporter claims in the final atomic batch;
   permissionless old deposits before cutover must cause a clean abort, not an unsupported carry-servicing promise.
2. Drain/finalize/cancel/refund old conversions correctly. Require zero pending conversion and UID, no actual active
   order, reconciled router-held ETH/BOLD, manager BOLD/sBOLD and completed pybSeba top-ups. Do not blindly call a
   function that immediately opens another order.
3. Prove the old protocol position's **real full exit at the current fork** with intended minima. Old user ID 4 being
   cleared does not prove the residual protocol exit works. If liquidity blocks it, stop; historical success or
   synthetic funding is not a current migration pass.
4. Pin exact expected handoff ETH, native import assignment, final-state checks and expiry. Recheck any unsolicited old
   ETH; classify it explicitly instead of importing blindly.
5. Have verified new proxies, complete recovery code, executor, disabled initial entries, operational legacy service and
   caught-up dual-era indexer/backend ready. No unfinished external order or unbounded approvals may cross the handoff.

Approved two-stage procedure, each stage rehearsed with the real Safe threshold on a fresh fork:

```text
Stage A — exit first, with separately approved exit parameters
oldManager.setYieldVault(verifiedStatelessIntakeStopper)
    # real Beefy exit; principal becomes zero; ETH stays in the old manager
    # stopper rejects deposits, harvests and redemptions without taking custody
reconcile actual ETH, original adapter residue and every old claim/order

Stage B — approve the now-known exact amount, then execute one atomic batch
V2.armLegacyImport(exactReviewedSourceAmountExpiryAndWeights)
handoff.assertPreMigration()
    # zero live old claims/PV, canonical stopper, exact ETH, Safe and identities
oldManager.setYieldVault(approvedHandoffAdapter)
oldManager.depositPrincipalIntoYieldVault()
    # exact ETH forwarded; handoff returns zero; old principal remains zero
enable/configure approved V2 intake, within the reviewed bootstrap gates
SebaPool.setYieldManager(verifiedV2Proxy)
assert final pointers, balances, zero old protocol basis, exact V2 import assignment
```

Use real Safe API semantics/threshold in rehearsal; signers authorize production separately. The executable state-check
mechanism must be audited and use narrowly typed assertions, not a generic executor. Do not merely place textual
assertions in a Safe UI and claim atomic protection.

Pause legacy yield maintenance before Stage A; retain non-yield backend duties. `SebaPool.sweepRewards()` is
permissionless: stopping the backend alone does not freeze inflows. The stopper makes old deposits and sweeps revert
between stages. Reconcile any forced/donated ETH again before Stage B: an amount mismatch must abort, not silently
change the approved import. A separate call to `retrievePrincipalFromYieldVault()` is not also required if
`setYieldVault()` already performs the redemption; do not double-withdraw.

Afterward, verify both transaction receipts and read-only state. Deploy pending ETH by leg in bounded, separately
simulated operations, then open public entries and agreed automation only after full reconciliation. Large treasury
supporter deposits need explicit token/amount approval. Do not revoke old-vault roles required to service any surviving
legacy positions.

### 10.4 Rollback limits

- Before Stage A: abort and retain the old live stack. Unfunded V2 deployments need not replace it.
- After Stage A: an abort leaves ETH parked in the old manager and legacy intake stopped; it does not restore Beefy. A
  failed Stage B rolls back its import arm and all of Stage B, not the completed Stage A exit. Reapprove any changed
  amount/expiry using a fresh handoff. Do not resume legacy intake without a separate reconciliation and approval.
- After import: undoing a pointer does not return funds to old manager. New liabilities and custody must remain
  serviced.
- Do not advertise a one-click pool-pointer rollback while the old manager points at the zero-return handoff: ordinary
  pool deposits would revert.
- Restore any old intake only after a separately approved, independently reconciled route change. No implicit
  liquidation/rebalance of V2 holdings.
- After public deposits: pause new entries, not valid claims. Emergency recovery uses the documented terminal path;
  token/venue losses cannot be rolled back.
- Software rollback must preserve both eras, positions, transaction state and historical indexing. Never reset
  production epochs/S3/graph history to make a release pass.

## 11. Repository implementation plan

No files in this section have been implemented by this specification task.

### 11.1 Contracts

Proposed targets: `src/YieldManagerV2.sol`, `src/RethSupporterVault.sol`, `src/YsyBoldSupporterVault.sol`, matching
interfaces; a small fixed-route execution component; `src/migration/LegacyProtocolPrincipalHandoff.sol`;
deploy/preflight/reconciliation scripts; per-contract/per-method BTT tests and fork suites. Final names/decomposition
may change without changing economics or trust boundaries.

Start from freshly inspected `origin/main` in an isolated V2 review branch/worktree; preserve the current unrelated rETH
changes. Reuse audited ideas/helpers from the existing ysyBOLD review only after checking differences. Do not merge that
ETH-only adapter's accounting/recovery ABI into the native-token product by accident. Preserve deployed legacy source
history and ABIs.

### 11.2 Backend

Add separate typed V2-manager and native-vault clients/configuration. Existing selection in
`lambdas/scheduled/validator-graduator/validator-graduator-helpers/utils.ts`, yBOLD proxy-equality checks in
`ybold-strategy.ts`, and independent standalone rETH maintenance in the graduator entrypoint require explicit revision;
the old ABI cannot be pointed at new addresses.

Required behavior:

- At a coherent block, read actual pool manager pointer and verify proxy/implementation/vault/token identities before
  writes. Config presence is not activation.
- Retain old manager reads/drain/legacy service and history; select the correct era explicitly.
- Era-gate the legacy first-graduation `startYieldFlow()` / `activateYieldFlow()` hook. The current graduator invokes it
  before graduation error handling; V2 has no such activation call and donates recognized yield from launch. An
  unsupported legacy-selector call must not block graduation on V2. Keep the hook only for an actual legacy manager.
- Maintain separate pending/harvest/retry state by vault and source. A failed ysyBOLD harvest must not stop rETH
  servicing or validator graduation/backpay work.
- Bound every maintenance action to onchain limits and fixed destinations. No operator upgrades, recovery, role changes,
  rebalance or automatic principal liquidation.
- Treat imports, native supporter deposits, protocol deployment and repairs as capital, never validator income.
- Preserve S3/state keys, epoch cursors, idempotence and deployment environment configuration; no reset/replay of
  already processed rewards.
- Reconcile completed donations and pending inventories from receipts/state. Monitor stale reports/feeds, deficit,
  custody mismatch, unexpected upgrades/roles/pool pointer, recovery funding and unclaimed positions.

Deliver backend unit/integration tests, local fork rehearsal, release manifest and rollback instructions.
Runtime/security patching is a separate environment check; this spec does not attest current AWS/Node patch status.

### 11.3 Subgraph

Retain original pool/PYB/sBOLD/legacy manager/backpay sources, start blocks and full history. Legacy static manager
start block is 23,481,656. Add versioned V2/vault ABIs, mappings, tests, schema/entities and exact new deployment
blocks. Register sources before their first events; late dynamic templates do not backfill initialization/upgrade
events.

Add handling for pool `YieldManagerSet`; current pool mapping does not track this transition. New `SupporterPosition`
IDs are chain+vault+local ID; preserve original legacy `YieldDeposit` semantics and historical records. Store token,
decimals, native basis unit, actual deposited/withdrawn tokens, unlock, status and recovery amounts explicitly; do not
invent ETH deposits/withdrawals for native-token entries/exits.

Index separate protocol/supporter bucket totals, pending ETH by purpose, weight versions, classified carry, completed
donations, repairs, shortage attribution and final token settlement budgets. Do not imply a weight change rebalanced old
holdings. Include manifest hash and exceptional recovery-classification flag.

Count completed sBOLD yield once. Legacy manager `BoldConversionFinalised` currently updates pool yield totals while PYB
`Topup` updates PYB assets. Define V2 completed-donation attribution without counting harvest, manager conversion and
the same PYB top-up multiple times. Reconcile each receipt's donation event with actual PYB/sBOLD balance movement.

Prove full historical rebuild or an explicitly approved graft. `_meta` health alone is not sufficient: reconcile
historical IDs, position ranges, deployment-boundary events, active pointers and all new accounting totals.

### 11.4 Frontend and operator tooling

Frontend source was not located; repository and owner are a release blocker, not an invented implementation claim.
Required UI contract:

- Choose native rETH or ysyBOLD; approve that vault proxy, show actual asset/basis and 30-day lock.
- Explain donated recognized yield, potentially fewer tokens returned, losses and residual locked/unreported-profit
  rights.
- Show previews as estimates, both independent positions and correct units; no shared-portfolio/rebalance controls.
- Preserve legacy withdrawals at old manager addresses; never reuse bare position IDs across eras/vaults.
- Display entry pause, economic deficit, custody recovery and funded settlement separately. Expose manifest, fixed
  payout basis and exceptional classification.
- Give direct-contract instructions for UI/indexer outages. Never ask users to send principal to treasury for an
  offchain promise while claims remain open.

## 12. Verification and audit acceptance

### 12.1 Unit, branch and property testing

Use repository BTT layout: every contract has a test folder and every method its branching tree. Exercise every
new/changed branch and require measured **100% line coverage** for new/changed onchain code. Publish exact
command/output, compiler/optimizer settings, exclusions and branch evidence; no invented full-stack percentage. Include
proxy initialization, inherited reachable security paths and negative controls. Coverage is evidence, not proof of
safety.

| Area                | Required cases/properties                                                                                                                                                                                                                                                                                                                                                         |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Initialization/UUPS | Atomic initialization; locked implementation; wrong/zero identities; repeat initialization; unauthorized upgrade/reinitializer/role grant; incompatible layout rejected; complete state preservation                                                                                                                                                                              |
| Entry               | Both real tokens; multiple users; same caller repeated positions; actual delta; exact spender; minimum/deadline; zero; bad transfer; deficits and pauses; unassigned donations; historical gains not retroactively donated                                                                                                                                                        |
| Exit                | Owner/unlock boundary; healthy and impaired; min-out/deadline; final healthy carry retained; final impaired Q cleared; zero-output ordinary rejection; transfer failure rollback; repeat/cross-vault/closed IDs                                                                                                                                                                   |
| Isolation           | Four B/Q buckets; no cross-leg netting or protocol priority; treasury supporter distinction; independent operation during sibling failure; no duplicated manager liabilities                                                                                                                                                                                                      |
| Math                | Full precision/overflow extremes; floor/ceil; PPS/rETH rate growth and loss; successful zero vs unavailable rate; all claim orders and tight rounding bounds; empty→funded→empty→funded cycles                                                                                                                                                                                    |
| Harvest             | Reserve preserved; no impaired-bucket carry; recognized/unlocked growth only; B/locks unchanged; residual locked-profit rights; tiny/unprofitable harvest skipped; zero-basis carry not next depositor's                                                                                                                                                                          |
| Intake/deployment   | 50/25/25, odd wei, 0/100 weights, version changes leave pending cash; route failure no spillover; gross ETH vs actual basis/fee; missing venue/capacity; forced ETH                                                                                                                                                                                                               |
| Conversion          | Direct ysy→BOLD route; all yield 100% donated; fixed recipients; minima/floors/deadlines; stale/invalid feeds; peg failure; Yearn limits/loss=0; exact approvals/refunds/partial consumption; failed donation retry                                                                                                                                                               |
| Donations/shortage  | Quarantined surplus; explicit repair no basis; no automatic subsidy; proportional physical-shortage recovery; normal revert does not falsely persist pause                                                                                                                                                                                                                        |
| Recovery            | Every state transition; unauthorized/repeat/premature/underfunded; exact export; no redemption/swap dependency; per-bucket full/partial/zero settlement; exceptional Safe classification; manifest; zero-basis bucket; double claim; locks; fixed-rate payout order; no last-claimer dust bonus; live reserves unsweepable; manager-buffer recovery leaves vault positions usable |
| Legacy handoff      | Correct exact import; wrong caller/chain/source/amount/destination/expiry; replay; normal old-deposit zero-return rollback; no second 50/50 haircut; intervening sweep; safe atomic assertions; old claims preserved                                                                                                                                                              |

Stateful fuzz handlers must model real funded actors and mixed entry/exit/harvest/loss/pause/repair/recovery sequences,
recording meaningful successful-call counts rather than passing on all reverts. Invariants cover exact basis sums, token
custody, escrows, classified pending ETH/inventory, immutable closed claims, no principal harvested, no order advantage
beyond proved atom bounds and complete conservation including fees/losses/donations. Include counterexample tests that
intentionally break one invariant to prove the harness can catch it.

### 12.2 Fork and full-stack E2E

Run two clearly labelled suites: deterministic pinned-mainnet regressions and a **fresh execution-time mainnet fork**.
Report block/hash/timestamp/RPC capability, commands, exact sizes and results. No production private keys or
transactions; impersonation is local only.

Mandatory scenarios:

1. Deploy real proxies, initialize/bind them, verify roles/implementations and deposit current real rETH/ysyBOLD from
   impersonated funded holders.
2. Real pool reward intake and real protocol investment in both legs; actual mint fee and every route output reconciled.
3. Healthy recognized-yield growth/harvest/top-up, native withdrawals after unlock, protocol withdrawal, multiple users
   and large intended treasury-size positions.
4. Broken/imbalanced Curve exit, unavailable Yearn redemption, stale USD feed and blocked DEX: prove native exits do not
   call them; sibling operation survives.
5. Rate/PPS losses and successful zero valuation; per-leg entry freeze and pro-rata exits; report/profit unlock cycles
   and retained future rights.
6. Authorized upgrade with open positions and all pending/recovery state preserved; every unauthorized attempt rejected.
7. Custody recovery/export, tagged real-token funding, full/partial/zero token budgets, exceptional
   unavailable-valuation classification, locked/unlocked users, protocol settlement and final token/basis/position
   reconciliation.
8. Complete **current** old Beefy→old manager→handoff→new manager→both protocol vaults path using actual residual
   capital and unchanged Safe threshold. Also test an explicit fixture containing surviving legacy users even though
   current IDs are cleared.
9. Backend against the same persistent fork and realistic transaction receipts; Graph Node historical/indexing replay
   and manager switch; frontend integration once its repo is supplied. Preserve validator graduation/backpay
   regressions.

Label fault injection (`mockCall`, storage/code overrides, synthetic loss/venue failure), artificial time/report
refreshes, account impersonation and donated synthetic funding separately. A funded recovery simulation proves claim
mechanics, not liquidation at par. Artificial future-time feed refresh is not fresh-market evidence. Historical
successful Beefy exits are not a current migration pass. The fresh baseline snapshot is **read-only evidence only**;
none of the V2 tests above have run yet.

### 12.3 Security review and release gates

Require independent accounting/migration/access-control/integration review plus adversarial verification of findings.
Use currently available audit models/harnesses and Trail of Bits/static-analysis tooling where applicable, followed by
stateful invariants and concrete PoCs. Pin skill/tool/model versions and audit commit scope. Do not claim the best
model, AI audit or 100% coverage eliminates exploits.

Block release on unresolved critical/high findings; document medium/low issues and explicit risk acceptance. Re-review
any code change after audit, reconcile dependency advisories/compiler warnings, proxy layout and EIP-170 runtime size.
Coverage, measured branch evidence and real full-stack E2E are separate gates, not substitutes for one another.

## 13. Deployment and operating runbook requirements

Implementation must deliver runnable, reviewed scripts and an exact address/role/artifact manifest; this specification
intentionally supplies no live executable payload.

Release order:

1. Approve this product/trust/accounting design; resolve numeric execution limits and exact migration ABI.
2. Implement contracts/stack in review branches, complete tests/invariants/audits and publish evidence.
3. Identify frontend repository/owner; stage dual-era UI/backend/indexer, preserving history/state.
4. Obtain separate production authorization. Deploy/verify proxies, executor and handoff only then; keep new inflows
   disabled until configured and checked.
5. Register all graph sources from actual deployment blocks, catch up/reconcile; deploy backend dual-era/read-only V2
   configuration with bounded operator keys/roles and old service retained.
6. Refresh mainnet inventory and complete exact current-fork Safe cutover rehearsal. Publish reviewed calldata, minima,
   expiry, fees, expected balances and abort conditions for signers.
7. Execute separately approved atomic cutover; reconcile receipt/state and roles immediately.
8. Deploy small protocol allocations, enable public entry only after checks, then separately approved treasury
   native-token deposits. New locks start at deposit; no silent treasury balance sweep.
9. Enable automation and monitor real donation/native withdrawal paths, pending buffers, graph parity and alerts. Keep a
   direct RPC/UI-independent exit guide.

Normal operations: backend quotes bounded pending deployment/carry, skips uneconomic harvests, simulates exact calldata,
executes within limits and reconciles receipts; Safe reviews future weights/limits and protocol withdrawals. No
quarterly-only assumption and no fixed harvest frequency without cost/yield evidence.

Emergency operations: Safe pauses affected entries/harvest; diagnose valuation versus route versus custody issue;
preserve native exits where safe; publish snapshot/manifest; simulate and authorize exact custody recovery; reconcile
exported tokens/buckets; publish ordinary or exceptional classification and loss disclosure; fund full fixed token
budgets; activate once; users claim after original unlock; reconcile remaining basis/escrow and finalize only at zero
liabilities. Never pay users offchain and leave their positions open.

Abort on identity/code/role/pointer mismatch, pending order/cash ambiguity, changed Safe security, unreconciled
surplus/shortage, stale/unapproved execution assumptions, old withdrawal failure, out-of-bound quote, unexpected token
behavior, incomplete verification, coverage/audit gaps or backend/indexer divergence. Rollback limits in section 10
remain in force.

## 14. CROPS and implementation handoff

- **Censorship resistance:** public native entry/exit and direct RPC instructions avoid mandatory UI/liquidation venues.
  Token transfers/views, Safe recovery and retained legacy administration can still block service; do not overstate
  trustlessness.
- **Open source:** publish verified contracts, ABIs, events, reproducible build/test/indexing instructions and
  applicable licenses. Proprietary hosting is not required to exercise a claim.
- **Privacy:** positions, amounts, owners, donations and timing are public. Document provider/indexer exposure; do not
  promise private deposits.
- **Security:** Safe-controlled upgrades/recovery are fully trusted; backend is narrowly bounded; legacy Aragon overlap
  remains explicit. No principal/yield or unit ambiguity, unpriced cross-leg claim or hidden loss socialization.

Implementation may begin after design review, but **must not deploy, broadcast, move funds, change production services
or merge without separate approval**. The current handoff has no V2 test coverage or E2E execution evidence because this
task creates a specification only.

Open release inputs, not silently decided: numeric route/risk limits; exact audited migration/ABI and atomic assertion
mechanism; refreshed full-size liquidity/capacity evidence; frontend repository/owner; production service/role
inventory; CI archive-RPC access and funded persistent-fork infrastructure. Report each honestly; do not substitute
guessed settings or a passing historical fork.

## 15. Specification preparation checks

Three parallel, read-only specialist reviews covered accounting/recovery, migration/full-stack compatibility and
external integrations. Their corrections are incorporated, including immediate-entry dust rejection, independent
recovery evidence/final-budget commitments, exact deployed `topup` casing, legacy graduation-hook compatibility and the
zero-live-legacy-claim cutover gate. These are design reviews, not code audits.

Prettier formatting and local evidence-link/JSON-pin checks passed. An in-memory rational-arithmetic sanity check
covered 38,657 positive-rate cases for floor/ceiling reserves, healthy exit backing and depleted final-claim closure.
This idealized arithmetic check does not exercise Solidity, actual protocol conversions, temporal state or adversarial
sequences; it is not V2 coverage, a fuzz harness or fork/E2E proof. No V2 source/tests were written or executed.

## 16. Evidence and primary references

- [Pinned read-only mainnet snapshot](SEBA_V2_MAINNET_SNAPSHOT_20261023.json). Supplementary reads and exact
  source/version distinctions are documented in section 2; refresh everything at release.
- Existing local behavior: [legacy manager](../src/YieldManager.sol), [pool](../src/SebaPool.sol),
  [pybSeba](../src/PYBSeba.sol). The previous ETH-only adapter design/runbook and October 22 audit artifacts belong to
  the separate yBOLD review, not this V2 release. Use the
  [V2 evidence and release gates](V2_IMPLEMENTATION_AND_RELEASE.md) for the implementation in this branch; previous
  tests do not cover this V2.
- [Rocket Pool rETH source](https://github.com/rocket-pool/rocketpool/blob/master/contracts/contract/token/RocketTokenRETH.sol),
  [deposit-pool source](https://github.com/rocket-pool/rocketpool/blob/master/contracts/contract/deposit/RocketDepositPool.sol),
  [network balance reports](https://github.com/rocket-pool/rocketpool/blob/master/contracts/contract/network/RocketNetworkBalances.sol).
  Pin deployed-compatible source commits before implementation; current master alone is not a bytecode match.
- [Yearn TokenizedStrategy v3.0.4](https://github.com/yearn/tokenized-strategy/blob/v3.0.4/src/TokenizedStrategy.sol),
  [yBOLD staker](https://github.com/yearn/yBOLD/blob/master/src/Staker.sol),
  [accountant](https://github.com/yearn/yBOLD/blob/master/src/periphery/Accountant.sol). Use deployed-version semantics,
  not master 3.1.0 accrual assumptions.
- [Uniswap V3 SwapRouter](https://github.com/Uniswap/v3-periphery/blob/main/contracts/SwapRouter.sol),
  [payment/refund behavior](https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/PeripheryPayments.sol),
  [OpenZeppelin upgradeable proxy guidance](https://docs.openzeppelin.com/contracts/5.x/api/proxy),
  [Aragon permissions](https://docs.aragon.org/osx-contracts/1.x/core/permissions/).
- [Repository-required Ethereum skill](https://ethskills.com/SKILL.md), including security, testing, address
  verification and CROPS guidance; [V2 vocabulary](../GLOSSARY.md).
