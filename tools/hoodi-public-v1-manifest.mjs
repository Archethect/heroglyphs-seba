// Build receipt-backed, non-secret public Hoodi V1 evidence. Read-only RPC; no signer or send path.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { execFileSync } from "node:child_process";
import { ethers } from "ethers";
import {
  HOODI_ADMIN,
  SAFE_SINGLETON,
  SAFE_FACTORY,
  SAFE_MULTISEND,
  requireHoodiChain,
} from "./hoodi-public-safe-plan.mjs";
import { CREATE_CALL } from "./hoodi-safe-createcall.mjs";
import { buildHoodiV1Plan } from "./hoodi-public-v1-plan.mjs";
import { HOODI_V1_RUNTIME_HASHES } from "./hoodi-public-v1-runtime.mjs";
import { HOODI_REHEARSAL_SAFE } from "./hoodi-public-v1-next.mjs";
import { verifyHoodiV1Batch } from "./hoodi-public-v1-verify.mjs";

const DEPLOYED_SOURCE_COMMIT = "e40e46cca58f5a63195848ae233a6e1f5deb2362";
const SAFE_TX = "0x3ac6307b93523487a9d39c079801994e6363d445f13554483f6540279d31fdf6";
const BATCH_TXS = [
  "0x7f33295d98ed95360b3c3d9bba3d2178256f93405b3a8221793f877c3331e74b",
  "0x71edd084d417ea2daa197feca46683638078b0dc53df63429613c188a80dd9c7",
  "0x37c44885d60d59d4bc8a56c6badf351f2507fafb3e0a01236d94ed8a332e7a8f",
  "0x772a100ac67a841fb6ea36adbe46a4cce5daebed9fe12d42797aa68afb22dc43",
  "0x1bdce5aaf2d0a2a483306096ceef4d7dd3fcf93addd5152486437c199fe1cb94",
];
const REAL = {
  safeSingleton: SAFE_SINGLETON,
  safeFactory: SAFE_FACTORY,
  safeMultiSend: SAFE_MULTISEND,
  safeCreateCall: CREATE_CALL,
  reth: "0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1",
  rocketStorage: "0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1",
};
const LABEL_TO_KEY = {
  MockWETH: ["dependencies", "weth"],
  MockUSDC: ["dependencies", "usdc"],
  MockBold: ["dependencies", "bold"],
  HoodiSBoldMock: ["v1", "sBold"],
  ethUsdFeed: ["dependencies", "ethUsdFeed"],
  usdcUsdFeed: ["dependencies", "usdcUsdFeed"],
  HoodiUniswapMock: ["dependencies", "uniswap"],
  HoodiCurveMock: ["dependencies", "curve"],
  HoodiBeefyMock: ["dependencies", "beefyVault"],
  HoodiBeefyHarvesterMock: ["dependencies", "beefyHarvester"],
  HoodiEthFlowMock: ["dependencies", "ethFlow"],
  EthToBoldRouter: ["v1", "router"],
  PYBSeba: ["v1", "pybSeba"],
  SebaPool: ["v1", "pool"],
  EUSDUSDCBeefyYieldVault: ["v1", "beefyAdapter"],
  YieldManager: ["v1", "manager"],
  RocketPoolBackPay: ["v1", "rocketPoolBackPay"],
};

function requireDeployedSourceUnchanged() {
  execFileSync("git", ["diff", "--quiet", DEPLOYED_SOURCE_COMMIT, "--", "src", "script", "foundry.toml"], {
    stdio: "ignore",
  });
  const changed = execFileSync(
    "git",
    ["status", "--porcelain", "--untracked-files=all", "--", "src", "script", "foundry.toml"],
    {
      encoding: "utf8",
    },
  );
  if (changed.trim()) throw new Error("onchain source changed since the deployed commit");
}

function evidence(receipt) {
  return {
    transactionHash: receipt.hash,
    blockNumber: receipt.blockNumber,
    blockHash: receipt.blockHash,
  };
}

