// Read-only Hoodi Stage A planner. Produces one owner-executed Safe batch; never signs or sends.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { currentSource } from "./hoodi-source-gate.mjs";
import { HOODI_ADMIN, requireHoodiChain, requireExpectedCodeHash, SAFE_MULTISEND, SAFE_SINGLETON } from "./hoodi-public-safe-plan.mjs";
import { CREATE_CALL, CREATE_CALL_CODE_HASH, create2Deployment, multiSendData } from "./hoodi-safe-createcall.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";

const MANIFEST = "docs/HOODI_V2_STAGED_MANIFEST.json";
const GUARD_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8";
const MODULE_SENTINEL = "0x0000000000000000000000000000000000000001";
const safeAbi = [
  "function nonce() view returns(uint256)", "function getOwners() view returns(address[])",
  "function getThreshold() view returns(uint256)",
  "function getModulesPaginated(address,uint256) view returns(address[],address)",
  "function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns(bool)",
];
const oldAbi = [
  "function yieldVault() view returns(address)", "function principalValue() view returns(uint256)",
  "function depositId() view returns(uint256)", "function pendingBoldConversion() view returns(uint256)",
  "function activeRouterUid() view returns(bytes32)", "function ADMIN_ROLE() view returns(bytes32)",
  "function hasRole(bytes32,address) view returns(bool)", "function setYieldVault(address)",
];
const feedAbi = [
  "function answer() view returns(int256)", "function updatedAt() view returns(uint256)",
  "function updater() view returns(address)", "function setUpdatedAt(uint256)",
];

function requireManifest(manifest) {
  if (manifest?.schemaVersion !== "seba-hoodi-rehearsal-v1" || manifest.network !== "hoodi" ||
    manifest.chainId !== 560048 || manifest.testOnly !== true || manifest.mode !== "isolated-mock-backed" ||
    manifest.phase !== "v2-staged") throw new Error("Hoodi V2 staged manifest required");
  if (manifest.safe?.address !== HOODI_REHEARSAL_SAFE || manifest.safe?.owners?.[0] !== HOODI_ADMIN ||
    manifest.safe.threshold !== 1) throw new Error("Hoodi Safe evidence mismatch");
}

/** Four calls are atomic: both synthetic reports, CREATE2 stopper, then old adapter exit. */
export function buildHoodiStageABatch(manifest, reportTime) {
  requireManifest(manifest);
  if (!Number.isSafeInteger(reportTime) || reportTime <= 0) throw new Error("valid Hoodi block timestamp required");
  const artifact = JSON.parse(fs.readFileSync(path.resolve("out/LegacyIntakeStopper.sol/LegacyIntakeStopper.json"), "utf8"));
  const bytecode = artifact.bytecode?.object;
  if (!ethers.isHexString(bytecode) || bytecode === "0x") throw new Error("missing compiled intake stopper");
  const salt = ethers.id(`seba:hoodi:560048:stage-a:${HOODI_REHEARSAL_SAFE}:intake-stopper`);
  const deployment = create2Deployment(bytecode, salt);
  const feed = new ethers.Interface(feedAbi);
  const old = new ethers.Interface(oldAbi);
  const calls = [
    { label: "refresh-eth-usd", to: manifest.dependencies.ethUsdFeed.address,
      data: feed.encodeFunctionData("setUpdatedAt", [reportTime]) },
    { label: "refresh-usdc-usd", to: manifest.dependencies.usdcUsdFeed.address,
      data: feed.encodeFunctionData("setUpdatedAt", [reportTime]) },
    { label: "deploy-intake-stopper", to: deployment.to, data: deployment.data,
      expectedAddress: deployment.expectedAddress, creationCodeHash: ethers.keccak256(bytecode) },
    { label: "exit-v1-and-stop-intake", to: manifest.v1.manager.address,
      data: old.encodeFunctionData("setYieldVault", [deployment.expectedAddress]) },
  ];
  return {
    stopper: deployment.expectedAddress,
    stopperRuntimeCodeHash: ethers.keccak256(artifact.deployedBytecode.object),
    reportTime, salt, calls,
    transaction: { to: SAFE_MULTISEND, valueWei: "0", operation: 1, data: multiSendData(calls) },
  };
}

