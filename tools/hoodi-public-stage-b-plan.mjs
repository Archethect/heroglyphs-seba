// Read-only, fail-closed plan for the isolated public Hoodi Stage B handoff deployment.
// Never signs or sends. The final seven-call cutover needs a fresh preflight AFTER deployment.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { currentSource } from "./hoodi-source-gate.mjs";
import { HOODI_ADMIN, requireHoodiChain, SAFE_MULTISEND, SAFE_SINGLETON, requireExpectedCodeHash } from "./hoodi-public-safe-plan.mjs";
import { CREATE_CALL, CREATE_CALL_CODE_HASH, create2Deployment, multiSendData } from "./hoodi-safe-createcall.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";
import { verifyHoodiStageA } from "./hoodi-public-stage-a-verify.mjs";

const APPROVAL_PATH = "docs/HOODI_PHASE5_STAGE_B_MANIFEST.json";
const STAGED_PATH = "docs/HOODI_V2_STAGED_MANIFEST.json";
export const APPROVED_STAGE_B_MANIFEST_HASH = "0x178ad989af6fbe81a3651e7f84618c538ff992d3a2a4927a0ec84d11b6237c9d";
const SENTINEL = "0x0000000000000000000000000000000000000001";
const GUARD_SLOT = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8";
const safeAbi = [
  "function nonce() view returns(uint256)", "function getOwners() view returns(address[])",
  "function getThreshold() view returns(uint256)",
  "function getModulesPaginated(address,uint256) view returns(address[],address)",
  "function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns(bool)",
];

function artifact(name, file = name) {
  const a = JSON.parse(fs.readFileSync(path.resolve(`out/${file}.sol/${name}.json`), "utf8"));
  if (!ethers.isHexString(a.bytecode?.object) || a.bytecode.object === "0x") throw new Error(`${name} artifact missing`);
  return a;
}

function sameAddress(a, b) {
  return ethers.isAddress(a) && ethers.isAddress(b) && ethers.getAddress(a) === ethers.getAddress(b);
}

export function validateStageBManifest(a, m) {
  if (a?.schemaVersion !== "seba-hoodi-stage-b-approval-v1" || a.network !== "hoodi" ||
    a.chainId !== 560048 || a.testOnly !== true || a.mode !== "isolated-mock-backed" ||
    m?.phase !== "v2-staged" || m?.chainId !== 560048 || m?.testOnly !== true ||
    a.sourceCommitForOnchainCode !== m.reconciliation?.sourceCommitForOnchainCode ||
    !ethers.isHexString(a.stageA?.transactionHash, 32) || !ethers.isHexString(a.stageA?.blockHash, 32) ||
    !ethers.isHexString(a.snapshot?.blockHash, 32) ||
    a.stageA.blockNumber <= m.checkpoint.blockNumber || a.snapshot.blockNumber < a.stageA.blockNumber ||
    a.stageA.parkedEthWei !== "1000000000000000000" ||
    !sameAddress(a.stageA.stopper, "0x8388e0c50197362FD46159Ac48cFC7c962E3937a") ||
    !sameAddress(a.safe?.address, HOODI_REHEARSAL_SAFE) || a.safe?.owners?.length !== 1 ||
    !sameAddress(a.safe.owners[0], HOODI_ADMIN) || a.safe.threshold !== 1 ||
    a.safe.expectedNonceBeforeHandoffDeployment !== 14 ||
    !sameAddress(a.legacy?.manager, m.v1.manager.address) ||
    !sameAddress(a.legacy?.pool, m.v1.pool.address) ||
    !sameAddress(a.legacy?.adapter, m.v1.beefyAdapter.address) ||
    !sameAddress(a.legacy?.router, m.v1.router.address) ||
    !sameAddress(a.destination?.managerProxy, m.v2.manager.address) ||
    a.destination.rethBps !== 5000 || a.destination.ysyBoldBps !== 5000 ||
    ["oldPrincipal", "oldDepositId", "adapterPrincipal", "adapterShares", "actualBeefyShares"]
      .some((key) => a.legacy[key] !== "0") ||
    ["maximumRouterEth", "maximumOldBold", "maximumOldSBold", "maximumRouterBold"]
      .some((key) => a.approvedUnmigratedSurplusCaps?.[key] !== "0")) {
    throw new Error("Stage B Hoodi approval manifest mismatch");
  }
}

