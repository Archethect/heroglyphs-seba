# V2 execution-parameter research — not approved configuration

All deployed candidates must still start disabled/zero. These observations are test evidence for governance review, not
permission to enable routes or a claim that these are optimal/safe under every market condition.

## Tested small pilot candidate

`test_researchOnlyPilotLimitsAllFiveRealRoutes` passed all five actual routes on a fresh mainnet fork at block
**26,255,943**, parent hash `0x36d1f837e43cb138b86d4dd8b1d1abc8f9c5240983f5c8bd3a68ac2668cf49c1`. Inputs were synthetic
local ETH and locally transferred real treasury tokens; no production transaction occurred.

| Setting                          |                  Research value | Meaning                                                                |
| -------------------------------- | ------------------------------: | ---------------------------------------------------------------------- |
| maxEth                           |                  1 ETH per call | Applies independently to ETH mint/invest/reward-conversion calls       |
| maxReth                          |                 1 rETH per call | Carry conversion cap, not permission to sell supporter principal       |
| maxYsy                           |          1,000 ysyBOLD per call | Direct zero-loss redemption cap                                        |
| maxDeadline                      |                     300 seconds | Payload still uses its own tighter deadline                            |
| slippageBps                      |                              50 | Independent route floors; not a total guaranteed end-to-end loss bound |
| pegBps                           |                             100 | USDC/BOLD peg guards; not a stablecoin solvency guarantee              |
| maxMintFeeWad                    |                            1e15 | Reject Rocket Pool mint fees above 0.1%                                |
| ethMaxAge                        |                   3,600 seconds | Fail closed if the selected feed exceeds this bound                    |
| usdcMaxAge                       |                  90,000 seconds | 25-hour research variant, not a verified feed heartbeat/SLA            |
| reportMaxAge / reportMaxBlockLag | 172,800 seconds / 20,000 blocks | Both Rocket Pool report gates apply                                    |
| wethUsdcFee / rethWethFee        |                       500 / 100 | Uniswap fee units: 0.05% / 0.01%; fixed reviewed pool paths            |

Actual atomic outputs from that probe:

| Route/input          |           Output atoms |
| -------------------- | ---------------------: |
| 1 ETH → rETH         |     851134298145220632 |
| 1 ETH → BOLD         | 2401320749478871452043 |
| 1 ETH → ysyBOLD      | 2182686802695118590306 |
| 1 rETH → BOLD        | 2819405987057981892099 |
| 1,000 ysyBOLD → BOLD | 1100107555926599909393 |

These sequential local route outputs are not executable production quotes. The test requests minimal caller floors to
isolate the independent executor guards. The real backend additionally supplies its exact independently derived caller
minimum and simulates the complete manager call, including temporary approvals and canonical native basis.

Separate component tests also pass 1/100 ETH BOLD routes, 1/70 ETH ysyBOLD investment and actual treasury-sized native
redemptions under the larger, explicitly test-only fixture. Passing a large test does not justify adopting its 200 ETH,
100 rETH or 300,000 ysyBOLD caps. Begin with separately approved small operations and review price impact/gas before
raising any cap. Native supporter deposit/withdrawal itself does not require those DEX routes.

## Recommendation and remaining approval work

Use the small-cap candidate as the **starting point for review**, not as an automatically selected production pack. Keep
the 50bps independent floors and zero accepted Yearn redemption loss; do not widen them merely to make a test pass.
Approve manager caps, leaf harvest caps and backend per-asset minima coherently; never combine ETH and yBOLD principal.
Set economic minima from measured gas and expected donation size at execution time, not a synthetic tiny-harvest test.

Verify selected feed ownership/addresses, published heartbeat/deviation and actual multi-day update behavior before
approving freshness bounds. At block **26,255,949**, the configured ETH proxy `0xc005...673aD` reported ETH/USD, 8
decimals and age948s; canonical `0x5f4e...b8419` reported age84s and a different contemporaneous answer. Both expose
`aggregator()`, so the configured address is a proxy, not a silently pinned implementation. USDC proxy `0x8fFf...18f6`
reported age49,716s. This is an onchain observation, not proof of a maximum heartbeat. The official feed pages were not
retrievable by the research client; heartbeat attestation remains open. Consult
[Chainlink's feed documentation](https://docs.chain.link/data-feeds) and the exact feed's official metadata before
approval. Feed heartbeat and `updatedAt` are separate checks, and a healthy snapshot does not guarantee future
freshness.

Registry entry addresses must be refreshed/pinned from the reviewed chain and monitored; no numeric approval authorizes
a changed integration. Approve alerting and operator gas funding separately. A stale feed, peg failure, excessive fee,
registry change or unavailable route leaves assigned inventory for retry or native recovery, not an automatic fallback.