/** Reject changed source obligations or a partially started V2 before a public exit. */
export function requireStageAState(manifest, state) {
  requireManifest(manifest);
  if (state.safeNonce !== 13n || state.poolManager !== manifest.v1.manager.address ||
    state.oldVault !== manifest.v1.beefyAdapter.address || state.depositId !== 0n ||
    state.pendingBold !== 0n || state.activeRouterUid !== ethers.ZeroHash || state.oldIdleEth !== 0n ||
    state.oldPrincipal !== BigInt(manifest.reconciliation.principalValueWei) || state.oldPrincipal <= 0n ||
    state.adapterPrincipal !== state.oldPrincipal || state.adapterShares <= 0n ||
    state.adapterShares !== state.beefyShares || state.v2IntakeEnabled || state.v2ExecutionEnabled ||
    state.legacyImported || state.cowEnabled || state.cowActiveCount !== 0n ||
    state.v2PendingEth.length !== 3 || state.v2PendingEth.some((value) => value !== 0n)) {
    throw new Error("Stage A state changed; abort and reconcile");
  }
}

function requireOnchainSourceUnchanged(manifest) {
  execFileSync("git", ["diff", "--quiet", manifest.reconciliation.sourceCommitForOnchainCode, "HEAD", "--", "src", "script", "foundry.toml"], { stdio: "ignore" });
  const dirty = execFileSync("git", ["status", "--porcelain", "--untracked-files=all", "--", "src", "script", "foundry.toml"], { encoding: "utf8" });
  if (dirty.trim()) throw new Error("onchain source changed since staged Hoodi deployment");
}

