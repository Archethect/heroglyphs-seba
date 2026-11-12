// Read-only public Hoodi receipt verifier for one reviewed V2 Safe batch.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { HOODI_ADMIN, requireHoodiChain } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";
import { requireV2BatchIndex } from "./hoodi-public-v2-next.mjs";
import { buildHoodiV2StagePlan } from "./hoodi-public-v2-plan.mjs";
import { HOODI_V2_RUNTIME_HASHES } from "./hoodi-public-v2-runtime.mjs";

const manifest = JSON.parse(fs.readFileSync("docs/HOODI_V1_PUBLIC_MANIFEST.json", "utf8"));
const safeAbi = new ethers.Interface([
  "event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)",
  "event ExecutionFailure(bytes32 indexed txHash,uint256 payment)",
  "function nonce() view returns(uint256)",
]);

export async function verifyHoodiV2Batch(provider, txHash, batchIndex) {
  if (!ethers.isHexString(txHash, 32)) throw new Error("32-byte transaction hash required");
  if (!Number.isInteger(batchIndex) || batchIndex < 0 || batchIndex > 5) throw new Error("V2 batch index out of range");
  requireHoodiChain(await provider.send("eth_chainId", []));
  const [tx, receipt] = await Promise.all([provider.getTransaction(txHash), provider.getTransactionReceipt(txHash)]);
  if (!tx || !receipt || receipt.status !== 1) throw new Error("successful Hoodi receipt required");
  if (tx.chainId !== 560048n || tx.from !== HOODI_ADMIN || tx.to !== HOODI_REHEARSAL_SAFE || tx.value !== 0n) {
    throw new Error("Hoodi transaction sender/recipient/value/chain mismatch");
  }
  const plan = await buildHoodiV2StagePlan(manifest);
  const expectedData = encodeOwnerSafeExecution(plan.batches[batchIndex].transaction.data, HOODI_ADMIN);
  if (tx.data.toLowerCase() !== expectedData.toLowerCase()) {
    throw new Error("full Safe calldata differs from reviewed V2 batch");
  }
  const events = receipt.logs.filter((log) => log.address === HOODI_REHEARSAL_SAFE).map((log) => {
    try { return safeAbi.parseLog(log)?.name; } catch { return null; }
  });
  if (!events.includes("ExecutionSuccess") || events.includes("ExecutionFailure")) {
    throw new Error("Safe did not emit ExecutionSuccess");
  }
  const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, safeAbi, provider);
  if ((await safe.nonce({ blockTag: receipt.blockNumber })) !== BigInt(8 + batchIndex)) {
    throw new Error("Safe nonce did not advance exactly once");
  }
  const deployedCount = [2, 4, 6, 8, 11, 11][batchIndex];
  for (const [i, d] of plan.deployments.entries()) {
    const code = await provider.getCode(d.expectedAddress, receipt.blockNumber);
    if (i < deployedCount) {
      if (code === "0x" || ethers.keccak256(code) !== HOODI_V2_RUNTIME_HASHES[d.label]) {
        throw new Error(`V2 deployment runtime mismatch: ${d.label}`);
      }
    } else if (code !== "0x") {
      throw new Error(`future V2 address occupied: ${d.label}`);
    }
  }
  const pool = new ethers.Contract(manifest.v1.pool.address, ["function yieldManager() view returns(address)"], provider);
  if ((await pool.yieldManager({ blockTag: receipt.blockNumber })) !== manifest.v1.manager.address) {
    throw new Error("V1 pool pointer changed during V2 staging");
  }
  if (batchIndex === 5) {
    const manager = new ethers.Contract(plan.addresses.manager, [
      "function treasury() view returns(address)", "function sebaPool() view returns(address)",
      "function vaults(uint256) view returns(address)", "function intakeEnabled() view returns(bool)",
      "function executionEnabled() view returns(bool)", "function executor() view returns(address)",
      "function cowModule() view returns(address)", "function operators(address) view returns(bool)",
      "function pendingEth(uint256) view returns(uint256)", "function pendingProtocolBold() view returns(uint256)",
    ], provider);
    const blockTag = receipt.blockNumber;
    if (
      (await manager.treasury({ blockTag })) !== HOODI_REHEARSAL_SAFE ||
      (await manager.sebaPool({ blockTag })) !== manifest.v1.pool.address ||
      (await manager.vaults(0, { blockTag })) !== plan.addresses.rethVault ||
      (await manager.vaults(1, { blockTag })) !== plan.addresses.ysyBoldVault ||
      (await manager.executor({ blockTag })) !== plan.addresses.executor ||
      (await manager.cowModule({ blockTag })) !== plan.addresses.cowModule ||
      (await manager.operators(HOODI_ADMIN, { blockTag })) ||
      (await manager.intakeEnabled({ blockTag })) || (await manager.executionEnabled({ blockTag })) ||
      (await manager.pendingEth(0, { blockTag })) !== 0n ||
      (await manager.pendingEth(1, { blockTag })) !== 0n ||
      (await manager.pendingProtocolBold({ blockTag })) !== 0n
    ) throw new Error("V2 manager staged state mismatch");
    const vaultAbi = [
      "function treasury() view returns(address)", "function manager() view returns(address)",
      "function entriesEnabled() view returns(bool)", "function harvestEnabled() view returns(bool)",
    ];
    for (const address of [plan.addresses.rethVault, plan.addresses.ysyBoldVault]) {
      const vault = new ethers.Contract(address, vaultAbi, provider);
      if (
        (await vault.treasury({ blockTag })) !== HOODI_REHEARSAL_SAFE ||
        (await vault.manager({ blockTag })) !== plan.addresses.manager ||
        (await vault.entriesEnabled({ blockTag })) || (await vault.harvestEnabled({ blockTag }))
      ) throw new Error("V2 vault staged state mismatch");
    }
    for (const address of [plan.addresses.executor, plan.addresses.cowModule]) {
      const c = new ethers.Contract(address, ["function enabled() view returns(bool)"], provider);
      if (await c.enabled({ blockTag })) throw new Error("V2 integration unexpectedly enabled");
    }
  }
  return {
    chainId: 560048, batchIndex, batchName: plan.batches[batchIndex].name,
    transactionHash: txHash, blockNumber: receipt.blockNumber, blockHash: receipt.blockHash,
    safeNonce: (8 + batchIndex).toString(), poolPointerUnchanged: true,
    verifiedDeployments: plan.deployments.slice(0, deployedCount).map((d) => d.label),
    stagedStateVerified: batchIndex === 5,
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 5) {
    throw new Error("Usage: node tools/hoodi-public-v2-verify.mjs <ignored-local-env-file> <batch-index-0..5> <tx-hash>");
  }
  const loaded = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || loaded.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  console.log(JSON.stringify(await verifyHoodiV2Batch(
    new ethers.JsonRpcProvider(rpc), process.argv[4], requireV2BatchIndex(process.argv[3]),
  ), null, 2));
}
