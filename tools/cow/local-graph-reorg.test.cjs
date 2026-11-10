"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { test } = require("node:test");

const script = path.join(__dirname, "local-graph-reorg.cjs");

test("local Graph reorg runner requires an explicit local-execution flag", () => {
  const result = spawnSync(process.execPath, [script], { encoding: "utf8" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /--execute-local/);
});

test("local Graph reorg runner rejects a non-local fixture before opening any RPC connection", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "seba-cow-reorg-guard-"));
  const fixture = path.join(dir, "fixture.json");
  try {
    fs.writeFileSync(
      fixture,
      JSON.stringify({
        localOnly: false,
        rpc: "https://example.invalid",
        chainId: 1,
        cowModule: { address: "0x0000000000000000000000000000000000000001" },
        treasury: "0x0000000000000000000000000000000000000002",
      }),
    );
    const result = spawnSync(process.execPath, [script, fixture, "--execute-local"], { encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Refusing non-isolated/);
  } finally {
    fs.unlinkSync(fixture);
    fs.rmdirSync(dir);
  }
});
