// Read-only, one-batch-at-a-time Hoodi V2 Safe planner. Never signs or sends.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { currentSource } from "./hoodi-source-gate.mjs";
import { HOODI_ADMIN, requireHoodiChain, requireExpectedCodeHash, SAFE_MULTISEND, SAFE_SINGLETON } from "./hoodi-public-safe-plan.mjs";
import { CREATE_CALL, CREATE_CALL_CODE_HASH } from "./hoodi-safe-createcall.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";
import { buildHoodiV2StagePlan } from "./hoodi-public-v2-plan.mjs";
import { HOODI_V2_RUNTIME_HASHES } from "./hoodi-public-v2-runtime.mjs";

const manifest = JSON.parse(fs.readFileSync("docs/HOODI_V1_PUBLIC_MANIFEST.json", "utf8"));
const GUARD_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8";
const SENTINEL_MODULES = "0x0000000000000000000000000000000000000001";
const SAFE_ABI = [
  "function nonce() view returns(uint256)",
  "function getOwners() view returns(address[])",
  "function getThreshold() view returns(uint256)",
  "function getModulesPaginated(address,uint256) view returns(address[],address)",
  "function execTransaction(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,bytes signatures) returns(bool)",
];

export function requireV2BatchIndex(input) {
  if (typeof input !== "string" || !/^[0-5]$/.test(input)) {
    throw new Error("V2 batch index must be explicitly selected from 0 to 5");
  }
  return Number(input);
}

export function expectedDeployedCount(index) {
  if (!Number.isInteger(index) || index < 0 || index > 5) throw new Error("V2 batch index out of range");
  return [0, 2, 4, 6, 8, 11][index];
}

