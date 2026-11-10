"use strict";

// Disposable test infrastructure only; never accepts a public RPC or the retained V2 fork port.
function validateLocalRpc(endpoint) {
  const url = new URL(endpoint);
  if (
    url.protocol !== "http:" ||
    !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) ||
    url.port !== "38545" ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash
  )
    throw new Error("Only isolated loopback Anvil :38545 is permitted");
  return url.href;
}

async function requireLocalFork(provider, anchor) {
  const version = await provider.send("web3_clientVersion", []);
  if (!version.toLowerCase().includes("anvil")) throw new Error("Anvil is required");
  await provider.send("anvil_nodeInfo", []);
  if ((await provider.getNetwork()).chainId !== 1n) throw new Error("Wrong local chain");
  const actual = await provider.getBlock(anchor.number);
  if (!actual || actual.hash !== anchor.hash) throw new Error("Local fork anchor changed");
}

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const {
  JsonRpcProvider,
  ContractFactory,
  Contract,
  parseEther,
  ZeroAddress,
  keccak256,
  AbiCoder,
  id,
} = require("ethers");
const { FIXED, readSnapshot, validateSnapshot } = require("../v2/preflight.cjs");
const ROOT = path.resolve(__dirname, "../..");
const RPC = "http://127.0.0.1:38545/";
const ANCHOR = { number: 26384004, hash: "0x779dd81f2ab7246265e585d415209b812c162c5c9a2c52ee4a5cda22c7bc7bde" };
const TOKEN = [
  "function balanceOf(address) view returns(uint256)",
  "function transfer(address,uint256) returns(bool)",
  "function approve(address,uint256) returns(bool)",
];
const artifact = (name) => JSON.parse(fs.readFileSync(path.join(ROOT, "out", `${name}.sol`, `${name}.json`)));
const tx = async (promise) => (await promise).wait();
const deadline = async (provider) => (await provider.getBlock("latest")).timestamp + 600;
async function impersonate(provider, address) {
  await provider.send("anvil_impersonateAccount", [address]);
  await provider.send("anvil_setBalance", [address, "0x" + parseEther("10").toString(16)]);
  return provider.getSigner(address);
}
async function prepare(provider) {
  // Fail before any local mutation when a build is incomplete.
  for (const name of [
    "YieldManagerV2",
    "ERC1967Proxy",
    "RethSupporterVault",
    "YsyBoldSupporterVault",
    "SebaV2DirectExecutor",
    "SebaCowIntentModule",
  ])
    artifact(name);
  const info = await provider.send("anvil_nodeInfo", []);
  if (Number(info.currentBlockNumber) !== ANCHOR.number) throw new Error("Prepare requires a fresh isolated fork");
  // Quotes use wall-clock expiry. Advance only the disposable fork; retain its exact historical anchor.
  await provider.send("evm_setNextBlockTimestamp", [
    Math.max(Math.floor(Date.now() / 1000), (await provider.getBlock("latest")).timestamp + 1),
  ]);
  const deployer = await provider.getSigner(0),
    operator = await provider.getSigner(1);
  const safe = await impersonate(provider, FIXED.treasury);
  const alice = await provider.getSigner(2),
    bob = await provider.getSigner(3);
  const old = new Contract(
    FIXED.oldManager,
    ["function sBOLD() view returns(address)", "function sebaVault() view returns(address)"],
    provider,
  );
  const sBold = await old.sBOLD(),
    pybSeba = await old.sebaVault();
  async function deploy(name, args = []) {
    const a = artifact(name),
      c = await new ContractFactory(a.abi, a.bytecode.object, deployer).deploy(...args);
    const receipt = await c.deploymentTransaction().wait();
    return {
      contract: c,
      metadata: {
        address: await c.getAddress(),
        deploymentBlock: receipt.blockNumber,
        deploymentTransaction: receipt.hash,
        deploymentBlockHash: receipt.blockHash,
      },
    };
  }
  async function proxy(name, args) {
    const implementation = await deploy(name);
    const p = await deploy("ERC1967Proxy", [
      implementation.metadata.address,
      implementation.contract.interface.encodeFunctionData("initialize", args),
    ]);
    return {
      contract: new Contract(p.metadata.address, artifact(name).abi, safe),
      metadata: { ...p.metadata, implementation: implementation.metadata.address },
    };
  }
  const op = await operator.getAddress();
  const manager = await proxy("YieldManagerV2", [
    {
      treasury: FIXED.treasury,
      operator: op,
      pool: FIXED.pool,
      bold: FIXED.bold,
      sBold,
      pybSeba,
      reth: FIXED.reth,
      ysyBold: FIXED.ysyBold,
    },
  ]);
  const r = await proxy("RethSupporterVault", [
    FIXED.treasury,
    manager.metadata.address,
    FIXED.reth,
    FIXED.rocketStorage,
  ]);
  const y = await proxy("YsyBoldSupporterVault", [
    FIXED.treasury,
    manager.metadata.address,
    FIXED.ysyBold,
    FIXED.yBold,
  ]);
  const executor = await deploy("SebaV2DirectExecutor", [
    {
      manager: manager.metadata.address,
      treasury: FIXED.treasury,
      reth: FIXED.reth,
      weth: FIXED.weth,
      usdc: ZeroAddress,
      bold: FIXED.bold,
      yBold: FIXED.yBold,
      ysyBold: FIXED.ysyBold,
      swapRouter: ZeroAddress,
      curvePool: ZeroAddress,
      ethUsdFeed: ZeroAddress,
      usdcUsdFeed: ZeroAddress,
      rocketStorage: FIXED.rocketStorage,
    },
  ]);
  const cow = await deploy("SebaCowIntentModule", [
    manager.metadata.address,
    FIXED.treasury,
    FIXED.weth,
    FIXED.reth,
    FIXED.bold,
    FIXED.cowSettlement,
  ]);
  const registry = new Contract(FIXED.rocketStorage, ["function getAddress(bytes32) view returns(address)"], provider);
  const registered = (name) => registry.getFunction("getAddress").staticCall(id("contract.address" + name));
  await tx(manager.contract.bindVaults(r.metadata.address, y.metadata.address));
  const safeOwners = await new Contract(
    FIXED.treasury,
    ["function getOwners() view returns(address[])"],
    provider,
  ).getOwners();
  const disabledManifest = {
    schema: "seba-v2-local-fixture-v1",
    localOnly: true,
    mainnetFork: true,
    chainId: 1,
    treasury: FIXED.treasury,
    pool: FIXED.pool,
    oldManager: FIXED.oldManager,
    deployer: await deployer.getAddress(),
    operator: op,
    manager: manager.metadata,
    rethVault: r.metadata,
    ysyBoldVault: y.metadata,
    executor: executor.metadata,
    cowModule: cow.metadata,
    safeOwnersHash: keccak256(AbiCoder.defaultAbiCoder().encode(["address[]"], [safeOwners])),
  };
  const disabledPreflight = validateSnapshot(await readSnapshot(provider, disabledManifest), disabledManifest);
  const ex = executor.contract.connect(safe);
  await tx(
    ex.configureLimits([
      parseEther("200"),
      parseEther("100"),
      parseEther("300000"),
      10n ** 15n,
      0,
      0,
      172800,
      20000,
      900,
      0,
      0,
      0,
      0,
      await registered("rocketDepositPool"),
      await registered("rocketNetworkBalances"),
      await registered("rocketDAOProtocolSettingsDeposit"),
    ]),
  );
  await tx(ex.configureBoldLimit(parseEther("1000000")));
  await tx(ex.setEnabled(true));
  await tx(
    manager.contract.configureExecution(
      executor.metadata.address,
      parseEther("200"),
      parseEther("100"),
      parseEther("300000"),
    ),
  );
  await tx(manager.contract.configureCowModule(cow.metadata.address)); // Before module configuration: template observes all config events.
  await tx(cow.contract.connect(safe).configureLimits(parseEther("200"), parseEther("100"), 900));
  await tx(cow.contract.connect(safe).setEnabled(true));
  await tx(r.contract.configureReportBounds(172800, 20000));
  for (const v of [r.contract, y.contract]) {
    await tx(v.configureEntry(1, true));
    await tx(v.configureHarvest(parseEther("100"), true));
    await tx(v.setOperator(op, true));
  }
  await tx(manager.contract.setExecutionEnabled(true));
  await tx(manager.contract.setIntakeEnabled(true));
  const pool = new Contract(FIXED.pool, ["function setYieldManager(address)", "function sweepRewards()"], safe);
  await tx(pool.setYieldManager(manager.metadata.address)); // Local Safe impersonation, NOT real signatures or an approved cutover.
  for (const [v, tokenAddress, quantity] of [
    [r.contract, FIXED.reth, parseEther("1")],
    [y.contract, FIXED.ysyBold, parseEther("100")],
  ]) {
    const token = new Contract(tokenAddress, TOKEN, safe);
    for (const who of [alice, bob]) {
      await tx(token.transfer(await who.getAddress(), quantity));
      await tx(token.connect(who).approve(await v.getAddress(), quantity));
      await tx(v.connect(who).deposit(quantity, 1, await deadline(provider)));
    }
  }
  // Actual existing Safe rETH, intentionally donated to create carry; NOT naturally accrued yield.
  await tx(new Contract(FIXED.reth, TOKEN, safe).transfer(r.metadata.address, parseEther("2")));
  await tx(r.contract.recognizeSurplus(0, parseEther("1"), false));
  await tx(r.contract.recognizeSurplus(1, parseEther("1"), false));
  // Synthetic fixture pool income, not legacy liquidation proceeds. Preserve any preexisting pool balance.
  await tx(deployer.sendTransaction({ to: FIXED.pool, value: parseEther("0.4") }));
  await tx(pool.sweepRewards());
  return {
    schema: "seba-cow-local-v1",
    localOnly: true,
    mainnetFork: true,
    chainId: 1,
    rpc: RPC,
    anchorBlock: ANCHOR.number,
    anchorHash: ANCHOR.hash,
    manager: manager.metadata,
    rethVault: r.metadata,
    ysyBoldVault: y.metadata,
    executor: executor.metadata,
    cowModule: cow.metadata,
    treasury: FIXED.treasury,
    operator: op,
    pool: FIXED.pool,
    oldManager: FIXED.oldManager,
    backendConfig: {
      chainId: 1,
      pool: FIXED.pool,
      legacyManager: FIXED.oldManager,
      manager: manager.metadata.address,
      rethVault: r.metadata.address,
      ysyBoldVault: y.metadata.address,
      rethToken: FIXED.reth,
      ysyBoldToken: FIXED.ysyBold,
      safe: FIXED.treasury,
      operator: op,
      managerImplementation: manager.metadata.implementation,
      rethImplementation: r.metadata.implementation,
      ysyBoldImplementation: y.metadata.implementation,
      executor: executor.metadata.address,
      cowModule: cow.metadata.address,
      cowSettlement: FIXED.cowSettlement,
      cowRelayer: FIXED.cowRelayer,
      cowModuleCodeHash: keccak256(await provider.getCode(cow.metadata.address)),
    },
    disabledPreflight,
    maintenancePolicy: {
      minimumEth: String(parseEther("0.001")),
      minimumReth: String(parseEther("0.001")),
      minimumYsy: String(parseEther("0.001")),
      minimumBold: String(parseEther("0.001")),
      minimumSBold: String(parseEther("0.001")),
      deadlineSeconds: 600,
      cowSlippageBps: 50,
    },
    interventions: [
      "Local deployments and Safe impersonation; no production writes or owner signatures",
      "Synthetic Safe ETH for local gas; synthetic 0.4 ETH pool income; not legacy recovery proceeds",
      "Actual Safe native tokens locally transferred; 2 rETH donated/recognized to synthesize carry",
      "Loopback synthetic quote/orderbook; real CoW settlement later uses impersonated allowed solver and synthetic BOLD inventory",
    ],
    users: [await alice.getAddress(), await bob.getAddress()],
  };
}
async function settle(provider, f) {
  const cow = new Contract(f.cowModule.address, artifact("SebaCowIntentModule").abi, provider);
  const solverAddress = "0x5ed864e8f37dcb4f79c5172a815d1b3a9147eaab";
  const solver = await impersonate(provider, solverAddress);
  const settlement = new Contract(
    FIXED.cowSettlement,
    [
      "function authenticator() view returns(address)",
      "function settle(address[],uint256[],(uint256 sellTokenIndex,uint256 buyTokenIndex,address receiver,uint256 sellAmount,uint256 buyAmount,uint32 validTo,bytes32 appData,uint256 feeAmount,uint256 flags,uint256 executedAmount,bytes signature)[],(address target,uint256 value,bytes callData)[][3])",
    ],
    solver,
  );
  assert.equal(
    await new Contract(
      await settlement.authenticator(),
      ["function isSolver(address) view returns(bool)"],
      provider,
    ).isSolver(solverAddress),
    true,
  );
  const boldPool = "0xEFc6516323FbD28e80B85A497B65A86243a54B3E";
  const donor = await impersonate(provider, boldPool);
  for (const source of [1, 0]) {
    const orderId = await cow.activeOrder(source);
    assert.ok(orderId > 0n, "Backend must create each source order");
    const o = await cow.orderData(orderId);
    const output = o.buyAmount + 10n ** 18n;
    // Real existing BOLD transferred out of a pool by LOCAL impersonation; not a market trade or par liquidation.
    await tx(new Contract(FIXED.bold, TOKEN, donor).transfer(FIXED.cowSettlement, output));
    await tx(
      settlement.settle(
        [o.sellToken, FIXED.bold],
        [output, o.sellAmount],
        [[0, 1, o.receiver, o.sellAmount, o.buyAmount, o.validTo, o.appData, 0, 96, o.sellAmount, o.receiver]],
        [[], [], []],
      ),
    );
  }
  assert.equal(await cow.activeCount(), 4n, "Settlement alone does not finalize manager accounting");
}
async function cancelAndExpire(provider, f) {
  const safe = await impersonate(provider, FIXED.treasury);
  const manager = new Contract(f.manager.address, artifact("YieldManagerV2").abi, safe);
  const cow = new Contract(f.cowModule.address, artifact("SebaCowIntentModule").abi, safe);
  await tx(cow.setEnabled(false));
  const id3 = await cow.activeOrder(3);
  assert.ok(id3 > 0n);
  await tx(manager.finalizeCowOrder(id3)); // Safe cancellation while the order is still valid.
  const id2 = await cow.activeOrder(2);
  assert.ok(id2 > 0n);
  const o = await cow.order(id2);
  await provider.send("evm_setNextBlockTimestamp", [Number(o.validTo) + 1]);
  await provider.send("evm_mine", []);
}
async function exit(provider, f, recoveryBeforeInvestment = false) {
  const safe = await impersonate(provider, FIXED.treasury);
  const manager = new Contract(f.manager.address, artifact("YieldManagerV2").abi, safe);
  const cow = new Contract(f.cowModule.address, artifact("SebaCowIntentModule").abi, provider);
  assert.equal(await cow.activeCount(), 0n);
  if (!recoveryBeforeInvestment)
    assert.equal(await manager.pendingProtocolBold(), 0n, "Backend must credit Yearn principal, not donate it");
  const vaults = [
    new Contract(f.rethVault.address, artifact("RethSupporterVault").abi, safe),
    new Contract(f.ysyBoldVault.address, artifact("YsyBoldSupporterVault").abi, safe),
  ];
  await tx(manager.setExecutionEnabled(false));
  await tx(manager.setIntakeEnabled(false));
  for (const v of vaults) {
    await tx(v.configureEntry(await v.minimumBasis(), false));
    await tx(v.configureHarvest(await v.maximumHarvest(), false));
  }
  await tx(manager.recoverBuffers(id("local cow completed reconciliation")));
  const unlocks = await Promise.all(vaults.flatMap((v) => f.users.map(async (_, i) => Number((await v.position(i + 1)).unlockAt))));
  const unlock = Math.max(...unlocks);
  if ((await provider.getBlock("latest")).timestamp < unlock) {
    await provider.send("evm_setNextBlockTimestamp", [unlock]);
    await provider.send("evm_mine", []);
  }
  // Native exits do not require fresh mint/harvest reports, ETH liquidity, or an active CoW orderbook.
  for (const v of vaults) {
    for (let i = 0; i < f.users.length; i++) {
      const user = await provider.getSigner(f.users[i]);
      await tx(v.connect(user).withdraw(i + 1, 1, await deadline(provider)));
      assert.equal((await v.position(i + 1)).closed, true);
    }
    const b = await v.bucket(1);
    if (b.basis > 0n) await tx(v.withdrawProtocol(b.basis, 1, await deadline(provider)));
    assert.equal((await v.bucket(0)).basis, 0n);
    assert.equal((await v.bucket(1)).basis, 0n);
  }
  // Last native exits may deliver authenticated recognized carry after initial manager recovery.
  const lateCarry =
    (await manager.harvestInventory(0, 0)) +
    (await manager.harvestInventory(0, 1)) +
    (await manager.harvestInventory(1, 0)) +
    (await manager.harvestInventory(1, 1));
  if (lateCarry > 0n) await tx(manager.recoverBuffers(id("local late native-exit carry reconciliation")));
  assert.equal(await manager.pendingBold(), 0n);
  assert.equal(await manager.pendingProtocolBold(), 0n);
  assert.equal(await manager.pendingSBold(), 0n);
  for (const leg of [0, 1]) for (const bucket of [0, 1]) assert.equal(await manager.harvestInventory(leg, bucket), 0n);
}
async function main(args = process.argv.slice(2)) {
  const [mode, input, output] = args;
  if (
    !["prepare", "settle", "cancel-expire", "exit", "recover-exit", "checkpoint"].includes(mode) ||
    !input ||
    !output ||
    fs.existsSync(output)
  )
    throw new Error("Usage: local-e2e.cjs MODE INPUT_OR_DASH NEW_OUTPUT.json (never overwrite evidence)");
  const provider = new JsonRpcProvider(validateLocalRpc(RPC), undefined, { cacheTimeout: -1 });
  provider.pollingInterval = 20;
  try {
    await requireLocalFork(provider, ANCHOR);
    const f = mode === "prepare" ? await prepare(provider) : JSON.parse(fs.readFileSync(input, "utf8"));
    if (f.anchorHash !== ANCHOR.hash || f.rpc !== RPC || !f.localOnly) throw new Error("Wrong fixture");
    if (mode === "settle") await settle(provider, f);
    if (mode === "cancel-expire") await cancelAndExpire(provider, f);
    if (mode === "exit") await exit(provider, f);
    if (mode === "recover-exit") await exit(provider, f, true);
    const head = await provider.getBlock("latest");
    fs.writeFileSync(
      output,
      JSON.stringify({ ...f, lastBlockNumber: head.number, lastBlockHash: head.hash, lastPhase: mode }, null, 2) + "\n",
    );
    console.log(JSON.stringify({ localOnly: true, phase: mode, block: head.number, hash: head.hash, output }));
  } finally {
    provider.destroy();
  }
}
module.exports = { validateLocalRpc, requireLocalFork };
if (require.main === module)
  main().catch((error) => {
    console.error(error.shortMessage || error.message);
    process.exitCode = 1;
  });
