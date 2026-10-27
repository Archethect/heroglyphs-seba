"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { AbiCoder, Interface, ZeroAddress, keccak256 } = require("ethers");
const {
  FIXED,
  IMPLEMENTATION_SLOT,
  INITIALIZABLE_SLOT,
  normalizeManifest,
  safeFailure,
  validateSnapshot,
  expectedRuntime,
  readSnapshot,
} = require("./preflight.cjs");
const coder = AbiCoder.defaultAbiCoder();
const addr = (n) => `0x${n.toString(16).padStart(40, "0")}`;
const word = (n) => `0x${BigInt(n).toString(16).padStart(64, "0")}`;
const same = (a, b) => a.toLowerCase() === b.toLowerCase();
const owners = Array.from({ length: 7 }, (_, i) => addr(100 + i));
function manifest() {
  const m = {
    schema: "seba-v2-deployment-v1",
    chainId: 1,
    phase: "unbound",
    treasury: FIXED.treasury,
    pool: FIXED.pool,
    oldManager: FIXED.oldManager,
    deployer: addr(200),
    initialOperator: ZeroAddress,
    manager: addr(201),
    managerImplementation: addr(202),
    rethVault: addr(203),
    rethImplementation: addr(204),
    ysyBoldVault: addr(205),
    ysyBoldImplementation: addr(206),
    executor: addr(207),
    safeOwnersHash: keccak256(coder.encode(["address[]"], [owners])),
  };
  m.bootstrapBindTo = m.manager;
  m.bootstrapBindData = new Interface(["function bindVaults(address,address)"]).encodeFunctionData("bindVaults", [
    m.rethVault,
    m.ysyBoldVault,
  ]);
  return m;
}
function snapshot(m = manifest()) {
  const sBold = "0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11";
  const pyb = "0x8D06a179486111E556A7C46E49352259B0279CD1";
  const manager = {
    treasury: FIXED.treasury,
    sebaPool: FIXED.pool,
    bold: FIXED.bold,
    sBold,
    pybSeba: pyb,
    reth: FIXED.reth,
    ysyBold: FIXED.ysyBold,
    yBold: FIXED.yBold,
    weth: ZeroAddress,
    usdc: ZeroAddress,
    intakeEnabled: false,
    executionEnabled: false,
    buffersRecovered: false,
    executor: ZeroAddress,
    maximumEth: 0n,
    pendingBold: 0n,
    pendingSBold: 0n,
    rethBps: 5000n,
    ysyBoldBps: 5000n,
    weightVersion: 1n,
    legacyHandoff: ZeroAddress,
    legacyExpectedEth: 0n,
    legacyExpiry: 0n,
    legacyWeightVersion: 0n,
    legacyImported: false,
    legacyManifest: word(0),
    vaults: m.phase === "bound" ? [m.rethVault, m.ysyBoldVault] : [ZeroAddress, ZeroAddress],
    pendingEth: [0n, 0n, 0n],
    maximumYieldTokens: [0n, 0n],
    harvestInventory: [0n, 0n, 0n, 0n],
    operators: { [ZeroAddress]: false, [m.deployer.toLowerCase()]: false, [FIXED.treasury.toLowerCase()]: false },
  };
  return {
    chainId: 1n,
    block: { number: 26255670, hash: word(99) },
    safe: { getOwners: [...owners], getThreshold: 3n, modules: [], next: addr(1), guard: word(0) },
    old: { sebaPool: FIXED.pool, BOLD: FIXED.bold, sBOLD: sBold, sebaVault: pyb },
    pool: { yieldManager: FIXED.oldManager, sebaVault: pyb },
    proxies: [
      [m.manager, m.managerImplementation],
      [m.rethVault, m.rethImplementation],
      [m.ysyBoldVault, m.ysyBoldImplementation],
    ].map(([proxy, implementation]) => ({
      proxy,
      implementation,
      slot: word(implementation),
      proxyInitializer: word(1),
      implementationInitializer: word((1n << 64n) - 1n),
      uuid: IMPLEMENTATION_SLOT,
      implementationCodeMatches: true,
      proxyCodeMatches: true,
    })),
    manager,
    vaults: [FIXED.reth, FIXED.ysyBold].map((asset, i) => ({
      treasury: FIXED.treasury,
      manager: m.manager,
      asset,
      basisAsset: i === 0 ? ZeroAddress : FIXED.yBold,
      entriesEnabled: false,
      harvestEnabled: false,
      minimumBasis: 0n,
      maximumHarvest: 0n,
      nextPositionId: 1n,
      recoveryState: 0n,
      recoveryInstance: word(0),
      buckets: [Array(8).fill(0n), Array(8).fill(0n)],
      operators: [false, false, false],
      ...(i === 0 ? { rocketStorage: FIXED.rocketStorage, maximumReportAge: 0n, maximumReportBlockLag: 0n } : {}),
    })),
    executor: {
      manager: m.manager,
      treasury: FIXED.treasury,
      configuration: { ...FIXED, manager: m.manager },
      limits: [...Array(13).fill(0n), ZeroAddress, ZeroAddress, ZeroAddress],
      enabled: false,
      codeMatches: true,
    },
    assetGraph: [FIXED.yBold, FIXED.bold, FIXED.bold, sBold],
    registryReth: FIXED.reth,
    curveCoins: [FIXED.bold, FIXED.usdc],
  };
}

