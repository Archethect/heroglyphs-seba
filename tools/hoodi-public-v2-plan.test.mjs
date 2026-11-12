import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { ethers } from "ethers";
import { buildHoodiV2StagePlan } from "./hoodi-public-v2-plan.mjs";
import { CREATE_CALL } from "./hoodi-safe-createcall.mjs";
import { HOODI_V2_RUNTIME_HASHES } from "./hoodi-public-v2-runtime.mjs";

const manifest = JSON.parse(fs.readFileSync("docs/HOODI_V1_PUBLIC_MANIFEST.json", "utf8"));

test("V2 stage is deterministic, Hoodi-only, Safe-owned, and does not switch the pool", async () => {
  const plan = await buildHoodiV2StagePlan(manifest);
  assert.equal(plan.chainId, 560048);
  assert.equal(plan.safe, manifest.safe.address);
  assert.equal(plan.owner, manifest.safe.owners[0]);
  assert.equal(plan.deployments.length, 11);
  assert.equal(new Set(plan.deployments.map((d) => d.expectedAddress)).size, 11);
  assert.equal(new Set(plan.deployments.map((d) => d.salt)).size, 11);
  assert.deepEqual(Object.keys(HOODI_V2_RUNTIME_HASHES).sort(), plan.deployments.map((d) => d.label).sort());
  for (const deployment of plan.deployments) {
    assert.equal(deployment.to, CREATE_CALL);
    assert.equal(deployment.valueWei, "0");
    assert.equal(
      deployment.expectedAddress,
      ethers.getCreate2Address(CREATE_CALL, deployment.salt, deployment.creationCodeHash),
    );
  }
  assert.deepEqual(plan.bindings.map((b) => b.label), [
    "manager.bindVaults",
    "manager.configureDisabledExecutor",
    "manager.configureDisabledCow",
  ]);
  assert.ok(plan.bindings.every((b) => b.to === plan.addresses.manager));
  assert.ok(plan.batches.every((b) => b.transaction.valueWei === "0" && b.calls.length > 0));
  assert.ok(plan.batches.flatMap((b) => b.calls).every((c) => c.to !== manifest.v1.pool.address));
});

test("V2 proxies use initializers with zero operator and Safe treasury", async () => {
  const plan = await buildHoodiV2StagePlan(manifest);
  const d = Object.fromEntries(plan.deployments.map((x) => [x.label, x]));
  const managerAbi = new ethers.Interface(JSON.parse(fs.readFileSync("out/YieldManagerV2.sol/YieldManagerV2.json")).abi);
  const managerProxy = d.managerProxy.constructorArgs;
  assert.equal(managerProxy[0], d.managerImplementation.expectedAddress);
  const parsed = managerAbi.parseTransaction({ data: managerProxy[1] });
  assert.equal(parsed.name, "initialize");
  assert.equal(parsed.args[0].treasury, manifest.safe.address);
  assert.equal(parsed.args[0].operator, ethers.ZeroAddress);
  assert.equal(parsed.args[0].pool, manifest.v1.pool.address);
  assert.equal(parsed.args[0].bold, manifest.dependencies.bold.address);
  assert.equal(parsed.args[0].reth, manifest.dependencies.reth.address);
  assert.equal(parsed.args[0].ysyBold, d.ysyBold.expectedAddress);
  assert.equal(d.rethProxy.constructorArgs[0], d.rethImplementation.expectedAddress);
  assert.equal(d.ysyBoldProxy.constructorArgs[0], d.ysyBoldImplementation.expectedAddress);
  assert.equal(d.cowModule.constructorArgs[0], d.managerProxy.expectedAddress);
  assert.equal(d.cowModule.constructorArgs[1], manifest.safe.address);
  assert.equal(d.cowModule.constructorArgs[5], d.cowSettlement.expectedAddress);
  assert.equal(d.cowSettlement.constructorArgs[1], manifest.safe.owners[0]);
});

test("V2 plan rejects an unapproved chain, Safe, or incomplete V1 evidence", async () => {
  for (const mutate of [
    (m) => { m.chainId = 1; },
    (m) => { m.network = "mainnet"; },
    (m) => { m.phase = "cutover"; },
    (m) => { m.safe.address = ethers.ZeroAddress; },
    (m) => { m.safe.owners = []; },
    (m) => { delete m.dependencies.reth; },
  ]) {
    const bad = structuredClone(manifest);
    mutate(bad);
    await assert.rejects(buildHoodiV2StagePlan(bad));
  }
});
