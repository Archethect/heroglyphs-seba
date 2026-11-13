"use strict";

const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "../..");

test("Hoodi fork verification is an explicit credentialed CI gate", () => {
  const workflow = fs.readFileSync(path.join(root, ".github/workflows/v2.yml"), "utf8");
  assert.match(workflow, /HOODI_RPC:\s*\$\{\{ secrets\.HOODI_RPC \}\}/);
  assert.match(workflow, /test -n "\$HOODI_RPC"/);
  assert.match(workflow, /test --match-path 'tests\/hoodi\/\*\*'/);
  assert.match(workflow, /tools\/hoodi-local-rehearsal\.test\.mjs/);
});

test("Foundry wrapper redacts both archive RPC credentials from output", (t) => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "seba-hoodi-rpc-test-"));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const fakeForge = path.join(temporary, "forge");
  fs.writeFileSync(fakeForge, '#!/bin/sh\nprintf "%s\\n" "$MAINNET_RPC" "$HOODI_RPC"\n', { mode: 0o755 });
  const mainnetRpc = "https://mainnet.invalid/v2-test-mainnet-secret-0123456789";
  const hoodiRpc = "https://hoodi.invalid/v2-test-hoodi-secret-0123456789";
  const result = spawnSync(process.execPath, [path.join(root, "tools/v2/run-foundry.mjs"), "build"], {
    cwd: root,
    env: {
      ...process.env,
      MAINNET_RPC: mainnetRpc,
      HOODI_RPC: hoodiRpc,
      PATH: `${temporary}${path.delimiter}${process.env.PATH ?? ""}`,
    },
    encoding: "utf8",
    timeout: 10_000,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /v2-test-(mainnet|hoodi)-secret/);
  assert.doesNotMatch(result.stdout, /https:\/\/(mainnet|hoodi)\.invalid/);
  assert.equal((result.stdout.match(/\[REDACTED_RPC\]/g) ?? []).length, 2);
});
