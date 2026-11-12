// Executes the reviewed V2 staging batches ONLY on a loopback Anvil Hoodi fork.
// Public Hoodi RPC is used for reads/fork state; there is no public signing or send path.
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import { execFileSync, spawn } from "node:child_process";
import { ethers } from "ethers";
import { buildHoodiV2StagePlan } from "./hoodi-public-v2-plan.mjs";
import { HOODI_ADMIN } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";
import { HOODI_V2_RUNTIME_HASHES } from "./hoodi-public-v2-runtime.mjs";
import { verifyHoodiV2Batch } from "./hoodi-public-v2-verify.mjs";

const manifest = JSON.parse(fs.readFileSync("docs/HOODI_V1_PUBLIC_MANIFEST.json", "utf8"));
const safeAbi = [
  "function nonce() view returns(uint256)",
  "function getOwners() view returns(address[])",
  "function getThreshold() view returns(uint256)",
  "event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)",
  "event ExecutionFailure(bytes32 indexed txHash,uint256 payment)",
];

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

async function main() {
  const key = execFileSync("aws", [
    "secretsmanager", "get-secret-value", "--region", "us-east-1",
    "--secret-id", "s/hero_boost/hoodi-v1-v2/alchemy_key",
    "--query", "SecretString", "--output", "text",
  ], { encoding: "utf8" }).trim();
  if (!/^[A-Za-z0-9_-]{12,}$/.test(key)) throw new Error("invalid isolated Hoodi RPC key format");
  const upstream = `https://eth-hoodi.g.alchemy.com/v2/${key}`;
  const publicHoodi = new ethers.JsonRpcProvider(upstream);
  if ((await publicHoodi.getNetwork()).chainId !== 560048n) throw new Error("not Hoodi");
  const head = await publicHoodi.getBlock("latest");
  if (!head?.hash) throw new Error("missing Hoodi block");
  const plan = await buildHoodiV2StagePlan(manifest);
  for (const group of [manifest.safe, manifest.dependencies, manifest.v1]) {
    for (const entry of Object.values(group)) {
      if (!entry?.address || !entry.runtimeCodeHash) continue;
      const code = await publicHoodi.getCode(entry.address, head.number);
      if (code === "0x" || ethers.keccak256(code) !== entry.runtimeCodeHash) {
        throw new Error(`V1 dependency code hash changed: ${entry.address}`);
      }
    }
  }
  for (const deployment of plan.deployments) {
    if ((await publicHoodi.getCode(deployment.expectedAddress, head.number)) !== "0x") {
      throw new Error(`V2 address already occupied: ${deployment.label}`);
    }
  }
  const poolAbi = ["function yieldManager() view returns(address)"];
  const oldAbi = [
    "function depositId() view returns(uint256)",
    "function principalValue() view returns(uint256)",
    "function pendingBoldConversion() view returns(uint256)",
  ];
  const publicPool = new ethers.Contract(manifest.v1.pool.address, poolAbi, publicHoodi);
  const publicOld = new ethers.Contract(manifest.v1.manager.address, oldAbi, publicHoodi);
  if (
    (await publicPool.yieldManager({ blockTag: head.number })) !== manifest.v1.manager.address ||
    (await publicOld.depositId({ blockTag: head.number })) !== 0n ||
    (await publicOld.principalValue({ blockTag: head.number })) !== 2000n * 10n ** 18n ||
    (await publicOld.pendingBoldConversion({ blockTag: head.number })) !== 0n
  ) throw new Error("public V1 financial baseline changed");

  const proxy = http.createServer(async (request, response) => {
    try {
      if (request.method !== "POST") throw new Error("RPC method");
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const upstreamResponse = await fetch(upstream, {
        method: "POST", headers: { "content-type": "application/json" }, body: Buffer.concat(chunks),
      });
      response.writeHead(upstreamResponse.status, { "content-type": "application/json" });
      response.end(Buffer.from(await upstreamResponse.arrayBuffer()));
    } catch {
      response.writeHead(502, { "content-type": "application/json" });
      response.end('{"error":"isolated upstream unavailable"}');
    }
  });
  await new Promise((resolve) => proxy.listen(0, "127.0.0.1", resolve));
  const proxyPort = proxy.address().port;
  const anvilPort = await freePort();
  const child = spawn("anvil", [
    "--fork-url", `http://127.0.0.1:${proxyPort}`, "--fork-block-number", String(head.number),
    "--chain-id", "560048", "--host", "127.0.0.1", "--port", String(anvilPort), "--silent",
  ], { stdio: "ignore" });
  try {
    const local = new ethers.JsonRpcProvider(`http://127.0.0.1:${anvilPort}`);
    let ready = false;
    for (let i = 0; i < 150; i++) {
      if (child.exitCode !== null) throw new Error("Anvil exited before readiness");
      try {
        if ((await local.getNetwork()).chainId === 560048n) { ready = true; break; }
      } catch { /* startup */ }
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    if (!ready) throw new Error("loopback Hoodi fork unavailable");
    const nodeInfo = await local.send("anvil_nodeInfo", []);
    if (Number(nodeInfo.forkConfig?.forkBlockNumber) !== head.number) throw new Error("wrong fork anchor");
    const forkAnchor = await local.getBlock(head.number);
    if (forkAnchor?.hash !== head.hash) throw new Error("fork block hash mismatch");
    await local.send("anvil_impersonateAccount", [HOODI_ADMIN]);
    await local.send("anvil_setBalance", [HOODI_ADMIN, ethers.toBeHex(ethers.parseEther("10"))]);
    const owner = await local.getSigner(HOODI_ADMIN);
    const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, safeAbi, local);
    const [owners, threshold, initialNonce] = await Promise.all([safe.getOwners(), safe.getThreshold(), safe.nonce()]);
    if (owners.length !== 1 || owners[0] !== HOODI_ADMIN || threshold !== 1n) throw new Error("Safe policy changed");
    const batches = [];
    for (const [index, batch] of plan.batches.entries()) {
      const beforeNonce = await safe.nonce();
      const data = encodeOwnerSafeExecution(batch.transaction.data, HOODI_ADMIN);
      const request = { from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, value: 0n, data };
      const estimatedGas = await local.estimateGas(request);
      const receipt = await (await owner.sendTransaction({
        to: HOODI_REHEARSAL_SAFE, data, gasLimit: (estimatedGas * 125n) / 100n,
      })).wait();
      const events = receipt.logs.filter((log) => log.address === HOODI_REHEARSAL_SAFE).map((log) => {
        try { return safe.interface.parseLog(log)?.name; } catch { return null; }
      });
      if (receipt.status !== 1 || !events.includes("ExecutionSuccess") || events.includes("ExecutionFailure")) {
        throw new Error(`local Safe batch failed: ${batch.name}`);
      }
      if ((await safe.nonce()) !== beforeNonce + 1n) throw new Error("Safe nonce did not advance once");
      await verifyHoodiV2Batch(local, receipt.hash, index);
      for (const deployment of batch.calls.filter((call) => call.expectedAddress)) {
        if ((await local.getCode(deployment.expectedAddress)) === "0x") {
          throw new Error(`missing local deployment: ${deployment.label}`);
        }
      }
      batches.push({ name: batch.name, estimatedGas: estimatedGas.toString(), gasUsed: receipt.gasUsed.toString() });
    }
    const manager = new ethers.Contract(plan.addresses.manager, [
      "function treasury() view returns(address)", "function sebaPool() view returns(address)",
      "function vaults(uint256) view returns(address)", "function intakeEnabled() view returns(bool)",
      "function executionEnabled() view returns(bool)", "function executor() view returns(address)",
      "function cowModule() view returns(address)", "function operators(address) view returns(bool)",
      "function pendingEth(uint256) view returns(uint256)", "function pendingProtocolBold() view returns(uint256)",
    ], local);
    const module = new ethers.Contract(plan.addresses.cowModule, ["function enabled() view returns(bool)"], local);
    const executor = new ethers.Contract(plan.addresses.executor, ["function enabled() view returns(bool)"], local);
    const vaultAbi = [
      "function treasury() view returns(address)", "function manager() view returns(address)",
      "function entriesEnabled() view returns(bool)", "function harvestEnabled() view returns(bool)",
    ];
    for (const vaultAddress of [plan.addresses.rethVault, plan.addresses.ysyBoldVault]) {
      const vault = new ethers.Contract(vaultAddress, vaultAbi, local);
      if (
        (await vault.treasury()) !== HOODI_REHEARSAL_SAFE ||
        (await vault.manager()) !== plan.addresses.manager ||
        (await vault.entriesEnabled()) || (await vault.harvestEnabled())
      ) throw new Error("V2 vault unexpectedly active or misowned");
    }
    if (
      (await manager.treasury()) !== HOODI_REHEARSAL_SAFE ||
      (await manager.sebaPool()) !== manifest.v1.pool.address ||
      (await manager.vaults(0)) !== plan.addresses.rethVault ||
      (await manager.vaults(1)) !== plan.addresses.ysyBoldVault ||
      (await manager.executor()) !== plan.addresses.executor ||
      (await manager.cowModule()) !== plan.addresses.cowModule ||
      (await manager.operators(HOODI_ADMIN)) ||
      (await manager.intakeEnabled()) || (await manager.executionEnabled()) ||
      (await module.enabled()) || (await executor.enabled()) ||
      (await manager.pendingEth(0)) !== 0n || (await manager.pendingEth(1)) !== 0n ||
      (await manager.pendingProtocolBold()) !== 0n ||
      (await new ethers.Contract(manifest.v1.pool.address, poolAbi, local).yieldManager()) !== manifest.v1.manager.address ||
      (await new ethers.Contract(manifest.v1.manager.address, oldAbi, local).principalValue()) !== 2000n * 10n ** 18n ||
      (await safe.nonce()) !== initialNonce + BigInt(plan.batches.length)
    ) throw new Error("V2 staged reconciliation mismatch");
    const deployments = [];
    for (const d of plan.deployments) {
      const runtimeCodeHash = ethers.keccak256(await local.getCode(d.expectedAddress));
      if (runtimeCodeHash !== HOODI_V2_RUNTIME_HASHES[d.label]) {
        throw new Error(`fork runtime hash differs from reviewed V2 candidate: ${d.label}`);
      }
      deployments.push({ label: d.label, address: d.expectedAddress, runtimeCodeHash });
    }
    console.log(JSON.stringify({
      mode: "local-anvil-fork-only", chainId: 560048,
      anchor: { blockNumber: head.number, blockHash: head.hash },
      initialSafeNonce: initialNonce.toString(), finalSafeNonce: (await safe.nonce()).toString(),
      poolManagerUnchanged: true, allV2EntryAndExecutionDisabled: true, batches, deployments,
    }, null, 2));
  } finally {
    child.kill();
    await new Promise((resolve) => proxy.close(resolve));
  }
}

main().catch((error) => {
  console.error(`Hoodi V2 loopback rehearsal failed: ${error.code ?? error.shortMessage ?? "check source/chain/gas"}`);
  process.exitCode = 1;
});
