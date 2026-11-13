import test from "node:test";
import assert from "node:assert/strict";
import { requireV2BatchIndex, expectedDeployedCount } from "./hoodi-public-v2-next.mjs";
import { verifyHoodiV2Batch } from "./hoodi-public-v2-verify.mjs";

test("V2 public planner requires an explicit ordered batch index", () => {
  for (let i = 0; i < 6; i++) {
    assert.equal(requireV2BatchIndex(String(i)), i);
  }
  for (const bad of ["", "-1", "6", "00", "0x0", "all", undefined]) {
    assert.throws(() => requireV2BatchIndex(bad));
  }
});

test("V2 batch deployment counts preserve all later addresses absent", () => {
  assert.deepEqual([0, 1, 2, 3, 4, 5].map(expectedDeployedCount), [0, 2, 4, 6, 8, 11]);
  assert.throws(() => expectedDeployedCount(6));
  assert.throws(() => expectedDeployedCount(-1));
});

test("V2 receipt verifier rejects malformed transaction hashes and indices before RPC", async () => {
  await assert.rejects(verifyHoodiV2Batch({}, "0x1234", 0), /32-byte/);
  await assert.rejects(verifyHoodiV2Batch({}, `0x${"00".repeat(32)}`, 6), /index/);
});
