"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const { validateLocalRpc, requireLocalFork } = require("./local-e2e.cjs");

test("local rehearsal cannot target public, retained, authenticated or redirected RPCs", () => {
  assert.equal(validateLocalRpc("http://127.0.0.1:38545"), "http://127.0.0.1:38545/");
  for (const endpoint of [
    "https://eth.drpc.org",
    "http://127.0.0.1:28545",
    "http://user:key@localhost:38545",
    "http://localhost:38545/proxy",
    "http://localhost:38545/?api-key=secret",
    "http://localhost:38545/#x",
    "https://localhost:38545",
    "http://127.0.0.1.example.com:38545",
  ])
    assert.throws(() => validateLocalRpc(endpoint), /isolated loopback/);
});

test("an ordinary Ethereum node or a different fork is rejected before writes", async () => {
  const anchor = { number: 26384004, hash: "0x" + "ab".repeat(32) };
  const provider = (version, chain, hash) => ({
    send: async (method) => {
      if (method === "web3_clientVersion") return version;
      if (method === "anvil_nodeInfo") return { currentBlockNumber: anchor.number };
      throw new Error("unexpected method");
    },
    getNetwork: async () => ({ chainId: chain }),
    getBlock: async () => ({ ...anchor, hash }),
  });
  await assert.rejects(requireLocalFork(provider("Geth", 1n, anchor.hash), anchor), /Anvil/);
  await assert.rejects(requireLocalFork(provider("anvil/v1", 31337n, anchor.hash), anchor), /chain/);
  await assert.rejects(requireLocalFork(provider("anvil/v1", 1n, "0xwrong"), anchor), /anchor/);
  await assert.doesNotReject(requireLocalFork(provider("anvil/v1", 1n, anchor.hash), anchor));
});
