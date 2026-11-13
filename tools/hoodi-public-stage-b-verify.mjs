// Read-only verifier for the exact public Hoodi Stage B Safe cutover receipt.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { HOODI_ADMIN, requireHoodiChain } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE } from "./hoodi-public-v1-next.mjs";
import { APPROVED_STAGE_B_MANIFEST_HASH } from "./hoodi-public-stage-b-plan.mjs";

const safeAbi = [
  "function nonce() view returns(uint256)",
  "event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)",
  "event ExecutionFailure(bytes32 indexed txHash,uint256 payment)",
];
const handoffAbi = [
  "function used() view returns(bool)",
  "event PreMigrationChecked(bytes32 indexed manifest,bytes32 indexed configurationHash,uint256 destinationEthBefore)",
  "event PrincipalHandedOff(address indexed oldManager,address indexed destination,uint256 ethAmount)",
  "event PostMigrationChecked(bytes32 indexed manifest,uint256 residualAdapterPrincipal,uint256 residualAdapterShares,uint256 residualBeefyShares)",
  "event ResidualSurplusObserved(bytes32 indexed manifest,uint256 routerEth,uint256 oldBold,uint256 oldSBold,uint256 routerBold)",
];
const managerAbi = [
  "function intakeEnabled() view returns(bool)", "function executionEnabled() view returns(bool)",
  "function legacyImported() view returns(bool)", "function pendingEth(uint256) view returns(uint256)",
  "event LegacyPrincipalImported(uint256 ethAmount,uint256 rethEth,uint256 ysyBoldEth)",
];

function events(receipt, address, abi) {
  const iface = new ethers.Interface(abi);
  return receipt.logs.filter((log) => log.address === address).map((log) => {
    try { return iface.parseLog(log); } catch { return null; }
  }).filter(Boolean);
}

