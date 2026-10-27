# Disabled deployment and read-only preflight evidence

No public deployment, signature, cutover or fund movement was performed. All deployments below are disposable local
fork fixtures. The release approval gate remains in force.

`DeploySebaV2.run(bytes32 approvedSafeOwnersHash)` creates three standard ERC1967 proxies with atomic initializers,
locked UUPS implementations, and the fixed treasury Safe as authority from initialization. It also creates the fixed
manager executor. Initial operators, limits, entry, harvest, intake and execution remain unset/disabled. The script
prints a `seba-v2-deployment-v1` JSON manifest and a **separate** Safe-only `bindVaults` target/calldata. It never binds
from the deployer, approves tokens, funds positions, changes the pool pointer or performs the legacy handoff.

The owner hash is `keccak256(abi.encode(Safe.getOwners()))`, preserving the exact returned order. Independently review
the live signer list before approving that input. Counts alone are insufficient: the script also requires the fixed
mainnet Safe's threshold 3, seven reviewed owners, no enabled modules and zero guard. A changed legacy pool/reward graph
aborts before contract creation. The large script-runner bytecode is not a contract deployed to mainnet; production
artifact size gates apply separately to the created implementations, proxy and executor.

## Commands and measured results

```sh
node tools/v2/run-foundry.mjs --env-file /absolute/path/to/ignored/.env test --match-contract DeploySebaV2ForkTest -vv
node tools/v2/run-foundry.mjs --env-file /absolute/path/to/ignored/.env coverage --match-contract DeploySebaV2ForkTest --report lcov --report-file /private/tmp/seba-v2-deployment-coverage.info
node --test tools/v2/preflight.test.cjs
node_modules/.bin/solhint --config .solhint-v2.json script/v2/DeploySebaV2.s.sol
node_modules/.bin/prettier --check script/v2/DeploySebaV2.s.sol tests/v2/deployment/fork/run/DeploySebaV2.t.sol tools/v2/preflight.cjs tools/v2/preflight.test.cjs
```

- **11/11 fork tests** pass at mainnet block **26,255,670**. The successful fixture verifies all proxy implementation
  slots, implementation initializer locks, Safe authority, disabled defaults, exact separate binding payload and
  rejection of deployer binding. Test-only Safe impersonation proves that payload works; it is not a production signature.
- Deployment script measured LCOV: **52/52 lines, 6/6 Foundry branches, 3/3 functions**, with no script-source exclusion.
  This is separate from the production onchain-source unit-coverage report. Deployment tests live under `fork/` so the
  unit-only coverage glob does not silently count mainnet behavior as synthetic unit evidence.
- **53/53 Node tests** pass: malformed/aliased manifests, Safe drift, wrong proxy/implementation runtime, unlocked
  initializers, foreign integration graph, enabled/default-state drift, correct bind phases, local-only labeling,
  immutable runtime reconstruction, RPC error redaction and the complete pinned read sequence.
- Initial RED evidence was the missing deployment source/compiler error and missing preflight module; both are now GREEN.

## Preflight usage and scope

```sh
node tools/v2/preflight.cjs --manifest /absolute/path/to/approved-candidate.json --env-file /absolute/path/to/ignored/.env
node tools/v2/preflight.cjs --manifest /absolute/path/to/approved-candidate.json --env-file /absolute/path/to/ignored/.env --block 26255670
```

The CLI uses `MAINNET_RPC` from the environment or Node's standard `util.parseEnv`, never an ad-hoc dotenv parser.
It never creates a signer or submits a transaction. Reads are pinned to one block and its hash is checked again at the
end. Failures print only a known check identifier or a generic message, not upstream RPC errors/credentials.

Use `phase: "unbound"` for the script output; after the separately approved Safe bind, explicitly update the reviewed
manifest to `phase: "bound"`. The gate expects a fresh disabled candidate, **not** a fully configured/live deployment.
It verifies the implementation slots, actual initializer namespace storage, UUPS UUIDs, exact compiled runtime including
constructor immutables, Safe signer security, reciprocal identities and default/empty **accounting** state. Independent
physical custody, allowances, historical legacy claims/orders, runtime source verification, risk-pack approval and
post-configuration/cutover checks remain required release gates; this tool does not replace them.

Local fixture manifests are explicitly marked `localOnly` and accept only a loopback `SEBA_V2_LOCAL_RPC`; their declared
test operator is not a production default. A fresh isolated fork on port 28645 passed all **36 preflight gates** at local
block **26,255,678**, hash `0x612465ba4afa03b01203c6d2a699320cfb45a19fc13bb9e32cbc1ff75fa10900`, using current optimized
artifacts and the existing local fixture tool. Local Safe impersonation and synthetic gas funding are disclosed by that
fixture. This proves tooling against deployed local contracts, not public deployment approval. The older active fork
was untouched: its latest changed pool pointer and its historical outdated runtime both correctly failed the gate.

Coverage writes unoptimized artifacts. Restore a normal optimized build before deployed-runtime comparison; do not
mistake coverage artifacts or an older fixture for the current reviewed release artifact.
