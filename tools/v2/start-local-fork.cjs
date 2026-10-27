#!/usr/bin/env node
"use strict";
// Local rehearsal ONLY. Credentials never appear in this script's output.
const fs = require("node:fs");
const { parseEnv } = require("node:util");
const { spawn } = require("node:child_process");
const envFile = process.argv[2];
if (!envFile) throw new Error("Provide the ignored local .env path");
const rpc = process.env.MAINNET_RPC || parseEnv(fs.readFileSync(envFile, "utf8")).MAINNET_RPC;
if (!rpc) throw new Error("MAINNET_RPC is required");
const block = process.env.SEBA_V2_FORK_BLOCK || "26255470";
if (!/^\d+$/.test(block)) throw new Error("Invalid fork block");
const child = spawn(
  "anvil",
  [
    "--host",
    "127.0.0.1",
    "--port",
    "28545",
    "--chain-id",
    "1",
    "--fork-url",
    rpc,
    "--fork-block-number",
    block,
    "--silent",
  ],
  {
    env: { ...process.env, ETHERSCAN_API_KEY: "", RUST_LOG: "error" },
    stdio: ["ignore", "pipe", "pipe"],
  },
);
// Buffer output because keys can be split between stream chunks. Anvil is silent while running.
const output = [];
child.stdout.on("data", (p) => output.push(p));
child.stderr.on("data", (p) => output.push(p));
child.on("error", () => {
  process.stderr.write("Unable to start local Anvil\n");
  process.exitCode = 1;
});
child.on("spawn", () =>
  process.stdout.write(
    `Local-only Anvil requested on 127.0.0.1:28545 at mainnet block ${block}; verify readiness separately.\n`,
  ),
);
child.on("close", (code) => {
  const key = new URL(rpc).pathname.split("/").at(-1);
  let text = Buffer.concat(output).toString("utf8").split(rpc).join("[REDACTED_RPC]");
  if (key) text = text.split(key).join("[REDACTED_RPC_KEY]");
  process.stdout.write(text);
  process.exitCode = code ?? 1;
});
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => child.kill(signal));