test("unknown manifest schema and non-mainnet chain fail closed", () => {
  assert.throws(() => normalizeManifest({ schema: "unknown" }), /manifest/);
  assert.throws(() => normalizeManifest({ schema: "seba-v2-deployment-v1", chainId: 2 }), /manifest/);
});

test("error output never contains upstream RPC URLs or credentials", () => {
  const error = new Error("https://provider.example/v2/secret-key: unauthorized");
  assert.equal(safeFailure(error), "Preflight failed; verify the manifest, pinned chain state and RPC availability.");
});

test("the preflight exports its independently testable read-only validator", () => {
  assert.equal(typeof validateSnapshot, "function");
});

test("fresh disabled candidate passes and returns exact separate bootstrap calldata", () => {
  const m = manifest();
  const report = validateSnapshot(snapshot(m), m);
  assert.equal(report.readOnly, true);
  assert.equal(report.phase, "unbound");
  assert.equal(report.bootstrapBindData, m.bootstrapBindData);
  assert.equal(report.checks.length, 36);
});

test("bound phase checks reciprocal vaults without enabling any operation", () => {
  const m = { ...manifest(), phase: "bound" };
  assert.equal(validateSnapshot(snapshot(m), m).phase, "bound");
  const s = snapshot(m);
  s.manager.vaults.reverse();
  assert.throws(() => validateSnapshot(s, m), /manager.bindingPhase/);
});

test("local fixture manifest is explicitly labeled and preserves its declared test operator", () => {
  const m = manifest();
  const local = {
    ...m,
    schema: "seba-v2-local-fixture-v1",
    localOnly: true,
    mainnetFork: true,
    manager: { address: m.manager, implementation: m.managerImplementation },
    rethVault: { address: m.rethVault, implementation: m.rethImplementation },
    ysyBoldVault: { address: m.ysyBoldVault, implementation: m.ysyBoldImplementation },
    executor: { address: m.executor },
    operator: addr(300),
  };
  const normalized = normalizeManifest(local);
  const s = snapshot(normalized);
  s.manager.operators[addr(300)] = true;
  assert.equal(validateSnapshot(s, local).localOnly, true);
  s.manager.operators[addr(301)] = true;
  assert.throws(() => validateSnapshot(s, local), /manager.initialOperatorOnly/);
});

test("malformed or aliased manifests cannot weaken runtime checks", () => {
  for (const mutate of [
    (m) => {
      m.managerImplementation = m.manager;
    },
    (m) => {
      m.manager = FIXED.reth;
    },
    (m) => {
      m.treasury = addr(1);
    },
    (m) => {
      m.initialOperator = addr(1);
    },
    (m) => {
      m.safeOwnersHash = word(0);
    },
    (m) => {
      m.phase = "enabled";
    },
    (m) => {
      m.bootstrapBindData = "0x";
    },
    (m) => {
      m.bootstrapBindTo = addr(1);
    },
    (m) => {
      m.deployer = ZeroAddress;
    },
    (m) => {
      m.executor = "not an address";
    },
  ]) {
    const m = manifest();
    mutate(m);
    assert.throws(() => normalizeManifest(m), /manifest/);
  }
});

