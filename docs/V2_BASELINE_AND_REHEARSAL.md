# V2 implementation preflight: mainnet baseline and rehearsal environments

23 October 2026. Read-only investigation before implementation. No feature code, deployment, transaction, infrastructure
change or merge.

## Mainnet code verdict

Fresh `git fetch origin main` confirmed contracts `origin/main` at `0d2c922d4df05c38d934bc481e020ef7dd79dab0`.

At block **26,255,322**, hash `0xdf03dd56424c670aa7b639794af21acdb65f670e74bbf531c6d18e3118bcb948`, 23 October 2026
**12:27:47 UTC / 14:27:47 Europe/Brussels**, all five active legacy core runtimes match a fresh compilation of that
exact commit after replacing only compiler-declared immutable locations with the deployed values. Repeated immutable
slots and integration getters were checked. SebaPool required no immutable substitution.

| Contract        | Mainnet address                              |  Bytes | Live runtime keccak256                                               |
| --------------- | -------------------------------------------- | -----: | -------------------------------------------------------------------- |
| SebaPool        | `0xe3B17b4533b339d3CBC26F57199d3fb937129894` |  4,747 | `0x61c9af11db78c42c5253722d65a94a7f953a40197d08f5b6fb17bc8d484098ff` |
| YieldManager    | `0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269` |  9,271 | `0x1559acbd76f94270c1f634c3ccad419e4b526f6cee6e3ddbc9ff5d346211cf3c` |
| Beefy adapter   | `0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba` | 12,345 | `0x8fbf28856761a6cc5d247a6ddc1f4309692d6a8c15337515a5ed8f50efb8c5ad` |
| ETH→BOLD router | `0x8964C3746b0d1A1BaE5F7f77879b2fE45c45FCA4` |  5,104 | `0x376eea4a900f4bf179f04fb5f5cf1c1d6d5dca10d30bd961eab2f2666ec6a7d3` |
| PYBSeba         | `0x8D06a179486111E556A7C46E49352259B0279CD1` |  7,500 | `0x69d87f49a85568ba17235ce12e43e252b57a47b46e7b044b4cc730b3f88bfcf4` |

Diagnostic source/artifacts: `/private/tmp/seba-origin-parity.C808Uj/`, extracted with `git archive` of the exact ref.
Build: `forge build --skip test --skip script`; this skips compiling unrelated tests/scripts for the diagnostic, and is
**not a test pass**. Compiler settings: Solidity 0.8.28, Cancun, optimizer 10,000, no CBOR metadata. Dependencies used:
OpenZeppelin 5.2.0, solmate 6.8.0. The remote baseline has **no tracked dependency lockfile**; its version ranges alone
are not a reproducible release.

**Qualified conclusion:** the five core contract implementations match. The repository is not an exact current
deployment/state manifest. Its deployment scripts do not encode the complete current Safe/Aragon handover; historical
roles, balances and external contracts are separate evidence. Safe/Aragon/third-party implementation sources are outside
this repository's own runtime-parity claim.

## Live configuration and obligations

- Pool still points to the legacy manager, which still selects the Beefy adapter and old ETH→BOLD router. Neither rETH
  nor ysyBOLD is currently selected there.
- Manager protocol principal is `3033332133271012792310` **old native units, not ETH**. Beefy shares are
  `2461485476753155859456`; its native principal is 149 atoms above the manager's.
- Current manager IDs 1–9 are cleared, but protocol principal remains. Pending conversion/manager UID and observed
  manager/router ETH are zero. Complete external order reconciliation is still a release requirement.
- Safe and Aragon DAO both currently have admin on all five core contracts. Backend is automator on pool/manager, not
  admin. Safe is 3-of-7, with no enabled modules and zero guard.
- Both Aragon admin and multisig plugins can execute; the known single-admin EOA remains a plugin member. Fresh multisig
  member-count and exhaustive role-history enumeration are not attested here.
- Slippage settings are 50 bps; manager validity 900 seconds; max-fee setting 1,000 bps; yield flow is active.

## Existing test environments: do not reset

| Stack                           | Actual chain            | Architecture                                               | Current concern                                                            |
| ------------------------------- | ----------------------- | ---------------------------------------------------------- | -------------------------------------------------------------------------- |
| `HeroBoostBackendStackTest`     | Hoodi, 560048           | Old BoostPool/apxETH, not mainnet-shaped BOLD/rETH/ysyBOLD | Stale stack/indexer/state; cannot prove this migration                     |
| `HeroBoostBackendStackTestMain` | **Ethereum mainnet, 1** | Legacy Seba/BOLD/Beefy                                     | **Real funded obligations and enabled automation, not disposable testnet** |

Hoodi pool is `0xD0bCFB4D71F375354bE86a07e14360470B96019f`, manager `0xDd6630f545455F5DF378B183aC8c4F7C5D599caa`.
Canonical mainnet rETH/ysyBOLD addresses have no code at the same addresses on Hoodi; separately deployed equivalents
were not established.

