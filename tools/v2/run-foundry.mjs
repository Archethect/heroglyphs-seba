#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { parseEnv } from "node:util";
import { spawn } from "node:child_process";

// Never parse .env with an ad-hoc regex: quotes and inline comments are significant.
const args = process.argv.slice(2);
let envFile = path.resolve(".env");
if (args[0] === "--env-file") {
  envFile = path.resolve(args[1] ?? "");
  args.splice(0, 2);
}
const allowed = new Set(["build", "test", "coverage", "inspect"]);
if (!allowed.has(args[0]) || args.includes("--broadcast")) {
  throw new Error("Only local forge build/test/coverage/inspect are allowed; broadcasting is forbidden");
}
const loaded = fs.existsSync(envFile) ? parseEnv(fs.readFileSync(envFile, "utf8")) : {};
const rpc = process.env.MAINNET_RPC || loaded.MAINNET_RPC;
const env = { ...process.env, ETHERSCAN_API_KEY: "", RUST_LOG: "error" };
if (rpc) env.MAINNET_RPC = rpc;
const redact = (text) => {
  let result = text;
  if (rpc) {
    result = result.split(rpc).join("[REDACTED_RPC]");
    const key = new URL(rpc).pathname.split("/").filter(Boolean).at(-1);
    if (key && key.length >= 16) result = result.split(key).join("[REDACTED_RPC_KEY]");
  }
  return result;
};
// Buffer complete output so a credential split across stream chunks cannot escape redaction.
const child = spawn("forge", args, { env, stdio: ["inherit", "pipe", "pipe"] });
const output = [];
child.stdout.on("data", (part) => output.push(part));
child.stderr.on("data", (part) => output.push(part));
child.on("error", () => {
  process.stderr.write("Unable to start forge\n");
  process.exitCode = 1;
});
child.on("close", (code) => {
  process.stdout.write(redact(Buffer.concat(output).toString("utf8")));
  process.exitCode = code ?? 1;
});
