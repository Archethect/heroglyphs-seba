# Manager verification map

`ManagerTestBase.t.sol` uses explicitly synthetic 1:1 token/venue mocks. It proves internal accounting and failure
rollback, not liquidation prices. Real external calls and Safe migration are in `../fork/`.

Each manager entry-point folder exercises its branching tree. Shared authorization matrix in `setOperator/` calls
**every** maintenance selector as an unprivileged address; `SafeMaintenance` proves the Safe alternative. Each OR-clause
in configuration/import checks has separate rejection cases, not just aggregate coverage.

| Entry point                      | Required cases                                                                                                                                                                        |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| initialize                       | locked implementation/reinitialization, every missing-code identity, aliases/self references, wrong ERC4626 asset, zero/nonzero operator, disabled defaults                           |
| bindVaults                       | Safe only, once, reciprocal manager/asset/basis/treasury, equal vaults, intake gate                                                                                                   |
| depositFunds                     | pool only, positive input, disabled/recovered, odd wei, 0/100 weights, future-only changes, forced ETH quarantine                                                                     |
| configureExecution / flags       | Safe only, fixed graph/recipient, every zero cap, previous allowance, disable-before-change, bound/ready executor, irreversible retirement                                            |
| deployProtocolPrincipal          | each leg, exact ETH spend, actual token credit, no supporter liabilities, route/vault misreport or partial input, minima, deadline, caps, rollback                                    |
| convertEthRewards                | reward ETH only; both investment buckets untouched, actual BOLD delta, no refund misclassification, sibling failure isolation                                                         |
| onYieldReceived / convertHarvest | authenticated leaf, both buckets/legs, physical backing, post-retirement callback, sibling outage isolation, exact consumption and clear approvals                                    |
| convertBoldToSBold / donateSBold | classified inventory only, positive caller floor plus independent canonical quote, unavailable/misreport mint, completed recipient delta, retry and clear approvals                   |
| legacy import                    | exact identities/chain/amount/expiry, disabled setup, immutable arm, locked version, full investment assignment, single use, recovered state                                          |
| surplus / rescue / recovery      | unassigned-only ETH classification, all core identities blocked, exact recipient delta, every classified buffer, failure rollback, repeat rejection and newly received terminal carry |
| upgrade                          | Safe not backend, locked initializers, live balances/links/config preserved, actual subsequent operation                                                                              |

Stateful invariant: synthetic cash + both native inventories + BOLD + sBOLD + protocol backing + completed donations
equals received reward ETH + authenticated synthetic carry, with all relevant approvals zero between actions. 256 runs ×
64 calls; deterministic reachability and injected-custody-leak negative controls prevent vacuous success.

Run commands and measured coverage boundaries are in `docs/V2_IMPLEMENTATION_AND_RELEASE.md`. Full measured V2 coverage
excludes no executable new source, but does not claim inherited libraries or deployed external protocol coverage.