export async function verifyHoodiStageBCutover(provider, approval, staged, plan, txHash) {
  if (!ethers.isHexString(txHash, 32)) throw new Error("32-byte Hoodi Stage B transaction hash required");
  if (plan?.schemaVersion !== "seba-hoodi-stage-b-cutover-plan-v1" ||
    plan.chainId !== 560048 || plan.transaction?.safeNonce !== "15" ||
    plan.transaction?.from !== HOODI_ADMIN || plan.transaction?.to !== HOODI_REHEARSAL_SAFE ||
    plan.transaction?.valueWei !== "0" || !ethers.isHexString(plan.transaction?.data) ||
    ethers.keccak256(plan.transaction.data) !== plan.transaction.dataHash ||
    plan.approvalManifestHash !== APPROVED_STAGE_B_MANIFEST_HASH ||
    plan.approvalManifestHash !== ethers.keccak256(ethers.toUtf8Bytes(
      fs.readFileSync("docs/HOODI_PHASE5_STAGE_B_MANIFEST.json", "utf8"),
    )) || plan.handoff?.address === ethers.ZeroAddress)
    throw new Error("Stage B reviewed cutover plan missing or changed");
  requireHoodiChain(await provider.send("eth_chainId", []));
  const [tx, receipt] = await Promise.all([provider.getTransaction(txHash), provider.getTransactionReceipt(txHash)]);
  if (!tx || !receipt || receipt.status !== 1 || tx.chainId !== 560048n ||
    tx.from !== HOODI_ADMIN || tx.to !== HOODI_REHEARSAL_SAFE || tx.value !== 0n ||
    tx.data !== plan.transaction.data || receipt.blockNumber < plan.observedAt.blockNumber)
    throw new Error("Stage B receipt differs from exact reviewed Safe transaction");
  const block = await provider.getBlock(receipt.blockNumber);
  if (!block?.hash || block.hash !== receipt.blockHash || block.timestamp > plan.handoff.expiry)
    throw new Error("Stage B receipt block or handoff expiry mismatch");
  const safeEvents = events(receipt, HOODI_REHEARSAL_SAFE, safeAbi).map((event) => event.name);
  if (!safeEvents.includes("ExecutionSuccess") || safeEvents.includes("ExecutionFailure"))
    throw new Error("Stage B Safe execution did not succeed");
  const handoffEvents = events(receipt, plan.handoff.address, handoffAbi);
  const one = (name) => {
    const matching = handoffEvents.filter((event) => event.name === name);
    if (matching.length !== 1) throw new Error(`Stage B ${name} event missing or duplicate`);
    return matching[0].args;
  };
  const pre = one("PreMigrationChecked");
  const transfer = one("PrincipalHandedOff");
  const post = one("PostMigrationChecked");
  const surplus = one("ResidualSurplusObserved");
  if (pre.manifest !== plan.approvalManifestHash || pre.configurationHash !== plan.handoff.configurationHash ||
    pre.destinationEthBefore !== 0n || transfer.oldManager !== approval.legacy.manager ||
    transfer.destination !== approval.destination.managerProxy || transfer.ethAmount !== 10n ** 18n ||
    post.manifest !== plan.approvalManifestHash || post.residualAdapterPrincipal !== 0n ||
    post.residualAdapterShares !== 0n || post.residualBeefyShares !== 0n ||
    surplus.manifest !== plan.approvalManifestHash || surplus.routerEth !== 0n ||
    surplus.oldBold !== 0n || surplus.oldSBold !== 0n || surplus.routerBold !== 0n)
    throw new Error("Stage B handoff event accounting mismatch");
  const imported = events(receipt, approval.destination.managerProxy, managerAbi)
    .filter((event) => event.name === "LegacyPrincipalImported");
  if (imported.length !== 1 || imported[0].args.ethAmount !== 10n ** 18n ||
    imported[0].args.rethEth !== 5n * 10n ** 17n ||
    imported[0].args.ysyBoldEth !== 5n * 10n ** 17n)
    throw new Error("Stage B V2 allocation event mismatch");
  const at = { blockTag: receipt.blockNumber };
  const c = (address, abi) => new ethers.Contract(address, abi, provider);
  const safe = c(HOODI_REHEARSAL_SAFE, safeAbi);
  const old = c(approval.legacy.manager, [
    "function principalValue() view returns(uint256)", "function yieldVault() view returns(address)",
    "function depositId() view returns(uint256)",
  ]);
  const pool = c(approval.legacy.pool, ["function yieldManager() view returns(address)"]);
  const v2 = c(approval.destination.managerProxy, managerAbi);
  const handoff = c(plan.handoff.address, handoffAbi);
  if (await safe.nonce(at) !== 16n || await old.principalValue(at) !== 0n ||
    await old.depositId(at) !== 0n || await old.yieldVault(at) !== plan.handoff.address ||
    await provider.getBalance(approval.legacy.manager, receipt.blockNumber) !== 0n ||
    await provider.getBalance(approval.destination.managerProxy, receipt.blockNumber) !== 10n ** 18n ||
    await pool.yieldManager(at) !== approval.destination.managerProxy ||
    !(await handoff.used(at)) || !(await v2.legacyImported(at)) || !(await v2.intakeEnabled(at)) ||
    await v2.executionEnabled(at) || await v2.pendingEth(0, at) !== 0n ||
    await v2.pendingEth(1, at) !== 5n * 10n ** 17n ||
    await v2.pendingEth(2, at) !== 5n * 10n ** 17n)
    throw new Error("Stage B post-receipt accounting mismatch");
  return {
    schemaVersion: "seba-hoodi-stage-b-receipt-v1", chainId: 560048,
    transactionHash: txHash, blockNumber: receipt.blockNumber, blockHash: receipt.blockHash,
    safeNonce: "16", handoff: plan.handoff.address,
    importedEthWei: "1000000000000000000", pendingRethEthWei: "500000000000000000",
    pendingYsyBoldEthWei: "500000000000000000", oldEthWei: "0",
    poolOnV2: true, v2IntakeEnabled: true, v2ExecutionDisabled: true,
    unmigratedSurplusZero: true,
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  if (process.argv.length !== 5) throw new Error(
    "Usage: node tools/hoodi-public-stage-b-verify.mjs <ignored-local-env-file> <cutover-plan.json> <tx-hash>",
  );
  const env = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || env.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const approval = JSON.parse(fs.readFileSync("docs/HOODI_PHASE5_STAGE_B_MANIFEST.json", "utf8"));
  const staged = JSON.parse(fs.readFileSync("docs/HOODI_V2_STAGED_MANIFEST.json", "utf8"));
  const plan = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  console.log(JSON.stringify(await verifyHoodiStageBCutover(
    new ethers.JsonRpcProvider(rpc), approval, staged, plan, process.argv[4],
  ), null, 2));
}