export async function planHoodiStageA(provider, manifest, source = currentSource()) {
  requireManifest(manifest);
  requireOnchainSourceUnchanged(manifest);
  requireHoodiChain(await provider.send("eth_chainId", []));
  const head = await provider.getBlock("latest");
  if (!head?.hash || (await provider.getBlock(manifest.checkpoint.blockNumber))?.hash !== manifest.checkpoint.blockHash) {
    throw new Error("Hoodi head or staged checkpoint mismatch");
  }
  const at = { blockTag: head.number };
  for (const entry of [manifest.safe, ...Object.values(manifest.v1), ...Object.values(manifest.v2), ...Object.values(manifest.dependencies)]) {
    if (!entry?.address || !entry.runtimeCodeHash) continue;
    const code = await provider.getCode(entry.address, head.number);
    if (code === "0x" || ethers.keccak256(code) !== entry.runtimeCodeHash) throw new Error(`Hoodi runtime drift: ${entry.address}`);
  }
  requireExpectedCodeHash(SAFE_SINGLETON, await provider.getCode(SAFE_SINGLETON, head.number));
  requireExpectedCodeHash(SAFE_MULTISEND, await provider.getCode(SAFE_MULTISEND, head.number));
  const createCallCode = await provider.getCode(CREATE_CALL, head.number);
  if (createCallCode === "0x" || ethers.keccak256(createCallCode) !== CREATE_CALL_CODE_HASH) throw new Error("CreateCall runtime drift");
  const singleton = await provider.getStorage(HOODI_REHEARSAL_SAFE, 0, head.number);
  if (ethers.getAddress(`0x${singleton.slice(-40)}`) !== SAFE_SINGLETON) throw new Error("Safe singleton changed");
  const safe = new ethers.Contract(HOODI_REHEARSAL_SAFE, safeAbi, provider);
  const [safeNonce, owners, threshold, modules, guard] = await Promise.all([
    safe.nonce(at), safe.getOwners(at), safe.getThreshold(at),
    safe.getModulesPaginated(MODULE_SENTINEL, 10, at), provider.getStorage(HOODI_REHEARSAL_SAFE, GUARD_SLOT, head.number),
  ]);
  if (owners.length !== 1 || owners[0] !== HOODI_ADMIN || threshold !== 1n ||
    modules[0].length !== 0 || modules[1] !== MODULE_SENTINEL || BigInt(guard) !== 0n) {
    throw new Error("Safe owner, threshold, modules, or guard changed");
  }
  const c = (address, abi) => new ethers.Contract(address, abi, provider);
  const old = c(manifest.v1.manager.address, oldAbi);
  const adapter = c(manifest.v1.beefyAdapter.address, [
    "function principalValue() view returns(uint256)", "function principalShares() view returns(uint256)",
    "function YIELDMANAGER_ROLE() view returns(bytes32)", "function hasRole(bytes32,address) view returns(bool)",
  ]);
  const beefy = c(manifest.dependencies.beefyVault.address, ["function balanceOf(address) view returns(uint256)"]);
  const pool = c(manifest.v1.pool.address, ["function yieldManager() view returns(address)"]);
  const manager = c(manifest.v2.manager.address, [
    "function intakeEnabled() view returns(bool)", "function executionEnabled() view returns(bool)",
    "function legacyImported() view returns(bool)", "function pendingEth(uint256) view returns(uint256)",
  ]);
  const cow = c(manifest.v2.cowModule.address, ["function enabled() view returns(bool)", "function activeCount() view returns(uint256)"]);
  const state = {
    safeNonce, poolManager: await pool.yieldManager(at), oldVault: await old.yieldVault(at),
    depositId: await old.depositId(at), pendingBold: await old.pendingBoldConversion(at),
    activeRouterUid: await old.activeRouterUid(at), oldIdleEth: await provider.getBalance(manifest.v1.manager.address, head.number),
    oldPrincipal: await old.principalValue(at), adapterPrincipal: await adapter.principalValue(at),
    adapterShares: await adapter.principalShares(at),
    beefyShares: await beefy.balanceOf(manifest.v1.beefyAdapter.address, at),
    v2IntakeEnabled: await manager.intakeEnabled(at), v2ExecutionEnabled: await manager.executionEnabled(at),
    legacyImported: await manager.legacyImported(at), cowEnabled: await cow.enabled(at),
    cowActiveCount: await cow.activeCount(at),
    v2PendingEth: await Promise.all([0, 1, 2].map((i) => manager.pendingEth(i, at))),
  };
  requireStageAState(manifest, state);
  if (!(await old.hasRole(await old.ADMIN_ROLE(at), HOODI_REHEARSAL_SAFE, at)) ||
    !(await adapter.hasRole(await adapter.YIELDMANAGER_ROLE(at), manifest.v1.manager.address, at))) {
    throw new Error("Stage A Safe/manager authorization changed");
  }
  const reports = {};
  for (const [name, answer] of [["ethUsdFeed", 2000n * 10n ** 8n], ["usdcUsdFeed", 10n ** 8n]]) {
    const feed = c(manifest.dependencies[name].address, feedAbi);
    const [actual, updater, updatedAt] = await Promise.all([feed.answer(at), feed.updater(at), feed.updatedAt(at)]);
    if (actual !== answer || updater !== HOODI_REHEARSAL_SAFE || updatedAt > BigInt(head.timestamp)) {
      throw new Error(`Stage A synthetic ${name} identity or report changed`);
    }
    reports[name] = { answer: actual.toString(), previousUpdatedAt: updatedAt.toString(),
      previousAgeSeconds: (BigInt(head.timestamp) - updatedAt).toString() };
  }
  const batch = buildHoodiStageABatch(manifest, head.timestamp);
  if (await provider.getCode(batch.stopper, head.number) !== "0x") throw new Error("Stage A stopper address already occupied");
  const data = encodeOwnerSafeExecution(batch.transaction.data, HOODI_ADMIN);
  const request = { from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, value: 0n, data };
  const result = await provider.call({ ...request, blockTag: head.number });
  if (!new ethers.Interface(safeAbi).decodeFunctionResult("execTransaction", result)[0]) {
    throw new Error("Stage A Safe eth_call returned false");
  }
  const estimatedGas = await provider.estimateGas(request);
  const gasLimit = (estimatedGas * 125n) / 100n;
  if (gasLimit > head.gasLimit) throw new Error("Stage A exceeds Hoodi block gas limit");
  const fees = await provider.getFeeData();
  const maxFeePerGas = fees.maxFeePerGas ?? fees.gasPrice;
  if (!maxFeePerGas) throw new Error("Hoodi fee unavailable");
  const walletBalance = await provider.getBalance(HOODI_ADMIN, head.number);
  if (walletBalance < gasLimit * maxFeePerGas) throw new Error("Hoodi owner lacks maximum gas cost");
  const walletNonce = await provider.getTransactionCount(HOODI_ADMIN, "latest");
  if (walletNonce !== await provider.getTransactionCount(HOODI_ADMIN, "pending")) {
    throw new Error("Hoodi owner has pending transactions");
  }
  return {
    schemaVersion: "seba-hoodi-stage-a-plan-v1", network: "hoodi", chainId: 560048,
    readOnly: true, broadcast: false, executionReady: !source.worktreeDirty,
    source, observedAt: { blockNumber: head.number, blockHash: head.hash, timestamp: head.timestamp },
    safe: { address: HOODI_REHEARSAL_SAFE, nonce: safeNonce.toString(), owner: HOODI_ADMIN, threshold: 1 },
    old: { manager: manifest.v1.manager.address, adapter: manifest.v1.beefyAdapter.address,
      principalValue: state.oldPrincipal.toString(), adapterShares: state.adapterShares.toString(),
      beefyShares: state.beefyShares.toString(), oldIdleEthWei: "0", liveSupporterClaims: 0 },
    syntheticReports: reports, stopper: { address: batch.stopper, runtimeCodeHash: batch.stopperRuntimeCodeHash,
      creationCodeHash: batch.calls[2].creationCodeHash },
    batch: { name: "refresh-oracles-deploy-stopper-exit-v1", reportTime: batch.reportTime,
      calls: batch.calls.map(({ label, to, expectedAddress }) => ({ label, to, expectedAddress: expectedAddress ?? null })) },
    signer: { address: HOODI_ADMIN, method: "owner browser wallet through Safe", walletNonce },
    transaction: { from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, valueWei: "0", data,
      dataBytes: ethers.dataLength(data), dataHash: ethers.keccak256(data),
      estimatedGas: estimatedGas.toString(), gasLimit: gasLimit.toString(),
      maxFeePerGasWei: maxFeePerGas.toString(), maximumGasCostWei: (gasLimit * maxFeePerGas).toString(),
      walletBalanceWei: walletBalance.toString() },
    abortIf: [
      "Wallet chain, signer, Safe nonce/policy, full calldata hash, or any code hash differs.",
      "Execution is more than 15 minutes after this block timestamp; regenerate the oracle refresh and batch.",
      "Any V1 supporter ID, pending conversion/order, principal/share/ETH drift, or V2 enablement appears.",
      "Hoodi backend financial work starts, either Hoodi graph is unhealthy, or exact-block graph/RPC parity fails.",
      "Current-block Safe eth_call or gas simulation fails; never bypass a failed exit or stale oracle check.",
      "If Stage A succeeds, do not estimate or execute Stage B until parked ETH and residual balances are measured.",
    ],
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 3) throw new Error("Usage: node tools/hoodi-public-stage-a-plan.mjs <ignored-local-env-file>");
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const manifest = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
  console.log(JSON.stringify(await planHoodiStageA(new ethers.JsonRpcProvider(rpc), manifest), null, 2));
}
