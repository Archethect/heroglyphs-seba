import test from "node:test";
import assert from "node:assert/strict";
import { ethers } from "ethers";
import {
  HOODI_ADMIN,
  HOODI_CHAIN_ID,
  SAFE_FACTORY,
  SAFE_SALT_NONCE,
  SAFE_SINGLETON,
  planHoodiSafe,
  requireExpectedCodeHash,
  requireHoodiChain,
  safeFactoryInputs,
  safeFactoryPayload,
} from "./hoodi-public-safe-plan.mjs";

test("public planner refuses non-Hoodi RPC before any other request", async () => {
  let calls = 0;
  const provider = {
    send: async () => {
      calls++;
      return "0x1";
    },
  };
  await assert.rejects(planHoodiSafe(provider, { contractsCommit: "a".repeat(40), worktreeDirty: false }), /non-Hoodi/);
  assert.equal(calls, 1);
  assert.doesNotThrow(() => requireHoodiChain(HOODI_CHAIN_ID));
});

test("public planner refuses absent, unknown, or changed dependency code", () => {
  assert.throws(() => requireExpectedCodeHash(SAFE_FACTORY, "0x"), /code hash mismatch/);
  assert.throws(() => requireExpectedCodeHash(SAFE_FACTORY, "0x6000"), /code hash mismatch/);
  assert.throws(() => requireExpectedCodeHash(ethers.ZeroAddress, "0x6000"), /code hash mismatch/);
});

test("Safe creation calldata has exactly one Hoodi admin and no setup hooks", () => {
  const inputs = safeFactoryInputs();
  assert.equal(ethers.dataLength(inputs.initializer), 356);
  assert.equal(inputs.singleton, SAFE_SINGLETON);
  assert.equal(inputs.saltNonce, SAFE_SALT_NONCE.toString());
  const factory = new ethers.Interface([
    "function createProxyWithNonce(address singleton,bytes initializer,uint256 saltNonce) returns (address proxy)",
  ]);
  const safe = new ethers.Interface([
    "function setup(address[] owners,uint256 threshold,address to,bytes data,address fallbackHandler,address paymentToken,uint256 payment,address payable paymentReceiver)",
  ]);
  const decodedFactory = factory.decodeFunctionData("createProxyWithNonce", safeFactoryPayload());
  assert.equal(decodedFactory.singleton, SAFE_SINGLETON);
  assert.equal(decodedFactory.saltNonce, SAFE_SALT_NONCE);
  assert.equal(decodedFactory.initializer, inputs.initializer);
  const decodedSafe = safe.decodeFunctionData("setup", decodedFactory.initializer);
  assert.deepEqual(Array.from(decodedSafe.owners), [HOODI_ADMIN]);
  assert.equal(decodedSafe.threshold, 1n);
  assert.equal(decodedSafe.to, ethers.ZeroAddress);
  assert.equal(decodedSafe.data, "0x");
  assert.equal(decodedSafe.fallbackHandler, ethers.ZeroAddress);
  assert.equal(decodedSafe.paymentToken, ethers.ZeroAddress);
  assert.equal(decodedSafe.payment, 0n);
  assert.equal(decodedSafe.paymentReceiver, ethers.ZeroAddress);
});
