#!/usr/bin/env node
"use strict";

// Isolated Anvil/Graph Node only. Proves Graph Node rolls back an orphaned CoW
// execution event and indexes the replacement block at the same height.
const fs = require("node:fs");
const { Contract, Interface, JsonRpcProvider } = require("ethers");

const fixturePath = process.argv[2];
if (!fixturePath || process.argv[3] !== "--execute-local" || process.argv.length !== 4)
  throw new Error("Usage: node tools/cow/local-graph-reorg.cjs FIXTURE --execute-local");
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
const RPC = "http://127.0.0.1:38545/";
const GRAPH = "http://127.0.0.1:38000/subgraphs/name/seba/cow-local";
if (
  !fixture.localOnly ||
  fixture.rpc !== RPC ||
  fixture.chainId !== 1 ||
  !fixture.cowModule?.address ||
  !fixture.treasury
)
  throw new Error("Refusing non-isolated or incomplete fork fixture");
const moduleAddress = fixture.cowModule.address;

const provider = new JsonRpcProvider(RPC);
const iface = new Interface(["function setEnabled(bool)", "function enabled() view returns (bool)"]);
const moduleContract = new Contract(moduleAddress, iface, provider);
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function graphState() {
  const response = await fetch(GRAPH, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      query:
        '{ _meta { block { number hash } } cowIntentModuleStates(first: 10) { id executionEnabled } cowIntentEvents(first: 1000, where: { kind: "CowExecutionSet" }) { transaction enabled } }',
    }),
  });
  if (!response.ok) throw new Error("Local Graph Node unavailable");
  const result = await response.json();
  if (result.errors || !result.data) throw new Error("Local Graph query failed");
  const state = result.data.cowIntentModuleStates.find((item) => item.id.endsWith(":" + moduleAddress.toLowerCase()));
  if (!state) throw new Error("Configured module not indexed");
  return { meta: result.data._meta.block, state, events: result.data.cowIntentEvents };
}

async function waitIndexed(block, hash, enabled, presentTx, absentTx) {
  for (let attempt = 0; attempt < 80; attempt++) {
    const indexed = await graphState();
    const txs = new Set(indexed.events.map((item) => item.transaction.toLowerCase()));
    const canonical = hash
      ? indexed.meta.number === block && indexed.meta.hash.toLowerCase() === hash.toLowerCase()
      : indexed.meta.number >= block &&
        indexed.meta.hash.toLowerCase() === (await provider.getBlock(indexed.meta.number)).hash.toLowerCase();
    if (
      canonical &&
      indexed.state.executionEnabled === enabled &&
      txs.has(presentTx.toLowerCase()) &&
      (!absentTx || !txs.has(absentTx.toLowerCase()))
    )
      return;
    await pause(1000);
  }
  throw new Error("Graph Node did not converge to the expected local reorg state");
}

async function main() {
  const anchor = await provider.getBlock(fixture.anchorBlock);
  const head = await provider.getBlock("latest");
  if (
    !anchor ||
    anchor.hash.toLowerCase() !== fixture.anchorHash.toLowerCase() ||
    !head ||
    head.number !== fixture.lastBlockNumber ||
    head.hash.toLowerCase() !== fixture.lastBlockHash.toLowerCase()
  )
    throw new Error("Local fork does not match the reviewed fixture head");
  const initial = await moduleContract.enabled();
  const before = await graphState();
  if (
    before.meta.number !== head.number ||
    before.meta.hash.toLowerCase() !== head.hash.toLowerCase() ||
    before.state.executionEnabled !== initial
  )
    throw new Error("Graph Node must be caught up before reorg test");

  const snapshot = await provider.send("evm_snapshot", []);
  let reverted = false;
  try {
    await provider.send("anvil_impersonateAccount", [fixture.treasury]);
    const safe = await provider.getSigner(fixture.treasury);
    const orphan = await safe.sendTransaction({
      to: moduleAddress,
      data: iface.encodeFunctionData("setEnabled", [!initial]),
    });
    const orphanReceipt = await orphan.wait();
    const orphanBlock = await provider.getBlock(orphanReceipt.blockNumber);
    await waitIndexed(orphanBlock.number, orphanBlock.hash, !initial, orphan.hash);

    if (!(await provider.send("evm_revert", [snapshot]))) throw new Error("Local Anvil snapshot revert failed");
    reverted = true;
    await provider.send("anvil_impersonateAccount", [fixture.treasury]);
    const replacement = await (
      await provider.getSigner(fixture.treasury)
    ).sendTransaction({
      to: moduleAddress,
      data: iface.encodeFunctionData("setEnabled", [initial]),
    });
    const replacementReceipt = await replacement.wait();
    const replacementBlock = await provider.getBlock(replacementReceipt.blockNumber);
    if (replacementBlock.number !== orphanBlock.number || replacementBlock.hash === orphanBlock.hash)
      throw new Error("Replacement did not produce a same-height competing block");
    // Graph Node's polling ingestor needs a successor before it notices a same-height reorg.
    await provider.send("anvil_mine", ["0x6"]);
    await waitIndexed(replacementBlock.number + 1, null, initial, replacement.hash, orphan.hash);
    if ((await moduleContract.enabled()) !== initial) throw new Error("Local module state was not restored");
    console.log(
      JSON.stringify({
        localOnly: true,
        orphanBlock: orphanBlock.number,
        orphanHash: orphanBlock.hash,
        replacementHash: replacementBlock.hash,
        orphanEventRemoved: true,
        replacementEventIndexed: true,
        stateRestored: true,
      }),
    );
  } finally {
    if (!reverted) await provider.send("evm_revert", [snapshot]);
    await provider.send("anvil_stopImpersonatingAccount", [fixture.treasury]);
  }
}
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
