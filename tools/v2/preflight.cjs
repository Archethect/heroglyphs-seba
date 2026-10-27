#!/usr/bin/env node
"use strict";

// Read-only release gate. No Wallet, Signer, deployment factory or transaction-submission API is used.
const fs = require("node:fs");
const path = require("node:path");
const { parseEnv } = require("node:util");
const { JsonRpcProvider, Interface, AbiCoder, ZeroAddress, getAddress, keccak256, toUtf8Bytes } = require("ethers");

const FIXED = Object.freeze({
  treasury: "0x888D768764A2E304215247F0bA3457cCb0f0ab4f",
  pool: "0xe3B17b4533b339d3CBC26F57199d3fb937129894",
  oldManager: "0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269",
  reth: "0xae78736Cd615f374D3085123A210448E74Fc6393",
  weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  bold: "0x6440f144b7e50D6a8439336510312d2F54beB01D",
  yBold: "0x9F4330700a36B29952869fac9b33f45EEdd8A3d8",
  ysyBold: "0x23346B04a7f55b8760E5860AA5A77383D63491cD",
  rocketStorage: "0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46",
  swapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
  curvePool: "0xEFc6516323FbD28e80B85A497B65A86243a54B3E",
  ethUsdFeed: "0xc0053f3FBcCD593758258334Dfce24C2A9A673aD",
  usdcUsdFeed: "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
});
const IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
const INITIALIZABLE_SLOT = "0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00";
const GUARD_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8";
const UINT64_MAX = (1n << 64n) - 1n;
const SENTINEL = "0x0000000000000000000000000000000000000001";
const ROOT = path.resolve(__dirname, "../..");
const coder = AbiCoder.defaultAbiCoder();
class PreflightError extends Error {
  constructor(check) {
    super(check);
    this.check = check;
  }
}
const requireCheck = (condition, name) => {
  if (!condition) throw new PreflightError(name);
};
const same = (a, b) => typeof a === "string" && typeof b === "string" && a.toLowerCase() === b.toLowerCase();
const zero = (n) => BigInt(n) === 0n;
const address = (value) => {
  requireCheck(typeof value === "string", "manifest.address");
  try {
    return getAddress(value);
  } catch {
    throw new PreflightError("manifest.address");
  }
};

function normalizeManifest(input) {
  requireCheck(input && typeof input === "object", "manifest");
  const local = input.schema === "seba-v2-local-fixture-v1";
  requireCheck(local || input.schema === "seba-v2-deployment-v1", "manifest.schema");
  requireCheck(Number(input.chainId) === 1, "manifest.chainId");
  if (local) requireCheck(input.localOnly === true && input.mainnetFork === true, "manifest.localOnly");
  const m = { ...input, localOnly: local, phase: local ? "bound" : input.phase };
  requireCheck(["unbound", "bound"].includes(m.phase), "manifest.phase");
  for (const name of ["treasury", "pool", "oldManager"]) {
    m[name] = address(input[name]);
    requireCheck(same(m[name], FIXED[name]), `manifest.${name}`);
  }
  for (const [name, impl] of [
    ["manager", "managerImplementation"],
    ["rethVault", "rethImplementation"],
    ["ysyBoldVault", "ysyBoldImplementation"],
  ]) {
    const metadata = input[name];
    m[name] = address(typeof metadata === "object" ? metadata.address : metadata);
    m[impl] = address(typeof metadata === "object" ? metadata.implementation : input[impl]);
  }
  m.executor = address(typeof input.executor === "object" ? input.executor.address : input.executor);
  m.deployer = address(input.deployer || (local ? ZeroAddress : undefined));
  m.initialOperator = address(local ? input.operator : input.initialOperator);
  if (!local) {
    requireCheck(!same(m.deployer, ZeroAddress), "manifest.deployer");
    requireCheck(same(m.initialOperator, ZeroAddress), "manifest.initialOperator");
  }
  requireCheck(/^0x[0-9a-fA-F]{64}$/.test(input.safeOwnersHash || ""), "manifest.safeOwnersHash");
  requireCheck(BigInt(input.safeOwnersHash) !== 0n, "manifest.safeOwnersHash");
  const identities = [
    m.manager,
    m.managerImplementation,
    m.rethVault,
    m.rethImplementation,
    m.ysyBoldVault,
    m.ysyBoldImplementation,
    m.executor,
    ...Object.values(FIXED),
  ];
  requireCheck(
    identities.every((a) => !same(a, ZeroAddress)),
    "manifest.zeroIdentity",
  );
  requireCheck(new Set(identities.map((a) => a.toLowerCase())).size === identities.length, "manifest.alias");
  const bind = new Interface(["function bindVaults(address,address)"]).encodeFunctionData("bindVaults", [
    m.rethVault,
    m.ysyBoldVault,
  ]);
  if (!local) {
    requireCheck(same(input.bootstrapBindTo, m.manager), "manifest.bootstrapBindTo");
    requireCheck(same(input.bootstrapBindData, bind), "manifest.bootstrapBindData");
  }
  m.bootstrapBindTo = m.manager;
  m.bootstrapBindData = bind;
  return m;
}

