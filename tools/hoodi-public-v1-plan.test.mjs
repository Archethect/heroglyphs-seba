import test from "node:test";
import assert from "node:assert/strict";
import { ethers } from "ethers";
import { buildHoodiV1Plan } from "./hoodi-public-v1-plan.mjs";
import { CREATE_CALL } from "./hoodi-safe-createcall.mjs";
import { HOODI_V1_RUNTIME_HASHES } from "./hoodi-public-v1-runtime.mjs";

const SAFE = "0xAc52395a9D706696Cf36125A0664c0C6d2B06B7b";
const OWNER = "0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f";

test("V1 plan uses 17 deterministic Hoodi-only creations and five ordered Safe batches", async () => {
  const plan = await buildHoodiV1Plan(SAFE, OWNER);
  assert.equal(plan.chainId, 560048);
  assert.equal(plan.safe, SAFE);
  assert.equal(plan.deployments.length, 17);
  assert.deepEqual(
    plan.batches.map((batch) => batch.name),
    ["dependencies-a", "dependencies-b", "core-a", "core-b", "bindings"],
  );
  assert.equal(new Set(plan.deployments.map((d) => d.expectedAddress)).size, 17);
  assert.equal(new Set(plan.deployments.map((d) => d.salt)).size, 17);
  assert.deepEqual(Object.keys(HOODI_V1_RUNTIME_HASHES).sort(), plan.deployments.map((d) => d.label).sort());
  for (const d of plan.deployments) {
    assert.equal(d.to, CREATE_CALL);
    assert.equal(d.valueWei, "0");
    assert.equal(d.expectedAddress, ethers.getCreate2Address(CREATE_CALL, d.salt, d.creationCodeHash));
    assert.equal(d.creationCodeHash, ethers.keccak256(d.creationCode));
  }
  assert.deepEqual(
    plan.batches.slice(0, 4).map((b) => b.calls.length),
    [6, 5, 3, 3],
  );
  assert.equal(plan.batches[4].calls.length, 7);
});

test("core V1 admin starts at Safe and the mock solver/automator stays bounded to owner", async () => {
  const plan = await buildHoodiV1Plan(SAFE, OWNER);
  const byName = Object.fromEntries(plan.deployments.map((d) => [d.name, d]));
  for (const name of ["PYBSeba", "SebaPool", "EUSDUSDCBeefyYieldVault", "YieldManager"]) {
    assert.equal(byName[name].constructorArgs[0], SAFE);
  }
  assert.equal(byName.EthToBoldRouter.constructorArgs[2], SAFE);
  assert.equal(byName.HoodiEthFlowMock.constructorArgs[0], OWNER);
  assert.equal(byName.SebaPool.constructorArgs[1], OWNER);
  assert.equal(byName.YieldManager.constructorArgs[1], OWNER);
  assert.equal(byName.EthToBoldRouter.constructorArgs[3], SAFE);
  assert.equal(byName.EUSDUSDCBeefyYieldVault.constructorArgs[1], SAFE);
  assert.deepEqual(
    plan.bindings.map((b) => b.label),
    [
      "adapter.grantManager",
      "adapter.revokeBootstrapSafeManager",
      "pyb.bindPool",
      "pool.bindPyb",
      "pool.bindManager",
      "router.grantManager",
      "router.revokeBootstrapSafeManager",
    ],
  );
});
