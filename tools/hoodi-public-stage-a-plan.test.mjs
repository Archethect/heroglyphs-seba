import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { ethers } from "ethers";
import { buildHoodiStageABatch, requireStageAState } from "./hoodi-public-stage-a-plan.mjs";
import { requireExactStageATxData, verifyHoodiStageA } from "./hoodi-public-stage-a-verify.mjs";
import { HOODI_ADMIN } from "./hoodi-public-safe-plan.mjs";
import { encodeOwnerSafeExecution } from "./hoodi-public-v1-next.mjs";

const manifest = JSON.parse(fs.readFileSync("docs/HOODI_V2_STAGED_MANIFEST.json", "utf8"));

test("Stage A is a single Hoodi Safe batch: refresh, deploy stopper, exit", () => {
  const plan = buildHoodiStageABatch(manifest, 1_794_560_000);
  assert.deepEqual(plan.calls.map((call) => call.label), [
    "refresh-eth-usd", "refresh-usdc-usd", "deploy-intake-stopper", "exit-v1-and-stop-intake",
  ]);
  assert.equal(plan.calls[0].to, manifest.dependencies.ethUsdFeed.address);
  assert.equal(plan.calls[1].to, manifest.dependencies.usdcUsdFeed.address);
  assert.equal(plan.calls[3].to, manifest.v1.manager.address);
  assert.equal(plan.calls[2].expectedAddress, plan.stopper);
  assert.equal(new ethers.Interface(["function setYieldVault(address)"]).decodeFunctionData(
    "setYieldVault", plan.calls[3].data)[0], plan.stopper);
  assert.equal(plan.transaction.operation, 1);
  assert.equal(plan.transaction.valueWei, "0");
  assert.ok(ethers.isHexString(plan.transaction.data));
});

test("Stage A refuses wrong phase, Safe, or report time", () => {
  assert.throws(() => buildHoodiStageABatch({ ...manifest, phase: "cutover" }, 1), /staged/);
  assert.throws(() => buildHoodiStageABatch({ ...manifest, safe: { ...manifest.safe, address: ethers.ZeroAddress } }, 1), /Safe/);
  assert.throws(() => buildHoodiStageABatch(manifest, 0), /timestamp/);
  assert.throws(() => buildHoodiStageABatch(manifest, 1.5), /timestamp/);
});

test("Stage A rejects claims, orders, custody drift, or enabled V2", () => {
  const good = {
    safeNonce: 13n, poolManager: manifest.v1.manager.address, oldVault: manifest.v1.beefyAdapter.address,
    depositId: 0n, pendingBold: 0n, activeRouterUid: ethers.ZeroHash, oldIdleEth: 0n,
    oldPrincipal: 2000n * 10n ** 18n, adapterPrincipal: 2000n * 10n ** 18n,
    adapterShares: 2000n * 10n ** 18n, beefyShares: 2000n * 10n ** 18n,
    v2IntakeEnabled: false, v2ExecutionEnabled: false, legacyImported: false,
    cowEnabled: false, cowActiveCount: 0n, v2PendingEth: [0n, 0n, 0n],
  };
  assert.doesNotThrow(() => requireStageAState(manifest, good));
  for (const [field, value] of [
    ["safeNonce", 14n], ["poolManager", ethers.ZeroAddress], ["oldVault", ethers.ZeroAddress],
    ["depositId", 1n], ["pendingBold", 1n], ["activeRouterUid", ethers.id("order")],
    ["oldIdleEth", 1n], ["oldPrincipal", 0n], ["adapterPrincipal", 0n],
    ["adapterShares", 1n], ["beefyShares", 1n], ["v2IntakeEnabled", true],
    ["v2ExecutionEnabled", true], ["legacyImported", true], ["cowEnabled", true],
    ["cowActiveCount", 1n], ["v2PendingEth", [0n, 1n, 0n]],
  ]) assert.throws(() => requireStageAState(manifest, { ...good, [field]: value }), /Stage A/);
});

test("Stage A receipt verifier accepts only the canonical full Safe calldata", async () => {
  const batch = buildHoodiStageABatch(manifest, 1_794_560_000);
  const data = encodeOwnerSafeExecution(batch.transaction.data, HOODI_ADMIN);
  assert.equal(requireExactStageATxData(manifest, data).reportTime, batch.reportTime);
  assert.throws(() => requireExactStageATxData(manifest, `${data}00`), /differs/);
  assert.throws(() => requireExactStageATxData(manifest, "0x1234"));
  await assert.rejects(verifyHoodiStageA({}, "0x1234", manifest), /32-byte/);
});