function artifact(name, artifactRoot = path.join(ROOT, "out")) {
  return JSON.parse(fs.readFileSync(path.join(artifactRoot, `${name}.sol`, `${name}.json`), "utf8"));
}

// Solc placeholders are replaced with the exact constructor immutables, never simply ignored.
function expectedRuntime(a, values) {
  let code = a.deployedBytecode.object.toLowerCase();
  requireCheck(/^0x[0-9a-f]*$/.test(code) && code.length > 2, "artifact.runtime");
  const declarations = new Map();
  function visit(node) {
    if (!node || typeof node !== "object") return;
    if (node.nodeType === "VariableDeclaration" && node.mutability === "immutable")
      declarations.set(String(node.id), node.name);
    for (const value of Object.values(node))
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === "object") visit(value);
  }
  visit(a.ast);
  for (const [id, references] of Object.entries(a.deployedBytecode.immutableReferences || {})) {
    const value = values[declarations.get(id)] || values.__self;
    requireCheck(value, "artifact.immutable");
    const word = coder.encode(["address"], [value]).slice(2).toLowerCase();
    for (const ref of references) {
      requireCheck(ref.length === 32, "artifact.immutableWidth");
      const start = 2 + ref.start * 2;
      code = code.slice(0, start) + word + code.slice(start + ref.length * 2);
    }
  }
  return code;
}