/** Compare every safety-sensitive observation against the Safe-reviewed snapshot; all surplus caps are zero. */
export function requireStageBState(a, s, m) {
  const expected = {
    safeNonce: BigInt(a.safe.expectedNonceBeforeHandoffDeployment), owners: a.safe.owners,
    threshold: BigInt(a.safe.threshold), modules: [], moduleNext: SENTINEL, guard: 0n,
    poolManager: a.legacy.manager, oldVault: a.stageA.stopper,
    oldPrincipal: BigInt(a.legacy.oldPrincipal), oldDepositId: BigInt(a.legacy.oldDepositId),
    oldIdleEth: BigInt(a.stageA.parkedEthWei), pendingBoldConversion: 0n,
    activeRouterUid: ethers.ZeroHash, routerOrderActive: false,
    adapterPrincipal: BigInt(a.legacy.adapterPrincipal), adapterShares: BigInt(a.legacy.adapterShares),
    actualBeefyShares: BigInt(a.legacy.actualBeefyShares),
    routerEth: 0n, oldBold: 0n, oldSBold: 0n, routerBold: 0n,
    v2Intake: false, v2Execution: false, v2Imported: false, v2Recovered: false,
    v2Treasury: a.safe.address, v2Pool: a.legacy.pool,
    v2Bold: m.dependencies.bold.address, v2SBold: m.v1.sBold.address, v2PybSeba: m.v1.pybSeba.address,
    v2CowModule: m.v2.cowModule.address, v2Vaults: [m.v2.rethVault.address, m.v2.ysyBoldVault.address],
    vaultManagers: [a.destination.managerProxy, a.destination.managerProxy],
    v2RethBps: BigInt(a.destination.rethBps), v2YsyBps: BigInt(a.destination.ysyBoldBps),
    v2PendingEth: [0n, 0n, 0n], v2PendingBold: 0n, v2PendingSBold: 0n, v2PendingProtocolBold: 0n,
    cowActive: 0n, cowEnabled: false, vaultProtocolBasis: [0n, 0n], vaultProtocolTokens: [0n, 0n],
    vaultRecovery: [0n, 0n], harvestInventory: [0n, 0n, 0n, 0n],
    legacyHandoff: ethers.ZeroAddress, legacyExpectedEth: 0n, legacyManifest: ethers.ZeroHash,
    destinationEth: 0n,
  };
  for (const [key, value] of Object.entries(expected)) {
    const actual = s[key];
    if (actual === undefined || JSON.stringify(actual, (_, v) => typeof v === "bigint" ? v.toString() : v) !==
      JSON.stringify(value, (_, v) => typeof v === "bigint" ? v.toString() : v)) {
      throw new Error(`Stage B ${key} drift`);
    }
  }
}

