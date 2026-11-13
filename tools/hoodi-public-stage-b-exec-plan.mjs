// Read-only public Hoodi preflight for the exact seven-call Stage B Safe cutover.
// Requires a prior, separately verified handoff deployment; never signs or sends.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { currentSource } from "./hoodi-source-gate.mjs";
import { HOODI_ADMIN, requireHoodiChain, SAFE_MULTISEND } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE, encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";
import { multiSendData } from "./hoodi-safe-createcall.mjs";
import {
  buildHandoffDeployment, buildStageBCalls, checkSourceCommit, checkStageBCode, readStageBState,
  requireStageBState, validateStageBManifest,
} from "./hoodi-public-stage-b-plan.mjs";

const safeAbi = [
  "function nonce() view returns(uint256)",
  "function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns(bool)",
  "event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)",
  "event ExecutionFailure(bytes32 indexed txHash,uint256 payment)",
];
const handoffAbi = [
  "function CONFIGURATION_HASH() view returns(bytes32)", "function used() view returns(bool)",
  "function chainId() view returns(uint256)", "function expectedEth() view returns(uint256)",
  "function expiry() view returns(uint256)", "function treasury() view returns(address)",
  "function destination() view returns(address)",
  "function configuration() view returns(tuple(address oldManager,address destination,address treasury,address pool,address oldVault,address stagingVault,address oldRouter,uint256 expectedEth,uint256 expiry,uint256 oldPrincipal,uint256 oldDepositId,uint256 adapterPrincipal,uint256 adapterShares,uint256 actualBeefyShares,uint256 oldIdleEth,bytes32 safeOwnersHash,uint256 safeThreshold,uint16 rethBps,bytes32 manifest,uint256 maximumRouterEth,uint256 maximumOldBold,uint256 maximumOldSBold,uint256 maximumRouterBold))",
];

export async function requireDeploymentPlan(a, plan, approvalBytes) {
  if (plan?.schemaVersion !== "seba-hoodi-stage-b-handoff-deployment-plan-v1" ||
    plan.chainId !== 560048 || plan.readOnly !== true || plan.broadcast !== false ||
    plan.approvalManifestHash !== ethers.keccak256(ethers.toUtf8Bytes(approvalBytes)) ||
    plan.transaction?.to !== HOODI_REHEARSAL_SAFE || plan.transaction?.from !== HOODI_ADMIN ||
    plan.transaction?.valueWei !== "0" || plan.transaction?.safeNonce !== "14" ||
    !ethers.isHexString(plan.transaction?.data) ||
    ethers.keccak256(plan.transaction.data) !== plan.transaction.dataHash ||
    !ethers.isAddress(plan.handoff?.expectedAddress) || !ethers.isHexString(plan.handoff?.salt, 32) ||
    !ethers.isHexString(plan.configurationHash, 32) ||
    !Number.isSafeInteger(plan.expiry) || plan.expiry <= plan.observedAt?.timestamp ||
    a.safe.expectedNonceBeforeHandoffDeployment !== 14) throw new Error("Stage B deployment plan is invalid");
  const canonical = await buildHandoffDeployment(a, plan.expiry, plan.approvalManifestHash);
  if (plan.transaction.data !== canonical.data ||
    plan.handoff.expectedAddress !== canonical.deployment.expectedAddress ||
    plan.handoff.salt !== canonical.salt ||
    plan.handoff.creationCodeHash !== ethers.keccak256(canonical.code) ||
    plan.configurationHash !== canonical.configurationHash)
    throw new Error("Stage B deployment plan differs from canonical source and manifest");
}