async function readSnapshot(provider, manifest, options = {}) {
  const m = normalizeManifest(manifest);
  const blockTag = options.blockTag === undefined ? await provider.getBlockNumber() : Number(options.blockTag);
  requireCheck(Number.isSafeInteger(blockTag) && blockTag >= 0, "block.number");
  const block = await provider.getBlock(blockTag);
  requireCheck(block && block.hash, "block.unavailable");
  const network = await provider.getNetwork();
  const load = (name) => artifact(name, options.artifactRoot);
  const call = async (to, abi, name, args = []) => {
    const iface = new Interface(abi);
    const raw = await provider.call({ to, data: iface.encodeFunctionData(name, args), blockTag });
    const result = iface.decodeFunctionResult(name, raw);
    return result.length === 1 ? result[0] : result;
  };
  const views = async (to, abi, names) =>
    Object.fromEntries(await Promise.all(names.map(async (name) => [name, await call(to, abi, name)])));
  const safeAbi = [
    "function getOwners() view returns(address[])",
    "function getThreshold() view returns(uint256)",
    "function getModulesPaginated(address,uint256) view returns(address[],address)",
  ];
  const legacyAbi = [
    "function sebaPool() view returns(address)",
    "function BOLD() view returns(address)",
    "function sBOLD() view returns(address)",
    "function sebaVault() view returns(address)",
  ];
  const poolAbi = ["function yieldManager() view returns(address)", "function sebaVault() view returns(address)"];
  const ma = load("YieldManagerV2");
  const ra = load("RethSupporterVault");
  const ya = load("YsyBoldSupporterVault");
  const ea = load("SebaV2Executor");
  const pa = load("ERC1967Proxy");
  const safe = await views(m.treasury, safeAbi, ["getOwners", "getThreshold"]);
  [safe.modules, safe.next] = await call(m.treasury, safeAbi, "getModulesPaginated", [SENTINEL, 1]);
  safe.guard = await provider.getStorage(m.treasury, GUARD_SLOT, blockTag);
  const old = await views(m.oldManager, legacyAbi, ["sebaPool", "BOLD", "sBOLD", "sebaVault"]);
  const pool = await views(m.pool, poolAbi, ["yieldManager", "sebaVault"]);
  const proxies = [];
  for (const [proxy, implementation, a] of [
    [m.manager, m.managerImplementation, ma],
    [m.rethVault, m.rethImplementation, ra],
    [m.ysyBoldVault, m.ysyBoldImplementation, ya],
  ]) {
    proxies.push({
      proxy,
      implementation,
      slot: await provider.getStorage(proxy, IMPLEMENTATION_SLOT, blockTag),
      proxyInitializer: await provider.getStorage(proxy, INITIALIZABLE_SLOT, blockTag),
      implementationInitializer: await provider.getStorage(implementation, INITIALIZABLE_SLOT, blockTag),
      uuid: await call(implementation, a.abi, "proxiableUUID"),
      implementationCodeMatches: same(
        await provider.getCode(implementation, blockTag),
        expectedRuntime(a, { __self: implementation }),
      ),
      proxyCodeMatches: same(await provider.getCode(proxy, blockTag), expectedRuntime(pa, {})),
    });
  }
  const manager = await views(m.manager, ma.abi, [
    "treasury",
    "sebaPool",
    "bold",
    "sBold",
    "pybSeba",
    "reth",
    "ysyBold",
    "yBold",
    "weth",
    "usdc",
    "intakeEnabled",
    "executionEnabled",
    "buffersRecovered",
    "executor",
    "maximumEth",
    "pendingBold",
    "pendingSBold",
    "rethBps",
    "ysyBoldBps",
    "weightVersion",
    "legacyHandoff",
    "legacyExpectedEth",
    "legacyExpiry",
    "legacyWeightVersion",
    "legacyImported",
    "legacyManifest",
  ]);
  manager.vaults = await Promise.all([0, 1].map((i) => call(m.manager, ma.abi, "vaults", [i])));
  manager.pendingEth = await Promise.all([0, 1, 2].map((i) => call(m.manager, ma.abi, "pendingEth", [i])));
  manager.maximumYieldTokens = await Promise.all([0, 1].map((i) => call(m.manager, ma.abi, "maximumYieldTokens", [i])));
  manager.harvestInventory = await Promise.all(
    [0, 1].flatMap((leg) => [0, 1].map((bucket) => call(m.manager, ma.abi, "harvestInventory", [leg, bucket]))),
  );
  const queriedOperators = [...new Set([m.initialOperator, m.deployer, m.treasury].map((a) => a.toLowerCase()))];
  manager.operators = Object.fromEntries(
    await Promise.all(
      queriedOperators.map(async (operator) => [operator, await call(m.manager, ma.abi, "operators", [operator])]),
    ),
  );
  const vaults = [];
  for (const [vault, a] of [
    [m.rethVault, ra],
    [m.ysyBoldVault, ya],
  ]) {
    const v = await views(vault, a.abi, [
      "treasury",
      "manager",
      "asset",
      "basisAsset",
      "entriesEnabled",
      "harvestEnabled",
      "minimumBasis",
      "maximumHarvest",
      "nextPositionId",
      "recoveryState",
      "recoveryInstance",
    ]);
    v.buckets = await Promise.all([0, 1].map((i) => call(vault, a.abi, "bucket", [i])));
    v.operators = await Promise.all(queriedOperators.map((operator) => call(vault, a.abi, "operators", [operator])));
    vaults.push(v);
  }
  Object.assign(
    vaults[0],
    await views(m.rethVault, ra.abi, ["rocketStorage", "maximumReportAge", "maximumReportBlockLag"]),
  );
  const executor = await views(m.executor, ea.abi, ["manager", "treasury", "configuration", "limits", "enabled"]);
  executor.codeMatches = same(
    await provider.getCode(m.executor, blockTag),
    expectedRuntime(ea, { manager: m.manager, treasury: m.treasury }),
  );
  const assetAbi = ["function asset() view returns(address)"];
  const assetGraph = await Promise.all(
    [FIXED.ysyBold, FIXED.yBold, old.sBOLD, old.sebaVault].map((token) => call(token, assetAbi, "asset")),
  );
  const registryAbi = ["function getAddress(bytes32) view returns(address)"];
  const registryReth = await call(FIXED.rocketStorage, registryAbi, "getAddress", [
    keccak256(toUtf8Bytes("contract.addressrocketTokenRETH")),
  ]);
  const curveAbi = ["function coins(uint256) view returns(address)"];
  const curveCoins = await Promise.all([0, 1].map((i) => call(FIXED.curvePool, curveAbi, "coins", [i])));
  // Catch a reorg during the multiple pinned reads instead of mixing inconsistent canonical observations.
  requireCheck(same((await provider.getBlock(blockTag))?.hash, block.hash), "block.reorg");
  return {
    chainId: network.chainId,
    block: { number: block.number, hash: block.hash },
    safe,
    old,
    pool,
    proxies,
    manager,
    vaults,
    executor,
    assetGraph,
    registryReth,
    curveCoins,
  };
}