export async function buildPublicHoodiV1Manifest(provider) {
  requireDeployedSourceUnchanged();
  requireHoodiChain(await provider.send("eth_chainId", []));
  const safeReceipt = await provider.getTransactionReceipt(SAFE_TX);
  if (!safeReceipt || safeReceipt.status !== 1) throw new Error("Hoodi Safe bootstrap receipt missing");
  const batchReceipts = [];
  for (const [index, hash] of BATCH_TXS.entries()) {
    await verifyHoodiV1Batch(provider, hash, index);
    batchReceipts.push(await provider.getTransactionReceipt(hash));
  }
  const plan = await buildHoodiV1Plan(HOODI_REHEARSAL_SAFE, HOODI_ADMIN);
  const checkpointReceipt = batchReceipts[4];
  const checkpoint = { blockNumber: checkpointReceipt.blockNumber, blockHash: checkpointReceipt.blockHash };
  const safeCode = await provider.getCode(HOODI_REHEARSAL_SAFE, checkpoint.blockNumber);
  if (ethers.keccak256(safeCode) !== "0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c") {
    throw new Error("Hoodi Safe runtime code changed");
  }
  const manifest = {
    schemaVersion: "seba-hoodi-rehearsal-v1",
    network: "hoodi",
    chainId: 560048,
    testOnly: true,
    mode: "isolated-mock-backed",
    phase: "v1-ready",
    previousManifestHash: null,
    source: { contractsCommit: DEPLOYED_SOURCE_COMMIT },
    anchor: { blockNumber: safeReceipt.blockNumber, blockHash: safeReceipt.blockHash },
    safe: {
      kind: "real-safe-proxy",
      address: HOODI_REHEARSAL_SAFE,
      runtimeCodeHash: ethers.keccak256(safeCode),
      evidence: evidence(safeReceipt),
      owners: [HOODI_ADMIN],
      threshold: 1,
      version: "1.4.1",
    },
    dependencies: {},
    v1: {},
    v2: {},
    cutover: {},
    reconciliation: {
      v1TestAutomator: HOODI_ADMIN,
      liveSupporterClaims: 0,
      depositId: 0,
      principalValueWei: "0",
      pendingBoldConversionWei: "0",
    },
    transactions: [
      { label: "safe.bootstrap", ...evidence(safeReceipt) },
      ...batchReceipts.map((receipt, index) => ({ label: `v1.${plan.batches[index].name}`, ...evidence(receipt) })),
    ],
    checkpoint,
  };
  for (const [key, address] of Object.entries(REAL)) {
    const code = await provider.getCode(address, checkpoint.blockNumber);
    if (code === "0x") throw new Error(`missing real Hoodi dependency: ${key}`);
    manifest.dependencies[key] = {
      kind: "real",
      address,
      runtimeCodeHash: ethers.keccak256(code),
      verifiedAt: checkpoint,
    };
  }
  for (const [index, deployment] of plan.deployments.entries()) {
    const [group, key] = LABEL_TO_KEY[deployment.label] ?? [];
    if (!group || !key) throw new Error(`missing manifest mapping: ${deployment.label}`);
    const code = await provider.getCode(deployment.expectedAddress, checkpoint.blockNumber);
    const runtimeCodeHash = ethers.keccak256(code);
    if (code === "0x" || runtimeCodeHash !== HOODI_V1_RUNTIME_HASHES[deployment.label]) {
      throw new Error(`deployed code hash changed: ${deployment.label}`);
    }
    const receipt = batchReceipts[index < 6 ? 0 : index < 11 ? 1 : index < 14 ? 2 : 3];
    manifest[group][key] = {
      kind: group === "v1" && key !== "sBold" ? "mainnet-source-on-mock-Hoodi" : "mock",
      creationKind: "safe-create2",
      address: deployment.expectedAddress,
      runtimeCodeHash,
      evidence: evidence(receipt),
    };
  }
  return manifest;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 3 && !(process.argv.length === 4 && process.argv[3] === "--write")) {
    throw new Error("Usage: node tools/hoodi-public-v1-manifest.mjs <ignored-local-env-file> [--write]");
  }
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const text = `${JSON.stringify(await buildPublicHoodiV1Manifest(new ethers.JsonRpcProvider(rpc)), null, 2)}\n`;
  if (process.argv[3] === "--write") {
    const destination = path.resolve("docs/HOODI_V1_PUBLIC_MANIFEST.json");
    if (fs.existsSync(destination))
      throw new Error("public Hoodi V1 manifest already exists; never overwrite evidence");
    fs.writeFileSync(destination, text, { flag: "wx" });
    console.log(destination);
  } else {
    console.log(text);
  }
}
