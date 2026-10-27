# V2 dependency review

This is a scoped dependency assessment, not a clean-bill-of-health claim. Public deployment remains gated.

The portable lock pins Solidity libraries OpenZeppelin5.2.0 and solmate6.8.0; test-framework/Uniswap Git sources use
exact commit hashes over HTTPS. Clean `npm ci --ignore-scripts --no-audit` succeeded in a separate empty directory,
without touching the original rETH checkout or running dependency lifecycle scripts. The committed npm lock contains no
workstation paths or authenticated RPC URLs.

Current `npm audit --json`: **0 critical,0 high,2 moderate,5 low**. The two moderate package entries describe the same
OpenZeppelin Bytes advisory. The five low entries describe the developer-tool dependency chain below; they are not five
deployed Solidity defects.

| Advisory / affected dependency                                                                                                                             | Reachability and disposition                                                                                                                                                                                                                                                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [GHSA-9rcw-c2f9-2j55](https://github.com/advisories/GHSA-9rcw-c2f9-2j55), OpenZeppelin contracts + upgradeable5.2                                          | `Bytes.lastIndexOf(bytes,bytes1,uint256)` can read out of bounds for an empty buffer. The V2 dependency paths use Initializable/UUPS/ERC1967, ReentrancyGuard, SafeERC20 and Math; they do not call this Bytes function. Do not describe this advisory as fixed by the V2 work. Retain the reviewed5.2 baseline for this candidate; a library update needs separate build/layout/runtime review. |
| [GHSA-848j-6mx2-7j84](https://github.com/advisories/GHSA-848j-6mx2-7j84), elliptic via upgrades-core → ethereumjs-util / ethereum-cryptography / secp256k1 | Developer validation tooling, not deployed contract code or production signing. npm reports no available transitive fix. The validation commands do not load a production key. Retain/report the exposure; do not assert every dependency is patched.                                                                                                                                            |

The CLI/tooling uses ethers6.17.0 rather than the earlier vulnerable websocket dependency combination. Source and
storage-layout checks must still run after any lock change; a dependency audit does not validate arithmetic, roles,
callback behavior, mainnet capacity or treasury settlement.

This work does not attest the deployed backend's AWS Node.js patch state. Host/runtime patch verification is separate
from an npm lock audit and requires the explicitly approved environment review.