function validateSnapshot(s, manifest) {
  const m = normalizeManifest(manifest);
  const checks = [];
  function check(condition, name) {
    requireCheck(condition, name);
    checks.push(name);
  }
  check(BigInt(s.chainId) === 1n, "chain.mainnet");
  check(s.safe.getOwners.length === 7 && BigInt(s.safe.getThreshold) === 3n, "safe.thresholdAndOwnerCount");
  check(same(keccak256(coder.encode(["address[]"], [s.safe.getOwners])), m.safeOwnersHash), "safe.reviewedOwners");
  check(s.safe.modules.length === 0 && same(s.safe.next, SENTINEL), "safe.noModules");
  check(zero(s.safe.guard), "safe.noGuard");
  check(same(s.pool.yieldManager, FIXED.oldManager) && same(s.old.sebaPool, FIXED.pool), "legacy.poolManager");
  check(same(s.old.BOLD, FIXED.bold) && same(s.pool.sebaVault, s.old.sebaVault), "legacy.rewardGraph");
  check(
    new Set([s.old.sBOLD, s.old.sebaVault, ...Object.values(FIXED)].map((a) => a.toLowerCase())).size ===
      Object.values(FIXED).length + 2,
    "legacy.distinctTokens",
  );
  check(
    s.assetGraph.every((a, i) => same(a, [FIXED.yBold, FIXED.bold, FIXED.bold, s.old.sBOLD][i])),
    "tokens.assetGraph",
  );
  check(
    same(s.registryReth, FIXED.reth) && s.curveCoins.every((a, i) => same(a, [FIXED.bold, FIXED.usdc][i])),
    "venues.assetGraph",
  );
  for (const [i, p] of s.proxies.entries()) {
    check(same(getAddress(`0x${p.slot.slice(-40)}`), p.implementation), `proxy.${i}.implementationSlot`);
    check(
      BigInt(p.proxyInitializer) === 1n && BigInt(p.implementationInitializer) === UINT64_MAX,
      `proxy.${i}.initializerLock`,
    );
    check(same(p.uuid, IMPLEMENTATION_SLOT), `proxy.${i}.uupsUUID`);
    check(p.implementationCodeMatches === true && p.proxyCodeMatches === true, `proxy.${i}.compiledRuntime`);
  }
  const g = s.manager;
  check(
    ["treasury", "bold", "reth", "ysyBold", "yBold"].every((name) => same(g[name], FIXED[name])) &&
      same(g.sebaPool, FIXED.pool) &&
      same(g.sBold, s.old.sBOLD) &&
      same(g.pybSeba, s.old.sebaVault),
    "manager.identities",
  );
  check(
    g.vaults.every((a, i) => same(a, m.phase === "bound" ? [m.rethVault, m.ysyBoldVault][i] : ZeroAddress)),
    "manager.bindingPhase",
  );
  check(g.intakeEnabled === false && g.executionEnabled === false && g.buffersRecovered === false, "manager.disabled");
  check(
    [g.executor, g.weth, g.usdc, g.legacyHandoff].every((a) => same(a, ZeroAddress)) &&
      [
        g.maximumEth,
        g.pendingBold,
        g.pendingSBold,
        g.legacyExpectedEth,
        g.legacyExpiry,
        g.legacyWeightVersion,
        ...g.pendingEth,
        ...g.maximumYieldTokens,
        ...g.harvestInventory,
      ].every(zero) &&
      g.legacyImported === false &&
      zero(g.legacyManifest),
    "manager.unconfiguredAndEmpty",
  );
  check(
    BigInt(g.rethBps) === 5000n && BigInt(g.ysyBoldBps) === 5000n && BigInt(g.weightVersion) === 1n,
    "manager.initialWeights",
  );
  check(
    Object.entries(g.operators).every(
      ([a, enabled]) => enabled === (!same(m.initialOperator, ZeroAddress) && same(a, m.initialOperator)),
    ),
    "manager.initialOperatorOnly",
  );
  for (const [i, v] of s.vaults.entries()) {
    check(
      same(v.manager, m.manager) &&
        same(v.treasury, FIXED.treasury) &&
        same(v.asset, [FIXED.reth, FIXED.ysyBold][i]) &&
        same(v.basisAsset, [ZeroAddress, FIXED.yBold][i]),
      `vault.${i}.identities`,
    );
    check(
      v.entriesEnabled === false &&
        v.harvestEnabled === false &&
        [v.minimumBasis, v.maximumHarvest, v.recoveryState, v.recoveryInstance].every(zero) &&
        BigInt(v.nextPositionId) === 1n &&
        v.operators.every((enabled) => enabled === false) &&
        v.buckets.every((bucket) => [...bucket].every(zero)),
      `vault.${i}.disabledAndEmpty`,
    );
  }
  check(
    same(s.vaults[0].rocketStorage, FIXED.rocketStorage) &&
      zero(s.vaults[0].maximumReportAge) &&
      zero(s.vaults[0].maximumReportBlockLag),
    "vault.reth.unsetFreshness",
  );
  const e = s.executor;
  check(
    same(e.manager, m.manager) &&
      same(e.treasury, FIXED.treasury) &&
      Object.entries({ ...FIXED, manager: m.manager })
        .filter(([name]) => !["pool", "oldManager"].includes(name))
        .every(([name, a]) => same(e.configuration[name], a)),
    "executor.identities",
  );
  check(
    e.enabled === false && [...e.limits].every((v) => (typeof v === "string" ? same(v, ZeroAddress) : zero(v))),
    "executor.disabledAndUnset",
  );
  check(e.codeMatches === true, "executor.compiledRuntime");
  return {
    schema: "seba-v2-preflight-v1",
    readOnly: true,
    localOnly: m.localOnly,
    chainId: 1,
    blockNumber: s.block.number,
    blockHash: s.block.hash,
    phase: m.phase,
    manager: m.manager,
    rethVault: m.rethVault,
    ysyBoldVault: m.ysyBoldVault,
    executor: m.executor,
    safeOwnersHash: m.safeOwnersHash,
    checks,
    bootstrapBindTo: m.bootstrapBindTo,
    bootstrapBindData: m.bootstrapBindData,
  };
}

