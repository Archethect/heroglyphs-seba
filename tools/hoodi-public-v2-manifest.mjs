// Receipt-backed Hoodi V2 stage evidence. Read-only RPC; never signs or sends.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { HOODI_ADMIN, requireHoodiChain } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE } from "./hoodi-public-v1-next.mjs";
import { buildHoodiV2StagePlan } from "./hoodi-public-v2-plan.mjs";
import { HOODI_V2_RUNTIME_HASHES } from "./hoodi-public-v2-runtime.mjs";
import { verifyHoodiV2Batch } from "./hoodi-public-v2-verify.mjs";

const PREVIOUS_PATH = "docs/HOODI_V1_PUBLIC_MANIFEST.json";
const DESTINATION = "docs/HOODI_V2_STAGED_MANIFEST.json";
const TX_HASHES = [
  "0xb45daa5bff8f25e10357d505cc6b4c57ff045c7c0d98a1dba150c4aa19cccf8e",
  "0x96a4b099b45564f5bc78e529d5398103c8085fe1ef1d2ea8a22bda3e8128344a",
  "0x35cf5908ccbb426a9b82d8ee7360d33988cbc011b50496548e9eab1955386133",
  "0x4f9416db0a5f8e511c673828e20f26d2e3f5c17cba4debdc17fa75cbed7b5bf8",
  "0x2ae55e599f7a27b7b7a7f114d6be17f6110d0a5e0dd00f6aa26167873625167c",
  "0xf557a12d01b12ae3aabf12f80f7c192cab891b44a2230c7e531ca25ca6243ed8",
];
const DEPENDENCY_LABELS = { yBold: "yBold", ysyBold: "ysyBold", cowSettlement: "cowSettlement" };
const V2_LABELS = {
  managerImplementation: "managerImplementation", managerProxy: "manager",
  rethImplementation: "rethImplementation", rethProxy: "rethVault",
  ysyBoldImplementation: "ysyBoldImplementation", ysyBoldProxy: "ysyBoldVault",
  SebaV2DirectExecutor: "executor", cowModule: "cowModule",
};

function requireSameOnchainSource(commit) {
  execFileSync("git", ["diff", "--quiet", commit, "HEAD", "--", "src", "script", "foundry.toml"], { stdio: "ignore" });
  const dirty = execFileSync("git", ["status", "--porcelain", "--untracked-files=all", "--", "src", "script", "foundry.toml"], { encoding: "utf8" });
  if (dirty.trim()) throw new Error("onchain source changed since Hoodi V1 evidence");
}

function requireReceiptSequence(receipts) {
  if (!Array.isArray(receipts) || receipts.length !== 6) throw new Error("six ordered V2 receipts required");
  for (const [index, receipt] of receipts.entries()) {
    if (
      !ethers.isHexString(receipt?.transactionHash, 32) ||
      !ethers.isHexString(receipt?.blockHash, 32) ||
      !Number.isSafeInteger(receipt?.blockNumber) || receipt.blockNumber < 1 ||
      (index > 0 && receipt.blockNumber <= receipts[index - 1].blockNumber)
    ) throw new Error("invalid or unordered V2 receipt evidence");
  }
}

/** Assemble only from individually verified receipts; callers must independently prove live state. */
export function assembleHoodiV2Manifest(previousBytes, plan, receipts, relayer) {
  requireReceiptSequence(receipts);
  if (!ethers.isAddress(relayer?.address) || !ethers.isHexString(relayer?.runtimeCodeHash, 32)) {
    throw new Error("verified mock CoW relayer identity required");
  }
  const previous = JSON.parse(Buffer.from(previousBytes).toString("utf8"));
  if (previous.phase !== "v1-ready" || previous.chainId !== 560048 || plan.safe !== previous.safe.address) {
    throw new Error("wrong prior Hoodi phase or Safe");
  }
  const result = structuredClone(previous);
  result.phase = "v2-staged";
  result.previousManifestHash = ethers.keccak256(previousBytes);
  result.v2 = {};
  result.cutover = {};
  for (const [index, deployment] of plan.deployments.entries()) {
    const group = DEPENDENCY_LABELS[deployment.label] ? "dependencies" : "v2";
    const key = DEPENDENCY_LABELS[deployment.label] ?? V2_LABELS[deployment.label];
    if (!key) throw new Error(`V2 deployment has no manifest field: ${deployment.label}`);
    const receipt = receipts[index < 2 ? 0 : index < 4 ? 1 : index < 6 ? 2 : index < 8 ? 3 : 4];
    result[group][key] = {
      kind: group === "v2" ? "mainnet-source-on-mock-Hoodi" : "mock",
      creationKind: "safe-create2",
      address: deployment.expectedAddress,
      runtimeCodeHash: HOODI_V2_RUNTIME_HASHES[deployment.label],
      evidence: receipt,
    };
  }
  result.dependencies.cowRelayer = {
    kind: "mock", creationKind: "internal-create",
    address: ethers.getAddress(relayer.address), runtimeCodeHash: relayer.runtimeCodeHash,
    evidence: receipts[4],
  };
  result.transactions = [
    ...previous.transactions,
    ...receipts.map((receipt, index) => ({ label: `v2.${plan.batches[index].name}`, ...receipt })),
  ];
  result.checkpoint = { blockNumber: receipts[5].blockNumber, blockHash: receipts[5].blockHash };
  result.reconciliation = {
    ...previous.reconciliation,
    liveSupporterClaims: 0, depositId: 0,
    principalValueWei: "2000000000000000000000", pendingBoldConversionWei: "0",
    v2PendingEthWei: ["0", "0", "0"], v2PendingBoldWei: "0", v2PendingProtocolBoldWei: "0",
    v2ActiveCowOrders: 0, v2CustodyWei: "0", safeNonce: 13,
    sourceCommitForOnchainCode: previous.source.contractsCommit,
  };
  return result;
}

