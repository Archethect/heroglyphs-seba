// Read-only verifier for the exact public Hoodi Stage A Safe receipt.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { HOODI_ADMIN, requireHoodiChain, SAFE_MULTISEND } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";
import { buildHoodiStageABatch } from "./hoodi-public-stage-a-plan.mjs";

const safeAbi = new ethers.Interface([
  "function nonce() view returns(uint256)",
  "function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns(bool)",
  "event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)",
  "event ExecutionFailure(bytes32 indexed txHash,uint256 payment)",
]);
const multiAbi = new ethers.Interface(["function multiSend(bytes transactions)"]);
const feedAbi = new ethers.Interface(["function setUpdatedAt(uint256)"]);
const adapterAbi = new ethers.Interface(["event PrincipalRetrieved(uint256 sharesRedeemed,uint256 ethOut)"]);

/** Decode the first feed update, then compare the complete Safe calldata to the canonical four-call batch. */
export function requireExactStageATxData(manifest, data) {
  const outer = safeAbi.decodeFunctionData("execTransaction", data);
  if (outer[0] !== SAFE_MULTISEND || outer[1] !== 0n || outer[3] !== 1n) {
    throw new Error("Stage A Safe target/value/operation mismatch");
  }
  const packed = ethers.getBytes(multiAbi.decodeFunctionData("multiSend", outer[2])[0]);
  if (packed.length < 121) throw new Error("Stage A MultiSend payload too short");
  const firstLength = ethers.toNumber(ethers.hexlify(packed.slice(53, 85)));
  if (firstLength !== 36 || packed.length < 85 + firstLength) throw new Error("Stage A first report call malformed");
  const reportTime = ethers.toNumber(feedAbi.decodeFunctionData("setUpdatedAt", ethers.hexlify(packed.slice(85, 121)))[0]);
  const batch = buildHoodiStageABatch(manifest, reportTime);
  const expected = encodeOwnerSafeExecution(batch.transaction.data, HOODI_ADMIN);
  if (data.toLowerCase() !== expected.toLowerCase()) throw new Error("Stage A full Safe calldata differs from canonical batch");
  return batch;
}

export async function verifyHoodiStageA(provider, txHash, manifest) {
  if (!ethers.isHexString(txHash, 32)) throw new Error("32-byte Hoodi transaction hash required");
  requireHoodiChain(await provider.send("eth_chainId", []));
  const [tx, receipt] = await Promise.all([provider.getTransaction(txHash), provider.getTransactionReceipt(txHash)]);
  if (!tx || !receipt || receipt.status !== 1 || tx.chainId !== 560048n ||
    tx.from !== HOODI_ADMIN || tx.to !== HOODI_REHEARSAL_SAFE || tx.value !== 0n ||
    receipt.blockNumber <= manifest.checkpoint.blockNumber) throw new Error("successful post-staging Hoodi Safe receipt required");
  const batch = requireExactStageATxData(manifest, tx.data);
  const block = await provider.getBlock(receipt.blockNumber);
  if (block?.hash !== receipt.blockHash || block.timestamp < batch.reportTime ||
    block.timestamp - batch.reportTime > 900) throw new Error("Stage A report age or block mismatch");
  const events = receipt.logs.filter((log) => log.address === HOODI_REHEARSAL_SAFE).map((log) => {
    try { return safeAbi.parseLog(log)?.name; } catch { return null; }
  });
  if (!events.includes("ExecutionSuccess") || events.includes("ExecutionFailure")) throw new Error("Stage A Safe execution failed");
  const adapterEvents = receipt.logs.filter((log) => log.address === manifest.v1.beefyAdapter.address).map((log) => {
    try { return adapterAbi.parseLog(log); } catch { return null; }
  }).filter((event) => event?.name === "PrincipalRetrieved");
  if (adapterEvents.length !== 1 || adapterEvents[0].args.ethOut <= 0n) {
    throw new Error("Stage A adapter ETH output event missing");
  }
  const at = { blockTag: receipt.blockNumber };
  const c = (address, abi) => new ethers.Contract(address, abi, provider);
  const safe = c(HOODI_REHEARSAL_SAFE, safeAbi);
  const old = c(manifest.v1.manager.address, [
    "function principalValue() view returns(uint256)", "function yieldVault() view returns(address)",
    "function depositId() view returns(uint256)", "function pendingBoldConversion() view returns(uint256)",
    "function activeRouterUid() view returns(bytes32)",
  ]);
  const adapter = c(manifest.v1.beefyAdapter.address, [
    "function principalValue() view returns(uint256)", "function principalShares() view returns(uint256)",
  ]);
  const beefy = c(manifest.dependencies.beefyVault.address, ["function balanceOf(address) view returns(uint256)"]);
  const pool = c(manifest.v1.pool.address, ["function yieldManager() view returns(address)"]);
  const manager = c(manifest.v2.manager.address, [
    "function intakeEnabled() view returns(bool)", "function executionEnabled() view returns(bool)",
    "function legacyImported() view returns(bool)",
  ]);
  const parkedEth = await provider.getBalance(manifest.v1.manager.address, receipt.blockNumber);
  const beforeEth = await provider.getBalance(manifest.v1.manager.address, receipt.blockNumber - 1);
  const stopperCode = await provider.getCode(batch.stopper, receipt.blockNumber);
  if ((await safe.nonce(at)) !== 14n || (await old.principalValue(at)) !== 0n ||
    (await old.yieldVault(at)) !== batch.stopper || (await old.depositId(at)) !== 0n ||
    (await old.pendingBoldConversion(at)) !== 0n || (await old.activeRouterUid(at)) !== ethers.ZeroHash ||
    beforeEth !== 0n || parkedEth !== adapterEvents[0].args.ethOut ||
    (await adapter.principalValue(at)) !== 0n || (await adapter.principalShares(at)) !== 0n ||
    (await beefy.balanceOf(manifest.v1.beefyAdapter.address, at)) !== 0n ||
    (await pool.yieldManager(at)) !== manifest.v1.manager.address ||
    (await manager.intakeEnabled(at)) || (await manager.executionEnabled(at)) || (await manager.legacyImported(at)) ||
    stopperCode === "0x" || ethers.keccak256(stopperCode) !== batch.stopperRuntimeCodeHash) {
    throw new Error("Stage A post-receipt accounting or code mismatch");
  }
  for (const name of ["ethUsdFeed", "usdcUsdFeed"]) {
    const feed = c(manifest.dependencies[name].address, ["function updatedAt() view returns(uint256)"]);
    if ((await feed.updatedAt(at)) !== BigInt(batch.reportTime)) throw new Error("Stage A feed refresh missing");
  }
  return {
    schemaVersion: "seba-hoodi-stage-a-receipt-v1", chainId: 560048,
    transactionHash: txHash, blockNumber: receipt.blockNumber, blockHash: receipt.blockHash,
    safeNonce: "14", stopper: batch.stopper, reportTime: batch.reportTime,
    adapterSharesRedeemed: adapterEvents[0].args.sharesRedeemed.toString(),
    adapterEthOutWei: adapterEvents[0].args.ethOut.toString(), parkedEthWei: parkedEth.toString(),
    poolStillOnV1: true, v2StillDisabled: true,
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 4) throw new Error("Usage: node tools/hoodi-public-stage-a-verify.mjs <ignored-local-env-file> <tx-hash>");
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const manifest = JSON.parse(fs.readFileSync("docs/HOODI_V2_STAGED_MANIFEST.json", "utf8"));
  console.log(JSON.stringify(await verifyHoodiStageA(new ethers.JsonRpcProvider(rpc), process.argv[3], manifest), null, 2));
}