export async function planNextHoodiV2Batch(provider, batchIndex, source = currentSource()) {
  const expectedCount = expectedDeployedCount(batchIndex);
  requireHoodiChain(await provider.send("eth_chainId", []));
  const head = await provider.getBlock("latest");
  if (!head?.hash) throw new Error("missing Hoodi head");
  const blockTag = head.number;
  const plan = await buildHoodiV2StagePlan(manifest);
  const safeCode = await provider.getCode(HOODI_REHEARSAL_SAFE, blockTag);
  if (safeCode === "0x" || ethers.keccak256(safeCode) !== manifest.safe.runtimeCodeHash) {
    throw new Error("Hoodi Safe runtime mismatch");
  }
  const createCallCode = await provider.getCode(CREATE_CALL, blockTag);
  if (createCallCode === "0x" || ethers.keccak256(createCallCode) !== CREATE_CALL_CODE_HASH) {
    throw new Error("Hoodi CreateCall runtime mismatch");
  }
  requireExpectedCodeHash(SAFE_SINGLETON, await provider.getCode(SAFE_SINGLETON, blockTag));
  requireExpectedCodeHash(SAFE_MULTISEND, await provider.getCode(SAFE_MULTISEND, blockTag));
  const singletonSlot = await provider.getStorage(HOODI_REHEARSAL_SAFE, 0, blockTag);
  if (ethers.getAddress(`0x${singletonSlot.slice(-40)}`) !== SAFE_SINGLETON) {
    throw new Error("Safe singleton pointer mismatch");
  }
  const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, SAFE_ABI, provider);
  const [nonce, owners, threshold, modules, guard] = await Promise.all([
    safe.nonce({ blockTag }),
    safe.getOwners({ blockTag }),
    safe.getThreshold({ blockTag }),
    safe.getModulesPaginated(SENTINEL_MODULES, 10, { blockTag }),
    provider.getStorage(HOODI_REHEARSAL_SAFE, GUARD_SLOT, blockTag),
  ]);
  if (
    nonce !== BigInt(7 + batchIndex) || owners.length !== 1 || owners[0] !== HOODI_ADMIN ||
    threshold !== 1n || modules[0].length !== 0 || modules[1] !== SENTINEL_MODULES || BigInt(guard) !== 0n
  ) throw new Error("Hoodi Safe nonce or owner/threshold/module/guard policy changed");
  for (const group of [manifest.dependencies, manifest.v1]) {
    for (const entry of Object.values(group)) {
      if (!entry?.address || !entry.runtimeCodeHash) continue;
      const code = await provider.getCode(entry.address, blockTag);
      if (code === "0x" || ethers.keccak256(code) !== entry.runtimeCodeHash) {
        throw new Error(`V1 code hash mismatch: ${entry.address}`);
      }
    }
  }
  const pool = new ethers.Contract(manifest.v1.pool.address, ["function yieldManager() view returns(address)"], provider);
  const old = new ethers.Contract(manifest.v1.manager.address, [
    "function depositId() view returns(uint256)", "function principalValue() view returns(uint256)",
    "function pendingBoldConversion() view returns(uint256)",
  ], provider);
  if (
    (await pool.yieldManager({ blockTag })) !== manifest.v1.manager.address ||
    (await old.depositId({ blockTag })) !== 0n ||
    (await old.principalValue({ blockTag })) !== 2000n * 10n ** 18n ||
    (await old.pendingBoldConversion({ blockTag })) !== 0n
  ) throw new Error("V1 state changed; stop V2 staging and reconcile");
  for (const [index, d] of plan.deployments.entries()) {
    const code = await provider.getCode(d.expectedAddress, blockTag);
    if (index < expectedCount) {
      if (code === "0x" || ethers.keccak256(code) !== HOODI_V2_RUNTIME_HASHES[d.label]) {
        throw new Error(`prior V2 deployment differs: ${d.label}`);
      }
    } else if (code !== "0x") {
      throw new Error(`future V2 address already occupied: ${d.label}`);
    }
  }
  const batch = plan.batches[batchIndex];
  const data = encodeOwnerSafeExecution(batch.transaction.data, HOODI_ADMIN);
  const request = { from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, value: 0n, data };
  const callResult = await provider.call({ ...request, blockTag });
  const [willSucceed] = new ethers.Interface(SAFE_ABI).decodeFunctionResult("execTransaction", callResult);
  if (!willSucceed) throw new Error("Hoodi Safe eth_call returned false; refusing batch");
  const estimatedGas = await provider.estimateGas(request);
  const gasLimit = (estimatedGas * 125n) / 100n;
  const fees = await provider.getFeeData();
  const maxFeePerGas = fees.maxFeePerGas ?? fees.gasPrice;
  if (!maxFeePerGas) throw new Error("Hoodi gas fee unavailable");
  const walletBalanceWei = await provider.getBalance(HOODI_ADMIN, blockTag);
  const maximumGasCostWei = gasLimit * maxFeePerGas;
  if (walletBalanceWei < maximumGasCostWei) throw new Error("Hoodi admin wallet lacks maximum gas cost");
  const walletNonce = await provider.getTransactionCount(HOODI_ADMIN, "latest");
  if (walletNonce !== (await provider.getTransactionCount(HOODI_ADMIN, "pending"))) {
    throw new Error("Hoodi admin EOA has pending transactions");
  }
  return {
    schemaVersion: "seba-hoodi-public-v2-next-v1", readOnly: true, broadcast: false,
    executionReady: !source.worktreeDirty, network: "hoodi", chainId: 560048,
    source, observedAt: { blockNumber: head.number, blockHash: head.hash },
    safe: HOODI_REHEARSAL_SAFE, safeNonce: nonce.toString(), batchIndex,
    batchName: batch.name, expectedNewDeployments: batch.calls.filter((c) => c.expectedAddress).map((c) => ({
      label: c.label, address: c.expectedAddress, runtimeCodeHash: HOODI_V2_RUNTIME_HASHES[c.label],
    })),
    signer: { address: HOODI_ADMIN, method: "owner-wallet-ui", nonce: walletNonce },
    transaction: {
      from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, valueWei: "0", data,
      dataBytes: ethers.dataLength(data), dataHash: ethers.keccak256(data),
      estimatedGas: estimatedGas.toString(), gasLimit: gasLimit.toString(),
      maxFeePerGasWei: maxFeePerGas.toString(), maximumGasCostWei: maximumGasCostWei.toString(),
      walletBalanceWei: walletBalanceWei.toString(),
    },
    abortIf: [
      "Wallet is not Hoodi chain 560048 or the sender is not the verified sole Safe owner.",
      "Recipient, ETH value, full calldata hash, Safe nonce or V1/V2 code/state differs; regenerate.",
      "Source worktree is dirty, owner has a pending transaction, or eth_call no longer returns true.",
      "Gas/fee ceiling changes materially, or a prior Safe execution has not been receipt-verified.",
      "Pool manager pointer changes or any V2 entry/execution is enabled before Stage B approval.",
    ],
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 4) {
    throw new Error("Usage: node tools/hoodi-public-v2-next.mjs <ignored-local-env-file> <batch-index-0..5>");
  }
  const loaded = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || loaded.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const provider = new ethers.JsonRpcProvider(rpc);
  console.log(JSON.stringify(await planNextHoodiV2Batch(provider, requireV2BatchIndex(process.argv[3])), null, 2));
}
