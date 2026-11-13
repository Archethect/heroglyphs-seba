// Executes both proposed Hoodi Stage B Safe transactions ONLY on a fresh loopback Anvil fork.
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import { spawn } from "node:child_process";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { currentSource } from "./hoodi-source-gate.mjs";
import { HOODI_ADMIN } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";
import { buildStageBCalls, planStageBHandoffDeployment } from "./hoodi-public-stage-b-plan.mjs";
import { planStageBCutover } from "./hoodi-public-stage-b-exec-plan.mjs";
import { verifyHoodiStageBCutover } from "./hoodi-public-stage-b-verify.mjs";
import { multiSendData } from "./hoodi-safe-createcall.mjs";

const approvalBytes = fs.readFileSync("docs/HOODI_PHASE5_STAGE_B_MANIFEST.json", "utf8");
const approval = JSON.parse(approvalBytes);
const staged = JSON.parse(fs.readFileSync("docs/HOODI_V2_STAGED_MANIFEST.json", "utf8"));
const safeAbi = [
  "function nonce() view returns(uint256)",
  "event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)",
  "event ExecutionFailure(bytes32 indexed txHash,uint256 payment)",
];
const handoffAbi = [
  "function CONFIGURATION_HASH() view returns(bytes32)", "function used() view returns(bool)",
  "function configuration() view returns(tuple(address oldManager,address destination,address treasury,address pool,address oldVault,address stagingVault,address oldRouter,uint256 expectedEth,uint256 expiry,uint256 oldPrincipal,uint256 oldDepositId,uint256 adapterPrincipal,uint256 adapterShares,uint256 actualBeefyShares,uint256 oldIdleEth,bytes32 safeOwnersHash,uint256 safeThreshold,uint16 rethBps,bytes32 manifest,uint256 maximumRouterEth,uint256 maximumOldBold,uint256 maximumOldSBold,uint256 maximumRouterBold))",
  "event ResidualSurplusObserved(bytes32 indexed manifest,uint256 routerEth,uint256 oldBold,uint256 oldSBold,uint256 routerBold)",
  "event PostMigrationChecked(bytes32 indexed manifest,uint256 residualAdapterPrincipal,uint256 residualAdapterShares,uint256 residualBeefyShares)",
];

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

function namedEvents(receipt, address, abi) {
  const iface = new ethers.Interface(abi);
  return receipt.logs.filter((log) => log.address === address).map((log) => {
    try { return iface.parseLog(log); } catch { return null; }
  }).filter(Boolean);
}