Mainnet-test pool is `0xE07Ef8Aed1870cf743A178255472ee776d937902`, manager `0x7D0949F5e55e36a782F98DF369F8fbc577473DbE`,
adapter `0x49e58724F6e86819195dC1b3A01A734586280879`.

At block **26,255,341**, hash `0xd799dbb7271e5b53bd5cf697c2e952f44e58c0def33c086d9d4cd8af4cdbefa5`, mainnet-test has:

- Protocol principal `22365968837130288885` legacy native units.
- Live user ID 1, owner `0x5EBAAA3E84F9595fBF787A71C3CAad97d370BC28`, amount `22374273007783437699` legacy native units,
  unlocked since 15 October 2025.
- Pending conversion `35263034319159` wei and an active-in-contract router order
  `0xb2fcccf639a367e64837fdfca38b0a525b94a104d1e8480e9f2ee82c214e4d33`, expired since 15 September 2025 but not
  finalized.

Both test EventBridge schedules remain enabled every 15 minutes. Both use 24-hour-style graduation settings (7,200
blocks / 225 epochs), not production timing. Inspected pollers are Node.js 20 and edge APIs Node.js 18. These are
test-environment observations, not claims about the production runtime.

Mainnet-test GraphQL metadata reports a missing deployment. Hoodi graph authorization/catch-up was not verified. The
test graph manifest/deploy scripts also contain filename-case and wrong-target naming problems. Backend CDK instantiates
production and both test stacks together: **do not run `cdk deploy --all`**.

Current remote main heads observed: backend `3955839c029c8f16b902aa1a9e5e157719b43f74`; subgraphs
`cd4c92d40cda077d4ba8335ab4b66882cee99863`. Running test backend source commits could not be established from inspected
deployment metadata.

## Recommended verification plan

1. Use a dedicated persistent fork of fresh mainnet as the authoritative contract/backend/Graph Node migration
   environment. Keep its RPC, backend state and indexer namespace isolated. Exercise real current legacy contracts,
   assets, liquidity and Safe threshold, plus locally advanced 30-day boundaries. Label impersonation, time advancement
   and fault injection.
2. Keep deterministic pinned regression forks alongside a refreshed migration rehearsal. Do not present historical exit
   success or synthetic funding as current liquidity proof.
3. Prepare, but do not deploy, an optional separately named mainnet-shaped Hoodi environment for public-network
   operations. Clearly identify test dependencies/mocks; it cannot establish actual mainnet liquidity or liquidation
   success.
4. Preserve both existing test stacks, balances, buckets, schedules and histories. Any future deployment requires
   explicit environment/state/configuration approval and exact scoped targets.
5. Create isolated implementation branches from each freshly fetched `origin/main`, with linked
   contracts/backend/subgraph PRs. Preserve the unrelated dirty rETH checkout. Frontend implementation is out of scope;
   a handover document and release gate are required.

## Verification access (updated after configuration)

- Existing local Docker daemon is available (29.9.2); no containers were started/changed.
- Public mainnet RPC historical `eth_call` at block 23,481,656 returned HTTP 403: archive requests require a personal
  token.
- The initial local HTTP 401 diagnosis was incorrect: an ad-hoc parser included quote/comment characters in the
  endpoint. Using Node's standard `util.parseEnv` resolved it. The configured Alchemy endpoint passes chain ID 1,
  current block, historical `eth_call`, historical `eth_getCode` and historical `eth_getStorageAt` at block 23,481,656.
  Its URL/key were not printed. The redacting Foundry wrapper uses the standard parser.
- Contracts GitHub Actions currently lists no repository secret names. No secret was created or uploaded. `origin/main`
  has no tracked Actions workflow; unmerged review-branch workflows are not existing main CI.

Local archive access is available. The user will configure encrypted GitHub `MAINNET_RPC` secrets; hosted CI remains a
separate gate until its actual runs pass. Secret values must be the complete URL without `.env` quotes/comments. Never
paste credentials in chat.

## Decisions approved before implementation

1. Implement/test the exact-amount one-shot legacy handoff and zero-live-legacy-claim gate for review; no production
   execution.
2. Implement configurable, disabled-by-default execution; exact production risk parameters remain separately approved.
3. Frontend code is out of scope. Deliver a team handover document and compatibility release gate.
4. The user configures local archive access and encrypted CI secrets. No agent secret uploads are authorized.

## Current exit measurement (not full migration evidence)

The real legacy protocol-principal exit succeeds on a local mainnet fork at block 26,255,470.
`tests/v2/fork/LegacyExitProbe.t.sol` measures **1.288290251823409274 ETH** received by the old manager, with its
principal set to zero. Adapter rounding residue remains: **150 native principal atoms / 121 Beefy share atoms**. These
are not ETH amounts and are not silently swept or counted as migrated capital. IDs 1–9 were already cleared in the
baseline; this is not a new ID 4 withdrawal. An exact current quote, full atomic Safe cutover and both new protocol
credits are still separate required tests.
