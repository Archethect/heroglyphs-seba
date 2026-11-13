// Read-only receipt gate for one public Hoodi V1 Safe batch. Never signs or sends.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { HOODI_ADMIN, requireHoodiChain } from "./hoodi-public-safe-plan.mjs";
import { buildHoodiV1Plan } from "./hoodi-public-v1-plan.mjs";
import { HOODI_V1_RUNTIME_HASHES } from "./hoodi-public-v1-runtime.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution, requireBatchIndex } from "./hoodi-public-v1-next.mjs";

const safeInterface = new ethers.Interface([
  "event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)",
  "event ExecutionFailure(bytes32 indexed txHash,uint256 payment)",
]);
const roleAbi = ["function hasRole(bytes32,address) view returns(bool)"];

async function requireFinalBindings(provider, plan, blockTag) {
  const address = (name) => plan.deployments.find((d) => d.name === name).expectedAddress;
  const safeRole = ethers.id("ADMIN_ROLE");
  const automatorRole = ethers.id("AUTOMATOR_ROLE");
  for (const name of ["EthToBoldRouter", "PYBSeba", "SebaPool", "EUSDUSDCBeefyYieldVault", "YieldManager"]) {
    const contract = new ethers.Contract(address(name), roleAbi, provider);
    if (
      !(await contract.hasRole(safeRole, HOODI_REHEARSAL_SAFE, { blockTag })) ||
      (await contract.hasRole(safeRole, HOODI_ADMIN, { blockTag }))
    )
      throw new Error(`admin role mismatch: ${name}`);
  }
  for (const name of ["SebaPool", "YieldManager"]) {
    const contract = new ethers.Contract(address(name), roleAbi, provider);
    if (!(await contract.hasRole(automatorRole, HOODI_ADMIN, { blockTag })))
      throw new Error(`automator role mismatch: ${name}`);
  }
  for (const [name, role] of [
    ["EthToBoldRouter", "YIELD_MANAGER_ROLE"],
    ["EUSDUSDCBeefyYieldVault", "YIELDMANAGER_ROLE"],
  ]) {
    const contract = new ethers.Contract(address(name), roleAbi, provider);
    if (
      !(await contract.hasRole(ethers.id(role), address("YieldManager"), { blockTag })) ||
      (await contract.hasRole(ethers.id(role), HOODI_REHEARSAL_SAFE, { blockTag }))
    )
      throw new Error(`manager role mismatch: ${name}`);
  }
  const pool = new ethers.Contract(
    address("SebaPool"),
    ["function yieldManager() view returns(address)", "function sebaVault() view returns(address)"],
    provider,
  );
  const pyb = new ethers.Contract(
    address("PYBSeba"),
    ["function sebaPool() view returns(address)", "function balanceOf(address) view returns(uint256)"],
    provider,
  );
  const manager = new ethers.Contract(
    address("YieldManager"),
    [
      "function depositId() view returns(uint256)",
      "function principalValue() view returns(uint256)",
      "function pendingBoldConversion() view returns(uint256)",
    ],
    provider,
  );
  if (
    (await pool.yieldManager({ blockTag })) !== address("YieldManager") ||
    (await pool.sebaVault({ blockTag })) !== address("PYBSeba") ||
    (await pyb.sebaPool({ blockTag })) !== address("SebaPool")
  )
    throw new Error("V1 pointer mismatch");
  if (
    (await pyb.balanceOf(HOODI_REHEARSAL_SAFE, { blockTag })) !== 1n ||
    (await manager.depositId({ blockTag })) !== 0n ||
    (await manager.principalValue({ blockTag })) !== 0n ||
    (await manager.pendingBoldConversion({ blockTag })) !== 0n
  )
    throw new Error("V1 clean-state mismatch");
}

export async function verifyHoodiV1Batch(provider, txHash, batchIndex) {
  if (!ethers.isHexString(txHash, 32)) throw new Error("32-byte transaction hash required");
  if (!Number.isInteger(batchIndex) || batchIndex < 0 || batchIndex > 4) throw new Error("batch index out of range");
  requireHoodiChain(await provider.send("eth_chainId", []));
  const [tx, receipt] = await Promise.all([provider.getTransaction(txHash), provider.getTransactionReceipt(txHash)]);
  if (!tx || !receipt || receipt.status !== 1) throw new Error("successful Hoodi receipt required");
  if (tx.chainId !== 560048n || tx.from !== HOODI_ADMIN || tx.to !== HOODI_REHEARSAL_SAFE || tx.value !== 0n) {
    throw new Error("Hoodi transaction sender/recipient/value/chain mismatch");
  }
  const plan = await buildHoodiV1Plan(HOODI_REHEARSAL_SAFE, HOODI_ADMIN);
  const batch = plan.batches[batchIndex];
  const expectedData = encodeOwnerSafeExecution(batch.transaction.data, HOODI_ADMIN);
  if (tx.data.toLowerCase() !== expectedData.toLowerCase())
    throw new Error("full Safe calldata differs from reviewed batch");
  const safeEvents = receipt.logs
    .filter((log) => log.address === HOODI_REHEARSAL_SAFE)
    .map((log) => {
      try {
        return safeInterface.parseLog(log)?.name;
      } catch {
        return undefined;
      }
    });
  if (!safeEvents.includes("ExecutionSuccess") || safeEvents.includes("ExecutionFailure")) {
    throw new Error("Safe did not emit ExecutionSuccess");
  }
  const blockTag = receipt.blockNumber;
  const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, ["function nonce() view returns(uint256)"], provider);
  if ((await safe.nonce({ blockTag })) !== BigInt(batchIndex + 1))
    throw new Error("Safe nonce did not advance exactly once");
  const expectedCount = [6, 11, 14, 17, 17][batchIndex];
  for (const [i, deployment] of plan.deployments.entries()) {
    const code = await provider.getCode(deployment.expectedAddress, blockTag);
    if (i < expectedCount) {
      if (code === "0x" || ethers.keccak256(code) !== HOODI_V1_RUNTIME_HASHES[deployment.label]) {
        throw new Error(`runtime mismatch after batch: ${deployment.label}`);
      }
    } else if (code !== "0x") throw new Error(`future V1 address already occupied: ${deployment.label}`);
  }
  if (batchIndex === 4) await requireFinalBindings(provider, plan, blockTag);
  return {
    network: "hoodi",
    chainId: 560048,
    readOnly: true,
    batchIndex,
    batchName: batch.name,
    txHash,
    blockNumber: receipt.blockNumber,
    blockHash: receipt.blockHash,
    transactionDataHash: ethers.keccak256(tx.data),
    gasUsed: receipt.gasUsed.toString(),
    safeExecutionSuccess: true,
    safeNonce: String(batchIndex + 1),
    verifiedDeployments: expectedCount,
    finalBindingsVerified: batchIndex === 4,
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 5)
    throw new Error(
      "Usage: node tools/hoodi-public-v1-verify.mjs <ignored-local-env-file> <batch-index-0..4> <tx-hash>",
    );
  const loaded = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || loaded.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const provider = new ethers.JsonRpcProvider(rpc);
  console.log(
    JSON.stringify(await verifyHoodiV1Batch(provider, process.argv[4], requireBatchIndex(process.argv[3])), null, 2),
  );
}
