// Read-only, one-batch-at-a-time Hoodi V1 Safe transaction planner. Never signs or sends.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { currentSource } from "./hoodi-source-gate.mjs";
import {
  HOODI_ADMIN,
  HOODI_CHAIN_ID,
  SAFE_MULTISEND,
  SAFE_SINGLETON,
  requireHoodiChain,
  requireExpectedCodeHash,
} from "./hoodi-public-safe-plan.mjs";
import { CREATE_CALL, CREATE_CALL_CODE_HASH } from "./hoodi-safe-createcall.mjs";
import { buildHoodiV1Plan } from "./hoodi-public-v1-plan.mjs";
import { HOODI_V1_RUNTIME_HASHES } from "./hoodi-public-v1-runtime.mjs";

export const HOODI_REHEARSAL_SAFE = "0xAc52395a9D706696Cf36125A0664c0C6d2B06B7b";
const SAFE_CODE_HASH = "0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c";
const GUARD_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8";
const SENTINEL_MODULES = "0x0000000000000000000000000000000000000001";
const SAFE_ABI = [
  "function nonce() view returns(uint256)",
  "function getOwners() view returns(address[])",
  "function getThreshold() view returns(uint256)",
  "function getModulesPaginated(address,uint256) view returns(address[],address)",
  "function execTransaction(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,bytes signatures) returns(bool)",
];
const safeInterface = new ethers.Interface(SAFE_ABI);

export function requireBatchIndex(input) {
  if (typeof input !== "string" || !/^[0-4]$/.test(input))
    throw new Error("batch index must be explicitly selected from 0 to 4");
  return Number(input);
}

export function encodeOwnerSafeExecution(batchData, owner) {
  if (!ethers.isHexString(batchData) || batchData === "0x") throw new Error("batch data required");
  if (!ethers.isAddress(owner) || owner === ethers.ZeroAddress) throw new Error("owner required");
  const signature = ethers.concat([ethers.zeroPadValue(owner, 32), ethers.ZeroHash, "0x01"]);
  return safeInterface.encodeFunctionData("execTransaction", [
    SAFE_MULTISEND,
    0,
    batchData,
    1,
    0,
    0,
    0,
    ethers.ZeroAddress,
    ethers.ZeroAddress,
    signature,
  ]);
}