function safeFailure(error) {
  return error instanceof PreflightError
    ? `Preflight failed: ${error.check}. No transaction was submitted.`
    : "Preflight failed; verify the manifest, pinned chain state and RPC availability.";
}

async function main(args = process.argv.slice(2)) {
  const values = {};
  for (let i = 0; i < args.length; i += 2) {
    requireCheck(["--manifest", "--env-file", "--block"].includes(args[i]) && args[i + 1], "arguments");
    requireCheck(values[args[i]] === undefined, "arguments.duplicate");
    values[args[i]] = args[i + 1];
  }
  requireCheck(values["--manifest"], "arguments.manifest");
  const manifest = normalizeManifest(JSON.parse(fs.readFileSync(values["--manifest"], "utf8")));
  const envFile = values["--env-file"] || path.join(ROOT, ".env");
  const env = fs.existsSync(envFile) ? parseEnv(fs.readFileSync(envFile, "utf8")) : {};
  const rpc = manifest.localOnly ? process.env.SEBA_V2_LOCAL_RPC : process.env.MAINNET_RPC || env.MAINNET_RPC;
  requireCheck(rpc, "rpc.configuration");
  if (manifest.localOnly) {
    const url = new URL(rpc);
    requireCheck(
      url.protocol === "http:" &&
        ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) &&
        !url.username &&
        !url.password,
      "rpc.localOnly",
    );
  }
  const provider = new JsonRpcProvider(rpc, undefined, { cacheTimeout: -1 });
  try {
    // provider errors are never logged; even credential-bearing request details stay private.
    const snapshot = await readSnapshot(provider, manifest, { blockTag: values["--block"] });
    return validateSnapshot(snapshot, manifest);
  } finally {
    provider.destroy();
  }
}

module.exports = {
  FIXED,
  IMPLEMENTATION_SLOT,
  INITIALIZABLE_SLOT,
  GUARD_SLOT,
  normalizeManifest,
  expectedRuntime,
  readSnapshot,
  validateSnapshot,
  safeFailure,
  main,
};
if (require.main === module)
  main()
    .then((result) => console.log(JSON.stringify(result, null, 2)))
    .catch((error) => {
      console.error(safeFailure(error));
      process.exitCode = 1;
    });
