import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { ethers } from "ethers";
import { validateStageBManifest, requireStageBState, buildStageBCalls, buildHandoffDeployment } from "./hoodi-public-stage-b-plan.mjs";
import { requireDeploymentPlan } from "./hoodi-public-stage-b-exec-plan.mjs";
import { verifyHoodiStageBCutover } from "./hoodi-public-stage-b-verify.mjs";

const approval = JSON.parse(fs.readFileSync("docs/HOODI_PHASE5_STAGE_B_MANIFEST.json", "utf8"));
const staged = JSON.parse(fs.readFileSync("docs/HOODI_V2_STAGED_MANIFEST.json", "utf8"));

function goodState() {
  return {
    safeNonce: 14n, owners: approval.safe.owners, threshold: 1n, modules: [],
    moduleNext: "0x0000000000000000000000000000000000000001", guard: 0n,
    poolManager: approval.legacy.manager, oldVault: approval.stageA.stopper,
    oldPrincipal: 0n, oldDepositId: 0n, oldIdleEth: 10n ** 18n,
    pendingBoldConversion: 0n, activeRouterUid: ethers.ZeroHash, routerOrderActive: false,
    adapterPrincipal: 0n, adapterShares: 0n, actualBeefyShares: 0n,
    routerEth: 0n, oldBold: 0n, oldSBold: 0n, routerBold: 0n,
    v2Intake: false, v2Execution: false, v2Imported: false, v2Recovered: false,
    v2Treasury: approval.safe.address, v2Pool: approval.legacy.pool,
    v2Bold: staged.dependencies.bold.address, v2SBold: staged.v1.sBold.address,
    v2PybSeba: staged.v1.pybSeba.address, v2CowModule: staged.v2.cowModule.address,
    v2Vaults: [staged.v2.rethVault.address, staged.v2.ysyBoldVault.address],
    vaultManagers: [approval.destination.managerProxy, approval.destination.managerProxy],
    v2RethBps: 5000n, v2YsyBps: 5000n, v2PendingEth: [0n, 0n, 0n],
    v2PendingBold: 0n, v2PendingSBold: 0n, v2PendingProtocolBold: 0n,
    cowActive: 0n, cowEnabled: false, vaultProtocolBasis: [0n, 0n], vaultProtocolTokens: [0n, 0n],
    vaultRecovery: [0n, 0n], harvestInventory: [0n, 0n, 0n, 0n],
    legacyHandoff: ethers.ZeroAddress, legacyExpectedEth: 0n,
    legacyManifest: ethers.ZeroHash, destinationEth: 0n,
  };
}

test("Stage B approval pins the exact Hoodi-only one-ETH, zero-surplus handoff", () => {
  assert.doesNotThrow(() => validateStageBManifest(approval, staged));
  for (const altered of [
    { ...approval, chainId: 1 },
    { ...approval, stageA: { ...approval.stageA, parkedEthWei: "2" } },
    { ...approval, legacy: { ...approval.legacy, pool: ethers.ZeroAddress } },
    { ...approval, approvedUnmigratedSurplusCaps: { ...approval.approvedUnmigratedSurplusCaps, maximumOldBold: "1" } },
  ]) assert.throws(() => validateStageBManifest(altered, staged));
});