async function run() {
  if (process.argv.length !== 3) throw new Error("Usage: node tools/hoodi-public-stage-b-fork.mjs <ignored-local-env-file>");
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const upstream = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!upstream?.startsWith("https://")) throw new Error("HTTPS Hoodi RPC required");
  const publicProvider = new ethers.JsonRpcProvider(upstream);
  if ((await publicProvider.getNetwork()).chainId !== 560048n) throw new Error("public RPC is not Hoodi");
  const head = await publicProvider.getBlock("latest");
  if (!head?.hash) throw new Error("missing Hoodi head");

  // Keep the upstream URL/key out of Anvil arguments and output.
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
      response.end('{"error":"isolated Hoodi upstream unavailable"}');
    }
  });
  await new Promise((resolve) => proxy.listen(0, "127.0.0.1", resolve));
  const port = await freePort();
  const child = spawn("anvil", [
    "--fork-url", `http://127.0.0.1:${proxy.address().port}`,
    "--fork-block-number", String(head.number), "--chain-id", "560048",
    "--host", "127.0.0.1", "--port", String(port), "--silent",
  ], { stdio: "ignore" });
  try {
    const local = new ethers.JsonRpcProvider(`http://127.0.0.1:${port}`);
    let ready = false;
    for (let i = 0; i < 150; i++) {
      if (child.exitCode !== null) throw new Error("Anvil exited before readiness");
      try { if ((await local.getNetwork()).chainId === 560048n) { ready = true; break; } }
      catch { /* startup */ }
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    if (!ready) throw new Error("loopback Hoodi fork unavailable");
    const info = await local.send("anvil_nodeInfo", []);
    if (Number(info.forkConfig?.forkBlockNumber) !== head.number ||
      (await local.getBlock(head.number))?.hash !== head.hash) throw new Error("fork anchor mismatch");

    const source = { ...currentSource(), worktreeDirty: false }; // source code itself is separately pinned by the planner
    const plan = await planStageBHandoffDeployment(local, approval, staged, approvalBytes, source);
    await local.send("anvil_impersonateAccount", [HOODI_ADMIN]);
    await local.send("anvil_setBalance", [HOODI_ADMIN, ethers.toBeHex(ethers.parseEther("10"))]);
    const signer = await local.getSigner(HOODI_ADMIN);
    const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, safeAbi, local);
    const deployed = await (await signer.sendTransaction({
      to: plan.transaction.to, value: 0n, data: plan.transaction.data,
      gasLimit: BigInt(plan.transaction.gasLimit),
    })).wait();
    const deployEvents = namedEvents(deployed, HOODI_REHEARSAL_SAFE, safeAbi).map((event) => event.name);
    if (deployed.status !== 1 || !deployEvents.includes("ExecutionSuccess") || deployEvents.includes("ExecutionFailure") ||
      await safe.nonce() !== 15n || await local.getCode(plan.handoff.expectedAddress) === "0x")
      throw new Error("local handoff deployment failed");
    const handoff = new ethers.Contract(plan.handoff.expectedAddress, handoffAbi, local);
    const config = await handoff.configuration();
    if (await handoff.CONFIGURATION_HASH() !== plan.configurationHash ||
      config.manifest !== plan.approvalManifestHash || config.expectedEth !== 10n ** 18n ||
      config.expiry !== BigInt(plan.expiry) || config.maximumOldBold !== 0n)
      throw new Error("local deployed handoff configuration mismatch");

    const calls = buildStageBCalls(approval, staged, plan.handoff.expectedAddress, plan.expiry, plan.approvalManifestHash);
    const cutoverData = encodeOwnerSafeExecution(multiSendData(calls), HOODI_ADMIN);
    const executionPlan = await planStageBCutover(local, approval, staged, approvalBytes, plan,
      deployed.hash, source, true /* verified exact local deployment; no Etherscan on fork */);
    if (!executionPlan.executionReady || executionPlan.transaction.data !== cutoverData ||
      executionPlan.transaction.safeNonce !== "15") throw new Error("local/public Stage B planner mismatch");
    const cutoverRequest = { from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, value: 0n, data: cutoverData };
    const safeInterface = new ethers.Interface([
      "function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns(bool)",
    ]);
    if (!safeInterface.decodeFunctionResult("execTransaction", await local.call(cutoverRequest))[0])
      throw new Error("local Stage B complete Safe batch returned false");
    const cutoverGasEstimate = await local.estimateGas(cutoverRequest);
    const cutover = await (await signer.sendTransaction({
      ...cutoverRequest, gasLimit: (cutoverGasEstimate * 125n) / 100n,
    })).wait();
    const receiptEvidence = await verifyHoodiStageBCutover(local, approval, staged, executionPlan, cutover.hash);
    if (receiptEvidence.importedEthWei !== approval.stageA.parkedEthWei)
      throw new Error("local/public Stage B receipt verifier mismatch");
    const cutoverEvents = namedEvents(cutover, HOODI_REHEARSAL_SAFE, safeAbi).map((event) => event.name);
    const handoffEvents = namedEvents(cutover, plan.handoff.expectedAddress, handoffAbi);
    if (cutover.status !== 1 || !cutoverEvents.includes("ExecutionSuccess") ||
      cutoverEvents.includes("ExecutionFailure") || await safe.nonce() !== 16n ||
      !(await handoff.used()) ||
      !handoffEvents.some((event) => event.name === "PostMigrationChecked") ||
      !handoffEvents.some((event) => event.name === "ResidualSurplusObserved" &&
        event.args.routerEth === 0n && event.args.oldBold === 0n &&
        event.args.oldSBold === 0n && event.args.routerBold === 0n))
      throw new Error("local Stage B Safe events or use mismatch");

    const old = new ethers.Contract(approval.legacy.manager, [
      "function principalValue() view returns(uint256)", "function yieldVault() view returns(address)",
    ], local);
    const pool = new ethers.Contract(approval.legacy.pool, ["function yieldManager() view returns(address)"], local);
    const v2 = new ethers.Contract(approval.destination.managerProxy, [
      "function intakeEnabled() view returns(bool)", "function executionEnabled() view returns(bool)",
      "function legacyImported() view returns(bool)", "function pendingEth(uint256) view returns(uint256)",
    ], local);
    const oldEth = await local.getBalance(approval.legacy.manager);
    const v2Eth = await local.getBalance(approval.destination.managerProxy);
    const r = await v2.pendingEth(1);
    const y = await v2.pendingEth(2);
    if (oldEth !== 0n || v2Eth !== 10n ** 18n || r !== 5n * 10n ** 17n || y !== 5n * 10n ** 17n ||
      await old.principalValue() !== 0n || await old.yieldVault() !== plan.handoff.expectedAddress ||
      await pool.yieldManager() !== approval.destination.managerProxy ||
      !(await v2.intakeEnabled()) || await v2.executionEnabled() || !(await v2.legacyImported()))
      throw new Error("local Stage B final accounting mismatch");

    console.log(JSON.stringify({
      mode: "loopback-anvil-fork-only", chainId: 560048,
      anchor: { blockNumber: head.number, blockHash: head.hash },
      approvalManifestHash: plan.approvalManifestHash, configurationHash: plan.configurationHash,
      handoff: plan.handoff.expectedAddress, expiry: plan.expiry,
      handoffDeployment: { safeDataHash: plan.transaction.dataHash, gasUsed: deployed.gasUsed.toString() },
      cutover: { safeDataHash: ethers.keccak256(cutoverData), estimatedGas: cutoverGasEstimate.toString(),
        gasUsed: cutover.gasUsed.toString(), calls: calls.map((call) => call.label) },
      final: { safeNonce: "16", oldEthWei: oldEth.toString(), v2EthWei: v2Eth.toString(),
        pendingRethEthWei: r.toString(), pendingYsyBoldEthWei: y.toString(),
        poolOnV2: true, v2IntakeEnabled: true, v2ExecutionDisabled: true,
        unmigratedSurplusZero: true },
    }, null, 2));
  } finally {
    child.kill();
    await new Promise((resolve) => proxy.close(resolve));
  }
}

run().catch((error) => {
  console.error(`Hoodi loopback Stage B failed: ${error.code ?? error.shortMessage ?? error.message}`);
  process.exitCode = 1;
});
