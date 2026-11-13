// Executes the exact proposed Stage A batch ONLY on a loopback Anvil fork of current Hoodi.
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import { spawn } from "node:child_process";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { currentSource } from "./hoodi-source-gate.mjs";
import { HOODI_ADMIN } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE } from "./hoodi-public-v1-next.mjs";
import { planHoodiStageA } from "./hoodi-public-stage-a-plan.mjs";
import { verifyHoodiStageA } from "./hoodi-public-stage-a-verify.mjs";

const manifest = JSON.parse(fs.readFileSync("docs/HOODI_V2_STAGED_MANIFEST.json", "utf8"));
const safeAbi = [
  "function nonce() view returns(uint256)",
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

async function run() {
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const upstream = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!upstream || !upstream.startsWith("https://")) throw new Error("HTTPS Hoodi RPC required");
  const publicProvider = new ethers.JsonRpcProvider(upstream);
  if ((await publicProvider.getNetwork()).chainId !== 560048n) throw new Error("public RPC is not Hoodi");
  const head = await publicProvider.getBlock("latest");
  if (!head?.hash) throw new Error("missing Hoodi head");

  // The key remains in this process, not in Anvil's argv or printed output.
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
    const plan = await planHoodiStageA(local, manifest, currentSource());
    await local.send("anvil_impersonateAccount", [HOODI_ADMIN]);
    await local.send("anvil_setBalance", [HOODI_ADMIN, ethers.toBeHex(ethers.parseEther("10"))]);
    const signer = await local.getSigner(HOODI_ADMIN);
    const receipt = await (await signer.sendTransaction({
      to: plan.transaction.to, value: 0n, data: plan.transaction.data,
      gasLimit: BigInt(plan.transaction.gasLimit),
    })).wait();
    const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, safeAbi, local);
    const events = receipt.logs.filter((log) => log.address === HOODI_REHEARSAL_SAFE).map((log) => {
      try { return safe.interface.parseLog(log)?.name; } catch { return null; }
    });
    if (receipt.status !== 1 || !events.includes("ExecutionSuccess") || events.includes("ExecutionFailure")) {
      throw new Error("local Safe Stage A execution failed");
    }
    const receiptEvidence = await verifyHoodiStageA(local, receipt.hash, manifest);
    const old = new ethers.Contract(manifest.v1.manager.address, [
      "function principalValue() view returns(uint256)", "function yieldVault() view returns(address)",
      "function depositId() view returns(uint256)", "function pendingBoldConversion() view returns(uint256)",
    ], local);
    const adapter = new ethers.Contract(manifest.v1.beefyAdapter.address, [
      "function principalShares() view returns(uint256)", "function principalValue() view returns(uint256)",
    ], local);
    const beefy = new ethers.Contract(manifest.dependencies.beefyVault.address, [
      "function balanceOf(address) view returns(uint256)",
    ], local);
    const pool = new ethers.Contract(manifest.v1.pool.address, ["function yieldManager() view returns(address)"], local);
    const v2 = new ethers.Contract(manifest.v2.manager.address, [
      "function intakeEnabled() view returns(bool)", "function legacyImported() view returns(bool)",
    ], local);
    const parkedEth = await local.getBalance(manifest.v1.manager.address);
    const stopperCode = await local.getCode(plan.stopper.address);
    if ((await safe.nonce()) !== 14n || (await old.principalValue()) !== 0n ||
      (await old.yieldVault()) !== plan.stopper.address || (await old.depositId()) !== 0n ||
      (await old.pendingBoldConversion()) !== 0n || parkedEth <= 0n ||
      (await adapter.principalShares()) !== 0n || (await adapter.principalValue()) !== 0n ||
      (await beefy.balanceOf(manifest.v1.beefyAdapter.address)) !== 0n ||
      (await pool.yieldManager()) !== manifest.v1.manager.address ||
      (await v2.intakeEnabled()) || (await v2.legacyImported()) ||
      stopperCode === "0x" || ethers.keccak256(stopperCode) !== plan.stopper.runtimeCodeHash) {
      throw new Error("local Stage A accounting or stop state mismatch");
    }
    console.log(JSON.stringify({
      mode: "loopback-anvil-fork-only", chainId: 560048,
      anchor: { blockNumber: head.number, blockHash: head.hash },
      exactSafeDataHash: plan.transaction.dataHash, estimatedGas: plan.transaction.estimatedGas,
      gasUsed: receipt.gasUsed.toString(), stopper: plan.stopper.address,
      parkedEthWei: parkedEth.toString(), safeNonce: "14", poolStillOnV1: true,
      V1SharesRemaining: "0", V2StillDisabled: true,
      receiptVerified: receiptEvidence.adapterEthOutWei === parkedEth.toString(),
    }, null, 2));
  } finally {
    child.kill();
    await new Promise((resolve) => proxy.close(resolve));
  }
}

if (process.argv.length !== 3) throw new Error("Usage: node tools/hoodi-public-stage-a-fork.mjs <ignored-local-env-file>");
run().catch((error) => {
  console.error(`Hoodi loopback Stage A failed: ${error.code ?? error.shortMessage ?? error.message}`);
  process.exitCode = 1;
});