export function buildHandoffConfiguration(a, expiry, manifestHash) {
  if (!Number.isSafeInteger(expiry) || expiry <= 0 || !ethers.isHexString(manifestHash, 32) || manifestHash === ethers.ZeroHash)
    throw new Error("Stage B expiry or manifest hash invalid");
  return {
    oldManager: a.legacy.manager, destination: a.destination.managerProxy, treasury: a.safe.address,
    pool: a.legacy.pool, oldVault: a.legacy.adapter, stagingVault: a.stageA.stopper,
    oldRouter: a.legacy.router, expectedEth: BigInt(a.stageA.parkedEthWei), expiry: BigInt(expiry),
    oldPrincipal: BigInt(a.legacy.oldPrincipal), oldDepositId: BigInt(a.legacy.oldDepositId),
    adapterPrincipal: BigInt(a.legacy.adapterPrincipal), adapterShares: BigInt(a.legacy.adapterShares),
    actualBeefyShares: BigInt(a.legacy.actualBeefyShares), oldIdleEth: BigInt(a.stageA.parkedEthWei),
    safeOwnersHash: ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address[]"], [a.safe.owners])),
    safeThreshold: BigInt(a.safe.threshold), rethBps: a.destination.rethBps, manifest: manifestHash,
    maximumRouterEth: BigInt(a.approvedUnmigratedSurplusCaps.maximumRouterEth),
    maximumOldBold: BigInt(a.approvedUnmigratedSurplusCaps.maximumOldBold),
    maximumOldSBold: BigInt(a.approvedUnmigratedSurplusCaps.maximumOldSBold),
    maximumRouterBold: BigInt(a.approvedUnmigratedSurplusCaps.maximumRouterBold),
  };
}

export function buildStageBCalls(a, m, handoff, expiry, manifestHash) {
  validateStageBManifest(a, m);
  if (!ethers.isAddress(handoff) || handoff === ethers.ZeroAddress) throw new Error("Stage B handoff address invalid");
  const manager = new ethers.Interface(artifact("YieldManagerV2").abi);
  const old = new ethers.Interface(artifact("YieldManager").abi);
  const pool = new ethers.Interface(artifact("SebaPool").abi);
  const h = new ethers.Interface(artifact("LegacyProtocolPrincipalHandoff").abi);
  return [
    { label: "arm-exact-import", to: a.destination.managerProxy,
      data: manager.encodeFunctionData("armLegacyImport", [handoff, a.stageA.parkedEthWei, expiry, manifestHash]) },
    { label: "assert-pre-migration", to: handoff, data: h.encodeFunctionData("assertPreMigration") },
    { label: "set-v1-handoff", to: a.legacy.manager, data: old.encodeFunctionData("setYieldVault", [handoff]) },
    { label: "import-parked-eth", to: a.legacy.manager, data: old.encodeFunctionData("depositPrincipalIntoYieldVault") },
    { label: "enable-v2-intake", to: a.destination.managerProxy, data: manager.encodeFunctionData("setIntakeEnabled", [true]) },
    { label: "switch-pool-manager", to: a.legacy.pool, data: pool.encodeFunctionData("setYieldManager", [a.destination.managerProxy]) },
    { label: "assert-post-migration", to: handoff, data: h.encodeFunctionData("assertPostMigration") },
  ];
}

/** Independently reconstruct the complete authorized deployment from reviewed manifest bytes and expiry. */
export async function buildHandoffDeployment(a, expiry, manifestHash) {
  const configuration = buildHandoffConfiguration(a, expiry, manifestHash);
  const handoffArtifact = artifact("LegacyProtocolPrincipalHandoff");
  const code = (await new ethers.ContractFactory(handoffArtifact.abi, handoffArtifact.bytecode.object)
    .getDeployTransaction(configuration)).data;
  if (!code) throw new Error("Stage B handoff creation code missing");
  const salt = ethers.id(`seba:hoodi:560048:stage-b:${a.safe.address}:${manifestHash}:${expiry}`);
  const deployment = create2Deployment(code, salt);
  const data = encodeOwnerSafeExecution(multiSendData([{ to: deployment.to, data: deployment.data }]), HOODI_ADMIN);
  const configurationHash = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
    ["tuple(address oldManager,address destination,address treasury,address pool,address oldVault,address stagingVault,address oldRouter,uint256 expectedEth,uint256 expiry,uint256 oldPrincipal,uint256 oldDepositId,uint256 adapterPrincipal,uint256 adapterShares,uint256 actualBeefyShares,uint256 oldIdleEth,bytes32 safeOwnersHash,uint256 safeThreshold,uint16 rethBps,bytes32 manifest,uint256 maximumRouterEth,uint256 maximumOldBold,uint256 maximumOldSBold,uint256 maximumRouterBold)"], [configuration],
  ));
  return { configuration, code, salt, deployment, data, configurationHash };
}

