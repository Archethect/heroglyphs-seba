import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { ethers } from "ethers";
import { buildHoodiV2StagePlan } from "./hoodi-public-v2-plan.mjs";
import { assembleHoodiV2Manifest } from "./hoodi-public-v2-manifest.mjs";

const previousBytes = fs.readFileSync("docs/HOODI_V1_PUBLIC_MANIFEST.json");
const previous = JSON.parse(previousBytes.toString());

test("V2 evidence retains V1 identities/history and links exact prior bytes", async () => {
  const plan = await buildHoodiV2StagePlan(previous);
  const receipts = Array.from({ length: 6 }, (_, i) => ({
    transactionHash: `0x${(i + 1).toString(16).padStart(64, "0")}`,
    blockNumber: 4_000_000 + i,
    blockHash: `0x${(i + 10).toString(16).padStart(64, "0")}`,
  }));
  const relayer = { address: "0x2319315d793c60010F99C7b88d3111E19412A01C", runtimeCodeHash: ethers.id("relayer") };
  const result = assembleHoodiV2Manifest(previousBytes, plan, receipts, relayer);
  assert.equal(result.phase, "v2-staged");
  assert.equal(result.previousManifestHash, ethers.keccak256(previousBytes));
  assert.equal(result.source.contractsCommit, previous.source.contractsCommit);
  assert.deepEqual(result.safe, previous.safe);
  assert.deepEqual(result.v1, previous.v1);
  for (const [key, value] of Object.entries(previous.dependencies)) assert.deepEqual(result.dependencies[key], value);
  assert.equal(result.v2.manager.address, plan.addresses.manager);
  assert.equal(result.v2.rethVault.address, plan.addresses.rethVault);
  assert.equal(result.v2.ysyBoldVault.address, plan.addresses.ysyBoldVault);
  assert.equal(result.v2.cowModule.address, plan.addresses.cowModule);
  assert.equal(result.dependencies.cowRelayer.address, relayer.address);
  assert.equal(result.dependencies.cowRelayer.creationKind, "internal-create");
  assert.deepEqual(result.checkpoint, { blockNumber: receipts[5].blockNumber, blockHash: receipts[5].blockHash });
  assert.equal(result.transactions.length, previous.transactions.length + 6);
  assert.deepEqual(result.cutover, {});
});

test("V2 manifest assembler rejects incomplete receipt sequence", async () => {
  const plan = await buildHoodiV2StagePlan(previous);
  assert.throws(() => assembleHoodiV2Manifest(previousBytes, plan, [], {}), /six/);
});