/** Exact onchain receipt and current-state verification before any Stage B cutover payload is released. */
export async function planStageBCutover(provider, a, m, approvalBytes, deploymentPlan, deploymentTxHash,
  source = currentSource(), sourceVerified = false) {
  validateStageBManifest(a, m);
  await requireDeploymentPlan(a, deploymentPlan, approvalBytes);
  checkSourceCommit(a);
  if (!ethers.isHexString(deploymentTxHash, 32)) throw new Error("Stage B handoff deployment receipt hash required");
  requireHoodiChain(await provider.send("eth_chainId", []));
  const head = await provider.getBlock("latest");
  if (!head?.hash || head.timestamp + 600 > deploymentPlan.expiry ||
    (await provider.getBlock(a.stageA.blockNumber))?.hash !== a.stageA.blockHash ||
    (await provider.getBlock(a.snapshot.blockNumber))?.hash !== a.snapshot.blockHash)
    throw new Error("Stage B expiry too close or chain anchor changed");
  const [tx, receipt] = await Promise.all([
    provider.getTransaction(deploymentTxHash), provider.getTransactionReceipt(deploymentTxHash),
  ]);
  if (!tx || !receipt || receipt.status !== 1 || tx.chainId !== 560048n ||
    tx.from !== HOODI_ADMIN || tx.to !== HOODI_REHEARSAL_SAFE || tx.value !== 0n ||
    tx.data !== deploymentPlan.transaction.data || receipt.blockNumber < deploymentPlan.observedAt.blockNumber)
    throw new Error("Stage B handoff deployment is not the reviewed Safe transaction");
  const safe = new ethers.Interface(safeAbi);
  const safeEvents = receipt.logs.filter((log) => log.address === HOODI_REHEARSAL_SAFE).map((log) => {
    try { return safe.parseLog(log)?.name; } catch { return null; }
  });
  if (!safeEvents.includes("ExecutionSuccess") || safeEvents.includes("ExecutionFailure"))
    throw new Error("Stage B Safe handoff deployment did not succeed");
  await checkStageBCode(provider, a, m, head.number);
  const code = await provider.getCode(deploymentPlan.handoff.expectedAddress, head.number);
  if (code === "0x") throw new Error("Stage B handoff code absent after Safe deployment");
  const h = new ethers.Contract(deploymentPlan.handoff.expectedAddress, handoffAbi, provider);
  const at = { blockTag: head.number };
  const config = await h.configuration(at);
  if (await h.CONFIGURATION_HASH(at) !== deploymentPlan.configurationHash || await h.used(at) ||
    await h.chainId(at) !== 560048n || await h.expectedEth(at) !== BigInt(a.stageA.parkedEthWei) ||
    await h.expiry(at) !== BigInt(deploymentPlan.expiry) ||
    await h.treasury(at) !== a.safe.address || await h.destination(at) !== a.destination.managerProxy ||
    config.manifest !== deploymentPlan.approvalManifestHash || config.maximumRouterEth !== 0n ||
    config.maximumOldBold !== 0n || config.maximumOldSBold !== 0n || config.maximumRouterBold !== 0n)
    throw new Error("Stage B deployed handoff configuration drift");
  const state = await readStageBState(provider, a, m, head.number);
  requireStageBState({ ...a, safe: { ...a.safe, expectedNonceBeforeHandoffDeployment: 15 } }, state, m);
  const calls = buildStageBCalls(a, m, deploymentPlan.handoff.expectedAddress,
    deploymentPlan.expiry, deploymentPlan.approvalManifestHash);
  const data = encodeOwnerSafeExecution(multiSendData(calls), HOODI_ADMIN);
  const request = { from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, value: 0n, data };
  const callResult = await provider.call({ ...request, blockTag: head.number });
  if (!safe.decodeFunctionResult("execTransaction", callResult)[0])
    throw new Error("Stage B full Safe cutover simulation returned false");
  const estimatedGas = await provider.estimateGas(request);
  const gasLimit = estimatedGas * 125n / 100n;
  if (gasLimit >= head.gasLimit) throw new Error("Stage B cutover exceeds Hoodi block gas limit");
  const fees = await provider.getFeeData();
  const maxFeePerGas = fees.maxFeePerGas ?? fees.gasPrice;
  if (!maxFeePerGas || await provider.getBalance(HOODI_ADMIN, head.number) < gasLimit * maxFeePerGas)
    throw new Error("Stage B Hoodi owner cannot fund cutover gas");
  if (await provider.getTransactionCount(HOODI_ADMIN, "latest") !==
    await provider.getTransactionCount(HOODI_ADMIN, "pending"))
    throw new Error("Stage B Hoodi owner has pending transaction");
  return {
    schemaVersion: "seba-hoodi-stage-b-cutover-plan-v1", readOnly: true, broadcast: false,
    executionReady: !source.worktreeDirty && sourceVerified,
    sourceVerified, chainId: 560048, approvalManifestHash: deploymentPlan.approvalManifestHash,
    observedAt: { blockNumber: head.number, blockHash: head.hash, timestamp: head.timestamp },
    handoff: { address: deploymentPlan.handoff.expectedAddress, deploymentTxHash,
      configurationHash: deploymentPlan.configurationHash, expiry: deploymentPlan.expiry },
    transaction: { from: HOODI_ADMIN, to: HOODI_REHEARSAL_SAFE, valueWei: "0", data,
      dataHash: ethers.keccak256(data), estimatedGas: estimatedGas.toString(), gasLimit: gasLimit.toString(),
      safeNonce: "15", operation: 1,
      innerCalls: calls.map((call) => ({ label: call.label, to: call.to })) },
  };
}

async function hoodiSourceVerified(apiKey, address) {
  if (!apiKey) throw new Error("Hoodi Etherscan API key required to verify handoff source");
  const url = new URL("https://api.etherscan.io/v2/api");
  for (const [name, value] of Object.entries({
    chainid: "560048", module: "contract", action: "getsourcecode", address, apikey: apiKey,
  })) url.searchParams.set(name, value);
  const response = await fetch(url);
  if (!response.ok) throw new Error("Hoodi Etherscan source lookup failed");
  const result = await response.json();
  const source = result?.result?.[0];
  return result.status === "1" && source?.ContractName === "LegacyProtocolPrincipalHandoff" &&
    source.SourceCode?.length > 0 && source.CompilerVersion === "v0.8.28+commit.7893614a" &&
    source.OptimizationUsed === "1" && source.Runs === "200" && !source.SimilarMatch;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 5) throw new Error(
    "Usage: node tools/hoodi-public-stage-b-exec-plan.mjs <ignored-local-env-file> <deployment-plan.json> <deployment-tx-hash>",
  );
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const approvalBytes = fs.readFileSync("docs/HOODI_PHASE5_STAGE_B_MANIFEST.json", "utf8");
  const approval = JSON.parse(approvalBytes);
  const staged = JSON.parse(fs.readFileSync("docs/HOODI_V2_STAGED_MANIFEST.json", "utf8"));
  const deploymentPlan = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  const sourceVerified = await hoodiSourceVerified(env.ETHERSCAN_API_KEY, deploymentPlan.handoff.expectedAddress);
  const plan = await planStageBCutover(new ethers.JsonRpcProvider(rpc), approval, staged, approvalBytes,
    deploymentPlan, process.argv[4], currentSource(), sourceVerified);
  console.log(JSON.stringify(process.env.HOODI_PLAN_SUMMARY === "1" ? {
    ...plan, transaction: { ...plan.transaction, data: "<omitted; run without HOODI_PLAN_SUMMARY for calldata>" },
  } : plan, null, 2));
}