export function checkSourceCommit(a) {
  execFileSync("git", ["diff", "--quiet", a.sourceCommitForOnchainCode, "HEAD", "--", "src", "script", "foundry.toml"], { stdio: "ignore" });
  const dirty = execFileSync("git", ["status", "--porcelain", "--untracked-files=all", "--", "src", "script", "foundry.toml"], { encoding: "utf8" });
  if (dirty.trim()) throw new Error("Hoodi onchain source changed since staged deployment");
}

export async function readStageBState(provider, a, m, blockTag) {
  const at = { blockTag };
  const c = (address, name, file = name) => new ethers.Contract(address, artifact(name, file).abi, provider);
  const safe = new ethers.Contract(a.safe.address, safeAbi, provider);
  const old = c(a.legacy.manager, "YieldManager");
  const adapter = c(a.legacy.adapter, "EUSDUSDCBeefyYieldVault");
  const router = c(a.legacy.router, "EthToBoldRouter");
  const pool = c(a.legacy.pool, "SebaPool");
  const v2 = c(a.destination.managerProxy, "YieldManagerV2");
  const beefy = c(m.dependencies.beefyVault.address, "HoodiBeefyMock", "HoodiExternalMocks");
  const bold = c(m.dependencies.bold.address, "MockBold");
  const sBold = c(m.v1.sBold.address, "HoodiSBoldMock", "HoodiExternalMocks");
  const cow = c(m.v2.cowModule.address, "SebaCowIntentModule");
  const vaults = [c(m.v2.rethVault.address, "RethSupporterVault"), c(m.v2.ysyBoldVault.address, "YsyBoldSupporterVault")];
  const [owners, modules, order, buckets] = await Promise.all([
    safe.getOwners(at), safe.getModulesPaginated(SENTINEL, 1, at), router.order(at),
    Promise.all(vaults.map((vault) => vault.bucket(1, at))),
  ]);
  return {
    safeNonce: await safe.nonce(at), owners, threshold: await safe.getThreshold(at),
    modules: modules[0], moduleNext: modules[1], guard: BigInt(await provider.getStorage(a.safe.address, GUARD_SLOT, blockTag)),
    poolManager: await pool.yieldManager(at), oldVault: await old.yieldVault(at),
    oldPrincipal: await old.principalValue(at), oldDepositId: await old.depositId(at),
    oldIdleEth: await provider.getBalance(a.legacy.manager, blockTag),
    pendingBoldConversion: await old.pendingBoldConversion(at), activeRouterUid: await old.activeRouterUid(at),
    routerOrderActive: order.active,
    adapterPrincipal: await adapter.principalValue(at), adapterShares: await adapter.principalShares(at),
    actualBeefyShares: await beefy.balanceOf(a.legacy.adapter, at),
    routerEth: await provider.getBalance(a.legacy.router, blockTag),
    oldBold: await bold.balanceOf(a.legacy.manager, at), oldSBold: await sBold.balanceOf(a.legacy.manager, at),
    routerBold: await bold.balanceOf(a.legacy.router, at),
    v2Intake: await v2.intakeEnabled(at), v2Execution: await v2.executionEnabled(at),
    v2Imported: await v2.legacyImported(at), v2Recovered: await v2.buffersRecovered(at),
    v2Treasury: await v2.treasury(at), v2Pool: await v2.sebaPool(at),
    v2Bold: await v2.bold(at), v2SBold: await v2.sBold(at), v2PybSeba: await v2.pybSeba(at),
    v2CowModule: await v2.cowModule(at), v2Vaults: await Promise.all([0, 1].map((leg) => v2.vaults(leg, at))),
    vaultManagers: await Promise.all(vaults.map((vault) => vault.manager(at))),
    v2RethBps: await v2.rethBps(at), v2YsyBps: await v2.ysyBoldBps(at),
    v2PendingEth: await Promise.all([0, 1, 2].map((i) => v2.pendingEth(i, at))),
    v2PendingBold: await v2.pendingBold(at), v2PendingSBold: await v2.pendingSBold(at),
    v2PendingProtocolBold: await v2.pendingProtocolBold(at),
    cowActive: await cow.activeCount(at), cowEnabled: await cow.enabled(at),
    vaultProtocolBasis: buckets.map((bucket) => bucket.basis),
    vaultProtocolTokens: buckets.map((bucket) => bucket.tokens),
    vaultRecovery: await Promise.all(vaults.map((vault) => vault.recoveryState(at))),
    harvestInventory: await Promise.all([0, 1].flatMap((leg) => [0, 1].map((bucket) => v2.harvestInventory(leg, bucket, at)))),
    legacyHandoff: await v2.legacyHandoff(at), legacyExpectedEth: await v2.legacyExpectedEth(at),
    legacyManifest: await v2.legacyManifest(at),
    destinationEth: await provider.getBalance(a.destination.managerProxy, blockTag),
  };
}