export async function buildPublicHoodiV2Manifest(provider) {
  const previousBytes = fs.readFileSync(PREVIOUS_PATH);
  const previous = JSON.parse(previousBytes.toString("utf8"));
  requireSameOnchainSource(previous.source.contractsCommit);
  requireHoodiChain(await provider.send("eth_chainId", []));
  const plan = await buildHoodiV2StagePlan(previous);
  const receipts = [];
  for (const [index, hash] of TX_HASHES.entries()) {
    await verifyHoodiV2Batch(provider, hash, index);
    const receipt = await provider.getTransactionReceipt(hash);
    receipts.push({ transactionHash: hash, blockNumber: receipt.blockNumber, blockHash: receipt.blockHash });
  }
  requireReceiptSequence(receipts);
  if (receipts[0].blockNumber <= previous.checkpoint.blockNumber) throw new Error("V2 deployed before V1 baseline");
  const settlement = new ethers.Contract(plan.addresses.cowSettlement, ["function vaultRelayer() view returns(address)"], provider);
  const module = new ethers.Contract(plan.addresses.cowModule, [
    "function relayer() view returns(address)", "function enabled() view returns(bool)",
    "function activeCount() view returns(uint256)", "function nextOrderId() view returns(uint256)",
  ], provider);
  const relayerAddress = await settlement.vaultRelayer();
  if ((await module.relayer()) !== relayerAddress || (await module.enabled()) || (await module.activeCount()) !== 0n || (await module.nextOrderId()) !== 1n) {
    throw new Error("mock CoW relayer or disabled order state mismatch");
  }
  const relayerCode = await provider.getCode(relayerAddress, receipts[4].blockNumber);
  if (relayerCode === "0x") throw new Error("missing mock CoW relayer code");
  const relayer = { address: relayerAddress, runtimeCodeHash: ethers.keccak256(relayerCode) };
  const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, ["function nonce() view returns(uint256)"], provider);
  const pool = new ethers.Contract(previous.v1.pool.address, ["function yieldManager() view returns(address)"], provider);
  const old = new ethers.Contract(previous.v1.manager.address, [
    "function depositId() view returns(uint256)", "function principalValue() view returns(uint256)",
    "function pendingBoldConversion() view returns(uint256)", "function activeRouterUid() view returns(bytes32)",
  ], provider);
  const manager = new ethers.Contract(plan.addresses.manager, [
    "function intakeEnabled() view returns(bool)", "function executionEnabled() view returns(bool)",
    "function pendingEth(uint256) view returns(uint256)", "function pendingBold() view returns(uint256)",
    "function pendingProtocolBold() view returns(uint256)",
  ], provider);
  const tokenAbi = ["function balanceOf(address) view returns(uint256)"];
  const reth = new ethers.Contract(previous.dependencies.reth.address, tokenAbi, provider);
  const ysy = new ethers.Contract(plan.addresses.ysyBold, tokenAbi, provider);
  const executor = new ethers.Contract(plan.addresses.executor, ["function enabled() view returns(bool)"], provider);
  if (
    (await safe.nonce()) !== 13n ||
    (await pool.yieldManager()) !== previous.v1.manager.address ||
    (await old.depositId()) !== 0n || (await old.principalValue()) !== 2000n * 10n ** 18n ||
    (await old.pendingBoldConversion()) !== 0n || (await old.activeRouterUid()) !== ethers.ZeroHash ||
    (await manager.intakeEnabled()) || (await manager.executionEnabled()) || (await executor.enabled()) ||
    (await manager.pendingEth(0)) !== 0n || (await manager.pendingEth(1)) !== 0n ||
    (await manager.pendingEth(2)) !== 0n || (await manager.pendingBold()) !== 0n ||
    (await manager.pendingProtocolBold()) !== 0n ||
    (await provider.getBalance(plan.addresses.manager)) !== 0n ||
    (await reth.balanceOf(plan.addresses.rethVault)) !== 0n ||
    (await ysy.balanceOf(plan.addresses.ysyBoldVault)) !== 0n
  ) throw new Error("public Hoodi V1/V2 staged accounting changed");
  for (const deployment of plan.deployments) {
    const code = await provider.getCode(deployment.expectedAddress);
    if (code === "0x" || ethers.keccak256(code) !== HOODI_V2_RUNTIME_HASHES[deployment.label]) {
      throw new Error(`latest V2 runtime mismatch: ${deployment.label}`);
    }
  }
  const result = assembleHoodiV2Manifest(previousBytes, plan, receipts, relayer);
  result.reconciliation.plannerCommit = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  result.reconciliation.safeSigner = HOODI_ADMIN;
  return result;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 3 && !(process.argv.length === 4 && process.argv[3] === "--write")) {
    throw new Error("Usage: node tools/hoodi-public-v2-manifest.mjs <ignored-local-env-file> [--write]");
  }
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const text = `${JSON.stringify(await buildPublicHoodiV2Manifest(new ethers.JsonRpcProvider(rpc)), null, 2)}\n`;
  if (process.argv[3] === "--write") {
    const destination = path.resolve(DESTINATION);
    if (fs.existsSync(destination)) throw new Error("public V2 staged manifest already exists; never overwrite evidence");
    fs.writeFileSync(destination, text, { flag: "wx" });
    console.log(destination);
  } else {
    console.log(text);
  }
}