for (const [name, mutate, failure] of [
  [
    "wrong chain",
    (s) => {
      s.chainId = 2n;
    },
    "chain.mainnet",
  ],
  [
    "wrong threshold",
    (s) => {
      s.safe.getThreshold = 1n;
    },
    "safe.thresholdAndOwnerCount",
  ],
  [
    "wrong count",
    (s) => {
      s.safe.getOwners.pop();
    },
    "safe.thresholdAndOwnerCount",
  ],
  [
    "signer drift",
    (s) => {
      s.safe.getOwners[0] = addr(400);
    },
    "safe.reviewedOwners",
  ],
  [
    "module",
    (s) => {
      s.safe.modules.push(addr(400));
    },
    "safe.noModules",
  ],
  [
    "pagination",
    (s) => {
      s.safe.next = addr(400);
    },
    "safe.noModules",
  ],
  [
    "guard",
    (s) => {
      s.safe.guard = word(400);
    },
    "safe.noGuard",
  ],
  [
    "pool cutover",
    (s) => {
      s.pool.yieldManager = addr(400);
    },
    "legacy.poolManager",
  ],
  [
    "legacy reward drift",
    (s) => {
      s.old.BOLD = addr(400);
    },
    "legacy.rewardGraph",
  ],
  [
    "legacy token alias",
    (s) => {
      s.old.sBOLD = FIXED.bold;
    },
    "legacy.distinctTokens",
  ],
  [
    "wrapper graph",
    (s) => {
      s.assetGraph[0] = FIXED.bold;
    },
    "tokens.assetGraph",
  ],
  [
    "registry",
    (s) => {
      s.registryReth = addr(400);
    },
    "venues.assetGraph",
  ],
  [
    "curve coin order",
    (s) => {
      s.curveCoins.reverse();
    },
    "venues.assetGraph",
  ],
  [
    "implementation slot",
    (s) => {
      s.proxies[0].slot = word(400);
    },
    "proxy.0.implementationSlot",
  ],
  [
    "unlocked implementation",
    (s) => {
      s.proxies[1].implementationInitializer = word(0);
    },
    "proxy.1.initializerLock",
  ],
  [
    "reinitialized proxy",
    (s) => {
      s.proxies[2].proxyInitializer = word(2);
    },
    "proxy.2.initializerLock",
  ],
  [
    "wrong UUID",
    (s) => {
      s.proxies[0].uuid = word(400);
    },
    "proxy.0.uupsUUID",
  ],
  [
    "foreign implementation code",
    (s) => {
      s.proxies[0].implementationCodeMatches = false;
    },
    "proxy.0.compiledRuntime",
  ],
  [
    "foreign proxy code",
    (s) => {
      s.proxies[0].proxyCodeMatches = false;
    },
    "proxy.0.compiledRuntime",
  ],
  [
    "manager role",
    (s) => {
      s.manager.treasury = addr(400);
    },
    "manager.identities",
  ],
  [
    "unexpected binding",
    (s) => {
      s.manager.vaults[0] = addr(400);
    },
    "manager.bindingPhase",
  ],
  [
    "intake enabled",
    (s) => {
      s.manager.intakeEnabled = true;
    },
    "manager.disabled",
  ],
  [
    "execution enabled",
    (s) => {
      s.manager.executionEnabled = true;
    },
    "manager.disabled",
  ],
  [
    "recovered manager",
    (s) => {
      s.manager.buffersRecovered = true;
    },
    "manager.disabled",
  ],
  [
    "configured executor",
    (s) => {
      s.manager.executor = addr(400);
    },
    "manager.unconfiguredAndEmpty",
  ],
  [
    "pending capital",
    (s) => {
      s.manager.pendingEth[1] = 1n;
    },
    "manager.unconfiguredAndEmpty",
  ],
  [
    "harvest inventory",
    (s) => {
      s.manager.harvestInventory[1] = 1n;
    },
    "manager.unconfiguredAndEmpty",
  ],
  [
    "armed migration",
    (s) => {
      s.manager.legacyHandoff = addr(400);
    },
    "manager.unconfiguredAndEmpty",
  ],
  [
    "changed weights",
    (s) => {
      s.manager.rethBps = 6000n;
    },
    "manager.initialWeights",
  ],
  [
    "EOA operator",
    (s) => {
      s.manager.operators[addr(200)] = true;
    },
    "manager.initialOperatorOnly",
  ],
  [
    "leaf manager",
    (s) => {
      s.vaults[0].manager = addr(400);
    },
    "vault.0.identities",
  ],
  [
    "leaf asset",
    (s) => {
      s.vaults[1].asset = FIXED.reth;
    },
    "vault.1.identities",
  ],
  [
    "leaf entry",
    (s) => {
      s.vaults[0].entriesEnabled = true;
    },
    "vault.0.disabledAndEmpty",
  ],
  [
    "leaf harvest",
    (s) => {
      s.vaults[1].harvestEnabled = true;
    },
    "vault.1.disabledAndEmpty",
  ],
  [
    "leaf capital",
    (s) => {
      s.vaults[1].buckets[0][0] = 1n;
    },
    "vault.1.disabledAndEmpty",
  ],
  [
    "leaf recovery",
    (s) => {
      s.vaults[0].recoveryState = 1n;
    },
    "vault.0.disabledAndEmpty",
  ],
  [
    "leaf operator",
    (s) => {
      s.vaults[0].operators[0] = true;
    },
    "vault.0.disabledAndEmpty",
  ],
  [
    "freshness configured",
    (s) => {
      s.vaults[0].maximumReportAge = 1n;
    },
    "vault.reth.unsetFreshness",
  ],
  [
    "executor manager",
    (s) => {
      s.executor.configuration.manager = addr(400);
    },
    "executor.identities",
  ],
  [
    "executor venue",
    (s) => {
      s.executor.configuration.swapRouter = addr(400);
    },
    "executor.identities",
  ],
  [
    "executor enabled",
    (s) => {
      s.executor.enabled = true;
    },
    "executor.disabledAndUnset",
  ],
  [
    "executor limits",
    (s) => {
      s.executor.limits[0] = 1n;
    },
    "executor.disabledAndUnset",
  ],
  [
    "executor registry pin",
    (s) => {
      s.executor.limits[13] = addr(400);
    },
    "executor.disabledAndUnset",
  ],
  [
    "executor code",
    (s) => {
      s.executor.codeMatches = false;
    },
    "executor.compiledRuntime",
  ],
])
  test(`rejects ${name}`, () => {
    const m = manifest();
    const s = snapshot(m);
    mutate(s);
    assert.throws(() => validateSnapshot(s, m), new RegExp(failure.replaceAll(".", "\\.")));
  });