test("Stage B preflight rejects changed authority, claims, funds, orders, residuals, or destination", () => {
  assert.doesNotThrow(() => requireStageBState(approval, goodState(), staged));
  for (const [key, value] of [
    ["safeNonce", 15n], ["owners", [ethers.ZeroAddress]], ["threshold", 2n],
    ["modules", [approval.legacy.manager]], ["guard", 1n],
    ["poolManager", approval.destination.managerProxy], ["oldVault", approval.legacy.adapter],
    ["oldPrincipal", 1n], ["oldDepositId", 1n], ["oldIdleEth", 1n],
    ["pendingBoldConversion", 1n], ["activeRouterUid", ethers.id("order")],
    ["routerOrderActive", true], ["adapterShares", 1n], ["actualBeefyShares", 1n],
    ["routerEth", 1n], ["oldBold", 1n], ["oldSBold", 1n], ["routerBold", 1n],
    ["v2Intake", true], ["v2Execution", true], ["v2Imported", true], ["v2Recovered", true],
    ["v2Treasury", ethers.ZeroAddress], ["v2Pool", ethers.ZeroAddress],
    ["v2Bold", ethers.ZeroAddress], ["v2SBold", ethers.ZeroAddress],
    ["v2PybSeba", ethers.ZeroAddress], ["v2CowModule", ethers.ZeroAddress],
    ["v2Vaults", [ethers.ZeroAddress, staged.v2.ysyBoldVault.address]],
    ["vaultManagers", [ethers.ZeroAddress, approval.destination.managerProxy]],
    ["v2RethBps", 6000n], ["v2PendingEth", [0n, 1n, 0n]],
    ["v2PendingBold", 1n], ["v2PendingSBold", 1n], ["v2PendingProtocolBold", 1n],
    ["cowActive", 1n], ["vaultProtocolBasis", [1n, 0n]], ["vaultProtocolTokens", [0n, 1n]],
    ["vaultRecovery", [1n, 0n]], ["harvestInventory", [0n, 0n, 1n, 0n]],
  ]) assert.throws(() => requireStageBState(approval, { ...goodState(), [key]: value }, staged), key);
});

test("Stage B call order is exact; neither reward conversion nor strategy investment is enabled", () => {
  const handoff = "0x1111111111111111111111111111111111111111";
  const manifestHash = ethers.id("reviewed Hoodi Stage B manifest");
  const calls = buildStageBCalls(approval, staged, handoff, 1_800_000_000n, manifestHash);
  assert.deepEqual(calls.map((x) => x.label), [
    "arm-exact-import", "assert-pre-migration", "set-v1-handoff",
    "import-parked-eth", "enable-v2-intake", "switch-pool-manager", "assert-post-migration",
  ]);
  assert.deepEqual(calls.map((x) => x.to), [
    approval.destination.managerProxy, handoff, approval.legacy.manager,
    approval.legacy.manager, approval.destination.managerProxy, approval.legacy.pool, handoff,
  ]);
  const manager = new ethers.Interface(staged.v2.manager.abi ?? [
    "function armLegacyImport(address,uint256,uint256,bytes32)",
  ]);
  assert.equal(manager.decodeFunctionData("armLegacyImport", calls[0].data)[1], 10n ** 18n);
  assert.ok(calls.every((x) => ethers.isHexString(x.data)));
});

test("Stage B deployment plan must reproduce exact constructor, CREATE2 salt and outer Safe calldata", async () => {
  const approvalBytes = fs.readFileSync("docs/HOODI_PHASE5_STAGE_B_MANIFEST.json", "utf8");
  const approvalManifestHash = ethers.keccak256(ethers.toUtf8Bytes(approvalBytes));
  const expiry = 1_800_000_000;
  const canonical = await buildHandoffDeployment(approval, expiry, approvalManifestHash);
  const plan = {
    schemaVersion: "seba-hoodi-stage-b-handoff-deployment-plan-v1", chainId: 560048,
    readOnly: true, broadcast: false, approvalManifestHash, expiry,
    observedAt: { timestamp: expiry - 3600 }, configurationHash: canonical.configurationHash,
    handoff: { expectedAddress: canonical.deployment.expectedAddress,
      creationCodeHash: ethers.keccak256(canonical.code), salt: canonical.salt },
    transaction: { to: approval.safe.address, from: approval.safe.owners[0], valueWei: "0",
      safeNonce: "14", data: canonical.data, dataHash: ethers.keccak256(canonical.data) },
  };
  await assert.doesNotReject(requireDeploymentPlan(approval, plan, approvalBytes));
  for (const changed of [
    { ...plan, configurationHash: ethers.ZeroHash },
    { ...plan, handoff: { ...plan.handoff, expectedAddress: ethers.ZeroAddress } },
    { ...plan, transaction: { ...plan.transaction, data: `${plan.transaction.data}00`,
      dataHash: ethers.keccak256(`${plan.transaction.data}00`) } },
  ]) await assert.rejects(requireDeploymentPlan(approval, changed, approvalBytes));
});

test("Stage B receipt verifier refuses malformed hashes before touching RPC", async () => {
  await assert.rejects(verifyHoodiStageBCutover({}, approval, staged, {}, "0x1234"), /32-byte/);
});
