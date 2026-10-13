# yBOLD yield and security note

Observation date: 2026-08-25. On-chain integration snapshot: Ethereum block `25,831,161`. APY values are observations,
not guarantees, and can change materially before migration.

## Current yield observations

- Beefy's official API reports `curve-eusd-usdc` total APY of approximately **0.90%**, composed of 0% vault APR and 0.90%
  trading APR, with a 9.5% Beefy performance-fee parameter. See the [live APY endpoint](https://api.beefy.finance/apy),
  [live breakdown endpoint](https://api.beefy.finance/apy/breakdown), and [API definitions](https://docs.beefy.finance/developer-documentation/beefy-api).
- Yearn's official yBOLD page reported approximately **10.7% estimated and 30-day APY**, about $5.86 million TVL, a 0%
  management fee, and a 10% performance fee. The allocation shown was approximately 78.2% wstETH Stability Pool, 12.8%
  rETH Stability Pool, and 8.95% WETH Stability Pool. See [Yearn BOLD](https://yearn.fi/v3/1/0x9F4330700a36B29952869fac9b33f45EEdd8A3d8).
- Yearn's [official yBOLD source](https://github.com/yearn/yBOLD) confirms that plain yBOLD is kept approximately 1:1
  with BOLD while profits are directed to st-yBOLD, making st-yBOLD the yield-bearing position used by this adapter.

The displayed APYs use different methodologies and time windows. They are useful observations, not a promise that the
future spread will persist. yBOLD can report losses; BOLD, USDC, or eUSD can depeg; incentives can disappear; and strategy
allocation or fees can change.

## Scenario estimate for yield reaching pybSeba

The table is an illustrative planning range on $300,000 of deployed principal. “Execution drag” includes expected Curve,
Uniswap, CowSwap, and amortized gas costs; it excludes principal entry/exit costs and assumes the keeper skips uneconomic
harvests. Yearn's displayed APY is treated as net of its displayed vault fee, so that fee is not subtracted twice.

| Scenario | Assumed st-yBOLD APY | Annual execution drag | Net delivered APY | Approx. annual yield |
| --- | ---: | ---: | ---: | ---: |
| Conservative | 2.50% | 0.35% | 2.15% | $6,450 |
| Base | 7.00% | 0.30% | 6.70% | $20,100 |
| Optimistic | 10.70% | 0.30% | 10.40% | $31,200 |

The adapter's steady-state harvest performs two Yearn redemptions, BOLD→USDC on Curve, USDC→WETH on Uniswap V3, and a
WETH unwrap. The unchanged manager then performs asynchronous ETH→BOLD through CowSwap and BOLD→sBOLD→pybSeba. Tests put
adapter deposit, claim, and retrieval paths in the several-hundred-thousand-gas range; exact production gas depends on
Yearn queues and current pool state. Swap configuration bounds each adapter swap at 0.50% from an independent reference,
and the manager separately applies its CowSwap limit. Those are loss ceilings, not expected costs.

Harvest monitoring should be daily with a **weekly target evaluation**, not quarterly. Execute only when unlocked expected
yield exceeds estimated gas plus swap/Cow friction by the operator's safety margin. Smaller or more frequent harvests can
turn an otherwise attractive APY into poor net yield.

## Security model and invariants

1. `principalValue` is denominated in yBOLD assets actually deposited into st-yBOLD; `principalShares` is the actual
   st-yBOLD share amount attributable to that book value.
2. Only unlocked value above `principalValue` is claimable. Yield-share conversion rounds down; partial principal share
   conversion rounds up. A full/over-sized final request redeems every remaining share and zeroes both counters.
3. Every state mutation precedes the external exit calls, and every failed external call reverts the whole transaction and
   restores manager deposit records and adapter accounting.
4. The adapter checks Chainlink round validity/freshness and uses Chainlink-derived WETH/USDC minimums. BOLD/USDC uses hard
   nominal parity minimums plus Curve's moving-average peg check; no same-pool spot quote sets its own minimum.
5. ERC-20 approvals are exact and reset to zero. Constructor checks code, token decimals, Curve coin order, and the
   BOLD→yBOLD→st-yBOLD asset graph.
6. Normal Yearn exits accept zero loss. Emergency exits can accept at most 1% by default and never more than the 10% hard
   contract cap. Insufficient liquidity is all-or-revert and retried later.
7. Pause and emergency mode block deposits and claims, never principal retrieval. Core assets cannot be rescued.
8. The adapter is non-upgradeable. Governance can change bounded risk parameters and roles; the existing YieldManager admin
   can retrieve/switch strategies, which remains the primary Seba governance trust assumption.

## CROPS and caller/incentive review

- **Censorship:** adapter admins can pause new capital/yield claims but cannot pause principal exits. Yearn liquidity,
  strategy shutdowns, USDC controls, and external oracle availability can still delay or prevent exits.
- **Rug/privilege:** adapter immutables and core-asset rescue prohibition limit adapter-admin theft. Existing YieldManager
  admins retain broad strategy-switch authority; Yearn and external protocol governance retain their documented powers.
- **Oracle/manipulation:** Chainlink and a Curve EMA are independent from the executed Uniswap/Curve spot. Hard nominal BOLD
  parity intentionally fails closed during a material depeg rather than realizing it silently.
- **Profit/incentives:** the automator controls harvest timing but receives no adapter payment. It can waste gas or delay
  yield, but cannot redirect proceeds: ETH is sent only to the role-bearing YieldManager and later credited to pybSeba.
- **Sybil:** no adapter accounting depends on identity count or voting weight. User-level ownership remains in the existing
  YieldManager deposit records.

## Static-analysis triage

An adapter-only Aderyn 0.6.8 pass completed with one high-severity pattern match and seven low-severity categories. The
high match treats constructor validation calls and `deposit` integration calls as unguarded reentrancy: constructor
creation is atomic and has no callable deployed runtime, while every state-changing integration entry point is protected
by OpenZeppelin `nonReentrant` and role checks. The low categories are the documented governance trust, literal/style
notices, mainnet-compatible PUSH0, ignored `_grantRole` boolean results, the Foundry-pinned `^0.8.28` pragma, and the
`IYieldVault` import required by Solidity's `@inheritdoc` resolution.

Slither 0.10.4 reported no untriaged result after reviewing its expected pattern matches. The complete first pass flagged:

- zero-output equality guards, which are intentional fail-closed sentinels;
- an unused Chainlink `startedAt` value, which is not part of the round-validity policy;
- missing zero-address checks on token constructor arguments, despite `_requireContract` checking both zero and bytecode;
- state writes after integration calls in `deposit`, which are protected by OpenZeppelin `nonReentrant`, role-gated, and
  must use the actual shares returned by the two Yearn deposits; and
- timestamp comparisons used only for oracle freshness and explicit accounting/availability bounds.

After excluding only those reviewed detector classes and naming-style notices, Slither reported zero results. The adapter's
optimized deployed bytecode is 14,732 bytes, leaving 9,844 bytes below the EIP-170 runtime limit.

Residual risks include Yearn/Liquity/Curve/Uniswap/Chainlink/CowSwap smart-contract risk, BOLD and USDC depeg/censorship,
Yearn governance and strategy allocation, unavailable withdrawal liquidity, oracle outages, MEV around public migration,
and the known old Beefy dust. The private-bundle/off-chain-freeze procedure addresses ordering and frontrunning but cannot
make the multi-signer Option A migration fully atomic.