export async function planNextHoodiV1Batch(provider, batchIndex, source = currentSource()) {
  if (!Number.isInteger(batchIndex) || batchIndex < 0 || batchIndex > 4) throw new Error("batch index out of range");
  requireHoodiChain(await provider.send("eth_chainId", []));
  const head = await provider.getBlock("latest");
  if (!head?.hash) throw new Error("missing Hoodi head");
  const blockTag = head.number;
  const checks = [
    [HOODI_REHEARSAL_SAFE, SAFE_CODE_HASH],
    [CREATE_CALL, CREATE_CALL_CODE_HASH],
  ];
  for (const [address, expectedHash] of checks) {
    const code = await provider.getCode(address, blockTag);
    if (code === "0x" || ethers.keccak256(code) !== expectedHash)
      throw new Error(`Hoodi code hash mismatch: ${address}`);
  }
  requireExpectedCodeHash(SAFE_MULTISEND, await provider.getCode(SAFE_MULTISEND, blockTag));
  requireExpectedCodeHash(SAFE_SINGLETON, await provider.getCode(SAFE_SINGLETON, blockTag));
  const singletonSlot = await provider.getStorage(HOODI_REHEARSAL_SAFE, 0, blockTag);
  if (ethers.getAddress(`0x${singletonSlot.slice(-40)}`) !== SAFE_SINGLETON)
    throw new Error("Safe singleton pointer mismatch");
  const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, SAFE_ABI, provider);
  const [nonce, owners, threshold, modules, guard] = await Promise.all([
    safe.nonce({ blockTag }),
    safe.getOwners({ blockTag }),
    safe.getThreshold({ blockTag }),
    safe.getModulesPaginated(SENTINEL_MODULES, 10, { blockTag }),
    provider.getStorage(HOODI_REHEARSAL_SAFE, GUARD_SLOT, blockTag),
  ]);
  if (nonce !== BigInt(batchIndex)) throw new Error(`Safe nonce ${nonce} differs from selected batch ${batchIndex}`);
  if (
    owners.length !== 1 ||
    owners[0] !== HOODI_ADMIN ||
    threshold !== 1n ||
    modules[0].length !== 0 ||
    modules[1] !== SENTINEL_MODULES ||
    BigInt(guard) !== 0n
  ) {
    throw new Error("Hoodi Safe owner/threshold/module/guard policy changed");
  }
  const plan = await buildHoodiV1Plan(HOODI_REHEARSAL_SAFE, HOODI_ADMIN);
  for (const [i, deployment] of plan.deployments.entries()) {
    const shouldExist = i < [0, 6, 11, 14, 17][batchIndex];
    const code = await provider.getCode(deployment.expectedAddress, blockTag);
    if ((code !== "0x") !== shouldExist) throw new Error(`V1 deployment state mismatch: ${deployment.label}`);
    if (shouldExist && ethers.keccak256(code) !== HOODI_V1_RUNTIME_HASHES[deployment.label]) {
      throw new Error(`V1 runtime code hash mismatch: ${deployment.label}`);
    }
  }
  const batch = plan.batches[batchIndex];
  const data = encodeOwnerSafeExecution(batch.transaction.data, HOODI_ADMIN);
  const request = { from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, value: 0n, data };
  const callResult = await provider.call({ ...request, blockTag });
  const [willSucceed] = safeInterface.decodeFunctionResult("execTransaction", callResult);
  if (!willSucceed) throw new Error("Hoodi Safe eth_call returned false; refusing batch");
  const estimatedGas = await provider.estimateGas(request);
  const gasLimit = (estimatedGas * 125n) / 100n;
  const fees = await provider.getFeeData();
  const maxFeePerGas = fees.maxFeePerGas ?? fees.gasPrice;
  if (!maxFeePerGas) throw new Error("Hoodi gas fee unavailable");
  const balanceWei = await provider.getBalance(HOODI_ADMIN, blockTag);
  const maximumGasCostWei = gasLimit * maxFeePerGas;
  if (balanceWei < maximumGasCostWei) throw new Error("Hoodi admin wallet cannot cover maximum gas cost");
  const ownerNonce = await provider.getTransactionCount(HOODI_ADMIN, "latest");
  const pendingOwnerNonce = await provider.getTransactionCount(HOODI_ADMIN, "pending");
  if (ownerNonce !== pendingOwnerNonce) throw new Error("admin EOA has pending transactions");
  return {
    schemaVersion: "seba-hoodi-public-v1-next-v1",
    readOnly: true,
    broadcast: false,
    executionReady: !source.worktreeDirty,
    network: "hoodi",
    chainId: Number(HOODI_CHAIN_ID),
    source,
    observedAt: { blockNumber: head.number, blockHash: head.hash },
    signer: { address: HOODI_ADMIN, method: "Remix browser wallet", nonce: pendingOwnerNonce },
    safe: { address: HOODI_REHEARSAL_SAFE, nonce: nonce.toString(), owner: HOODI_ADMIN, threshold: 1 },
    batch: {
      index: batchIndex,
      name: batch.name,
      calls: batch.calls.map((call) => ({
        label: call.label ?? call.name,
        to: call.to,
        expectedAddress: call.expectedAddress ?? null,
        creationCodeHash: call.creationCodeHash ?? null,
      })),
    },
    transaction: {
      from: HOODI_ADMIN,
      to: HOODI_REHEARSAL_SAFE,
      valueWei: "0",
      data,
      dataBytes: ethers.dataLength(data),
      dataHash: ethers.keccak256(data),
      estimatedGas: estimatedGas.toString(),
      gasLimit: gasLimit.toString(),
      maxFeePerGasWei: maxFeePerGas.toString(),
      maxPriorityFeePerGasWei: fees.maxPriorityFeePerGas?.toString() ?? null,
      maximumGasCostWei: maximumGasCostWei.toString(),
      walletBalanceWei: balanceWei.toString(),
    },
    abortIf: [
      "Wallet network is not Hoodi (chain 560048), or sender is not the verified sole Safe owner.",
      "Recipient is not the verified Hoodi Safe, ETH value is nonzero, or calldata hash differs.",
      "Safe nonce or any prior/future deployment state differs from this selected batch; regenerate the plan.",
      "Safe owner/threshold/module/guard or Safe/CreateCall/MultiSend code hash changes.",
      "The source worktree is dirty, the owner has a pending transaction, or eth_call no longer returns true.",
      "Fee ceiling or gas estimate changes materially; regenerate and review the plan.",
    ],
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 4)
    throw new Error("Usage: node tools/hoodi-public-v1-next.mjs <ignored-local-env-file> <batch-index-0..4>");
  const loaded = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || loaded.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const provider = new ethers.JsonRpcProvider(rpc);
  console.log(JSON.stringify(await planNextHoodiV1Batch(provider, requireBatchIndex(process.argv[3])), null, 2));
}