export async function checkStageBCode(provider, a, m, blockTag) {
  for (const entry of [m.safe, ...Object.values(m.v1), ...Object.values(m.v2), ...Object.values(m.dependencies)]) {
    if (!entry?.address || !entry.runtimeCodeHash) continue;
    const code = await provider.getCode(entry.address, blockTag);
    if (code === "0x" || ethers.keccak256(code) !== entry.runtimeCodeHash) throw new Error(`Stage B code drift: ${entry.address}`);
  }
  requireExpectedCodeHash(SAFE_SINGLETON, await provider.getCode(SAFE_SINGLETON, blockTag));
  requireExpectedCodeHash(SAFE_MULTISEND, await provider.getCode(SAFE_MULTISEND, blockTag));
  const createCallCode = await provider.getCode(CREATE_CALL, blockTag);
  if (createCallCode === "0x" || ethers.keccak256(createCallCode) !== CREATE_CALL_CODE_HASH)
    throw new Error("Stage B Safe CreateCall code drift");
  const stopperCode = await provider.getCode(a.stageA.stopper, blockTag);
  if (stopperCode === "0x" || ethers.keccak256(stopperCode) !== ethers.keccak256(artifact("LegacyIntakeStopper").deployedBytecode.object))
    throw new Error("Stage B intake stopper code drift");
  const singletonSlot = await provider.getStorage(a.safe.address, 0, blockTag);
  if (ethers.getAddress(`0x${singletonSlot.slice(-40)}`) !== SAFE_SINGLETON)
    throw new Error("Stage B Safe singleton drift");
}