test("runtime comparison resolves all immutable addresses and detects changed non-immutable bytes", () => {
  const a = {
    ast: { nodeType: "VariableDeclaration", id: 1, mutability: "immutable", name: "manager" },
    deployedBytecode: {
      object: "0x60" + "00".repeat(32) + "61",
      immutableReferences: { 1: [{ start: 1, length: 32 }] },
    },
  };
  assert.equal(
    expectedRuntime(a, { manager: addr(200) }),
    "0x60" + coder.encode(["address"], [addr(200)]).slice(2) + "61",
  );
  assert.notEqual(expectedRuntime(a, { manager: addr(200) }), expectedRuntime(a, { manager: addr(201) }));
  assert.throws(() => expectedRuntime(a, {}), /artifact.immutable/);
  a.deployedBytecode.immutableReferences[1][0].length = 20;
  assert.throws(() => expectedRuntime(a, { manager: addr(200) }), /artifact.immutableWidth/);
});

test("snapshot reader only performs pinned reads and produces an independently validated snapshot", async () => {
  const m = manifest();
  const s = snapshot(m);
  const artifacts = {};
  const load = (name) =>
    (artifacts[name] ||= JSON.parse(fs.readFileSync(path.join(__dirname, "../../out", `${name}.sol`, `${name}.json`))));
  const contracts = new Map();
  function register(a, name, value) {
    const current = contracts.get(a.toLowerCase()) || { iface: new Interface(load(name).abi), views: {} };
    Object.assign(current.views, value);
    contracts.set(a.toLowerCase(), current);
  }
  function narrow(a, abi, views) {
    contracts.set(a.toLowerCase(), { iface: new Interface(abi), views });
  }
  register(m.manager, "YieldManagerV2", {
    ...s.manager,
    vaults: (i) => s.manager.vaults[Number(i)],
    pendingEth: (i) => s.manager.pendingEth[Number(i)],
    maximumYieldTokens: (i) => s.manager.maximumYieldTokens[Number(i)],
    harvestInventory: () => 0n,
    operators: () => false,
  });
  for (const [i, name] of ["RethSupporterVault", "YsyBoldSupporterVault"].entries()) {
    const a = i === 0 ? m.rethVault : m.ysyBoldVault;
    register(a, name, {
      ...s.vaults[i],
      bucket: (which) => s.vaults[i].buckets[Number(which)],
      operators: () => false,
    });
  }
  register(m.executor, "SebaV2Executor", s.executor);
  for (const [a, name] of [
    [m.managerImplementation, "YieldManagerV2"],
    [m.rethImplementation, "RethSupporterVault"],
    [m.ysyBoldImplementation, "YsyBoldSupporterVault"],
  ])
    register(a, name, { proxiableUUID: IMPLEMENTATION_SLOT });
  narrow(
    FIXED.treasury,
    [
      "function getOwners() view returns(address[])",
      "function getThreshold() view returns(uint256)",
      "function getModulesPaginated(address,uint256) view returns(address[],address)",
    ],
    { getOwners: owners, getThreshold: 3n, getModulesPaginated: [[], addr(1)] },
  );
  narrow(
    FIXED.oldManager,
    [
      "function sebaPool() view returns(address)",
      "function BOLD() view returns(address)",
      "function sBOLD() view returns(address)",
      "function sebaVault() view returns(address)",
    ],
    s.old,
  );
  narrow(
    FIXED.pool,
    ["function yieldManager() view returns(address)", "function sebaVault() view returns(address)"],
    s.pool,
  );
  [FIXED.ysyBold, FIXED.yBold, s.old.sBOLD, s.old.sebaVault].forEach((a, i) =>
    narrow(a, ["function asset() view returns(address)"], { asset: s.assetGraph[i] }),
  );
  narrow(FIXED.rocketStorage, ["function getAddress(bytes32) view returns(address)"], { getAddress: FIXED.reth });
  narrow(FIXED.curvePool, ["function coins(uint256) view returns(address)"], { coins: (i) => s.curveCoins[Number(i)] });
  let reads = 0;
  const provider = {
    async getNetwork() {
      return { chainId: 1n };
    },
    async getBlockNumber() {
      return s.block.number;
    },
    async getBlock(blockTag) {
      assert.equal(blockTag, s.block.number);
      return s.block;
    },
    async getStorage(a, slot, blockTag) {
      assert.equal(blockTag, s.block.number);
      if (same(a, FIXED.treasury)) return word(0);
      const p = s.proxies.find((p) => same(p.proxy, a) || same(p.implementation, a));
      if (slot === IMPLEMENTATION_SLOT) return p.slot;
      assert.equal(slot, INITIALIZABLE_SLOT);
      return same(a, p.proxy) ? p.proxyInitializer : p.implementationInitializer;
    },
    async getCode(a, blockTag) {
      assert.equal(blockTag, s.block.number);
      const p = s.proxies.find((p) => same(p.proxy, a) || same(p.implementation, a));
      if (p)
        return expectedRuntime(
          load(
            same(a, p.proxy)
              ? "ERC1967Proxy"
              : p.proxy === m.manager
                ? "YieldManagerV2"
                : p.proxy === m.rethVault
                  ? "RethSupporterVault"
                  : "YsyBoldSupporterVault",
          ),
          { __self: p.implementation },
        );
      assert.ok(same(a, m.executor));
      return expectedRuntime(load("SebaV2Executor"), { manager: m.manager, treasury: FIXED.treasury });
    },
    async call(tx) {
      reads++;
      assert.equal(tx.blockTag, s.block.number);
      assert.equal(Object.keys(tx).sort().join(","), "blockTag,data,to");
      const c = contracts.get(tx.to.toLowerCase());
      const parsed = c.iface.parseTransaction({ data: tx.data });
      const handler = c.views[parsed.name];
      assert.notEqual(handler, undefined, parsed.name);
      const value = typeof handler === "function" ? handler(...parsed.args) : handler;
      return c.iface.encodeFunctionResult(parsed.fragment, parsed.fragment.outputs.length === 1 ? [value] : value);
    },
  };
  const result = await readSnapshot(provider, m);
  assert.equal(validateSnapshot(result, m).readOnly, true);
  assert.ok(reads > 80, "must test the real complete read sequence rather than a handcrafted success flag");
  provider.getBlock = async () => null;
  await assert.rejects(readSnapshot(provider, m), /block.unavailable/);
});