/** Current-chain read-only preflight for the separate Safe CREATE2 handoff deployment. */
export async function planStageBHandoffDeployment(provider, a, m, approvalBytes, source = currentSource(), lifetimeSeconds = 3600) {
  validateStageBManifest(a, m);
  checkSourceCommit(a);
  if (!Number.isInteger(lifetimeSeconds) || lifetimeSeconds < 900 || lifetimeSeconds > 7200)
    throw new Error("Stage B expiry window must be 15–120 minutes");
  requireHoodiChain(await provider.send("eth_chainId", []));
  const head = await provider.getBlock("latest");
  if (!head?.hash || head.number < a.snapshot.blockNumber ||
    (await provider.getBlock(a.stageA.blockNumber))?.hash !== a.stageA.blockHash ||
    (await provider.getBlock(a.snapshot.blockNumber))?.hash !== a.snapshot.blockHash)
    throw new Error("Stage B chain anchor mismatch");
  const receipt = await verifyHoodiStageA(provider, a.stageA.transactionHash, m);
  if (receipt.blockHash !== a.stageA.blockHash || receipt.parkedEthWei !== a.stageA.parkedEthWei ||
    !sameAddress(receipt.stopper, a.stageA.stopper)) throw new Error("Stage A receipt differs from Stage B approval");
  await checkStageBCode(provider, a, m, head.number);
  const state = await readStageBState(provider, a, m, head.number);
  requireStageBState(a, state, m);
  const expiry = head.timestamp + lifetimeSeconds;
  const manifestHash = ethers.keccak256(ethers.toUtf8Bytes(approvalBytes));
  if (manifestHash !== APPROVED_STAGE_B_MANIFEST_HASH)
    throw new Error("Stage B reviewed manifest bytes changed");
  const { code, salt, deployment, data, configurationHash } =
    await buildHandoffDeployment(a, expiry, manifestHash);
  if (await provider.getCode(deployment.expectedAddress, head.number) !== "0x") throw new Error("Stage B handoff address occupied");
  const request = { from: HOODI_ADMIN, to: a.safe.address, value: 0n, data };
  const safe = new ethers.Interface(safeAbi);
  if (!safe.decodeFunctionResult("execTransaction", await provider.call({ ...request, blockTag: head.number }))[0])
    throw new Error("Stage B Safe handoff deployment simulation returned false");
  const estimatedGas = await provider.estimateGas(request);
  const gasLimit = (estimatedGas * 125n) / 100n;
  if (gasLimit >= head.gasLimit) throw new Error("Stage B handoff deployment exceeds block gas limit");
  const fees = await provider.getFeeData();
  const maxFeePerGas = fees.maxFeePerGas ?? fees.gasPrice;
  if (!maxFeePerGas || await provider.getBalance(HOODI_ADMIN, head.number) < gasLimit * maxFeePerGas)
    throw new Error("Stage B Hoodi owner cannot fund handoff deployment gas");
  if (await provider.getTransactionCount(HOODI_ADMIN, "latest") !== await provider.getTransactionCount(HOODI_ADMIN, "pending"))
    throw new Error("Stage B Hoodi owner has pending transaction");
  return {
    schemaVersion: "seba-hoodi-stage-b-handoff-deployment-plan-v1", readOnly: true, broadcast: false,
    executionReady: !source.worktreeDirty, chainId: 560048,
    observedAt: { blockNumber: head.number, blockHash: head.hash, timestamp: head.timestamp },
    approvalManifestHash: manifestHash, expiry, lifetimeSeconds,
    configurationHash,
    handoff: { expectedAddress: deployment.expectedAddress, creationCodeHash: ethers.keccak256(code), salt },
    transaction: { from: HOODI_ADMIN, to: a.safe.address, valueWei: "0", data,
      dataHash: ethers.keccak256(data), estimatedGas: estimatedGas.toString(), gasLimit: gasLimit.toString(),
      safeNonce: "14", operation: 1, innerCalls: [{ to: CREATE_CALL, label: "deploy-reviewed-handoff" }] },
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 3) throw new Error("Usage: node tools/hoodi-public-stage-b-plan.mjs <ignored-local-env-file>");
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const approvalBytes = fs.readFileSync(APPROVAL_PATH, "utf8");
  const approval = JSON.parse(approvalBytes);
  const staged = JSON.parse(fs.readFileSync(STAGED_PATH, "utf8"));
  const plan = await planStageBHandoffDeployment(
    new ethers.JsonRpcProvider(rpc), approval, staged, approvalBytes,
  );
  console.log(JSON.stringify(process.env.HOODI_PLAN_SUMMARY === "1" ? {
    ...plan, transaction: { ...plan.transaction, data: "<omitted; run without HOODI_PLAN_SUMMARY for calldata>" },
  } : plan, null, 2));
}
