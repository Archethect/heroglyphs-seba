#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { execFileSync } = require("node:child_process");
const { UpgradeableContract, getStorageUpgradeErrors, validateUpgradeSafety } = require("@openzeppelin/upgrades-core");

const root = path.resolve(__dirname, "../..");
const source = "src/YBoldYieldVault.sol";
const target = `${source}:YBoldYieldVault`;
const v2Target = "tests/mocks/YBoldYieldVaultV2Mock.sol:YBoldYieldVaultV2Mock";
const baseline = JSON.parse(fs.readFileSync(path.join(__dirname, "storage-layout.baseline.json"), "utf8"));

async function main() {
  // A fresh build avoids validating stale or coverage-instrumented artifacts.
  execFileSync("forge", ["build", "--force", "--silent"], { cwd: root, stdio: "pipe" });
  const currentSource = fs.readFileSync(path.join(root, source), "utf8");
  const buildDir = path.join(root, "out/build-info");
  const candidates = fs
    .readdirSync(buildDir)
    .map((file) => ({ file, modified: fs.statSync(path.join(buildDir, file)).mtimeMs }))
    .sort((a, b) => b.modified - a.modified);
  const candidate = candidates.find(({ file }) => {
    const build = JSON.parse(fs.readFileSync(path.join(buildDir, file), "utf8"));
    return (
      build.input.sources[source]?.content === currentSource &&
      build.input.settings.optimizer.enabled &&
      build.output.contracts?.[source]?.YBoldYieldVault &&
      build.output.contracts?.["tests/mocks/YBoldYieldVaultV2Mock.sol"]?.YBoldYieldVaultV2Mock
    );
  });
  if (!candidate) throw new Error("Fresh optimized compiler build info missing");
  const build = JSON.parse(fs.readFileSync(path.join(buildDir, candidate.file), "utf8"));
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "seba-ybold-upgrades-"));
  try {
    fs.copyFileSync(path.join(buildDir, candidate.file), path.join(temp, candidate.file));
    const report = await validateUpgradeSafety(temp, target);
    console.log(report.explain(false));
    if (!report.ok) throw new Error("OpenZeppelin implementation validation failed");

    const current = new UpgradeableContract(target, build.input, build.output, { kind: "uups" }, build.solcVersion);
    const v2 = new UpgradeableContract(v2Target, build.input, build.output, { kind: "uups" }, build.solcVersion);
    const baselineErrors = getStorageUpgradeErrors(baseline.layout, current.layout, { kind: "uups" });
    const v2Errors = getStorageUpgradeErrors(current.layout, v2.layout, { kind: "uups" });
    if (baselineErrors.length || v2Errors.length) {
      console.error(JSON.stringify({ baselineErrors, v2Errors }, null, 2));
      throw new Error("OpenZeppelin storage incompatibility detected");
    }
    // Positive-control failure: prove the checker rejects changing an existing slot.
    const incompatible = structuredClone(current.layout);
    incompatible.storage[0].slot = "1";
    if (getStorageUpgradeErrors(current.layout, incompatible, { kind: "uups" }).length === 0) {
      throw new Error("Storage checker failed its incompatible-slot control");
    }
    const runtime = build.output.contracts[source].YBoldYieldVault.evm.deployedBytecode.object;
    const runtimeBytes = runtime.replace(/^0x/, "").length / 2;
    if (runtimeBytes > 24_576) throw new Error(`EIP-170 exceeded: ${runtimeBytes}`);
    console.log(`PASS baseline ${baseline.referenceCommit} -> current (including ERC-7201 namespaces)`);
    console.log("PASS current -> append-only V2 fixture; incompatible-slot control rejected");
    console.log(`Runtime: ${runtimeBytes}/24576 bytes; compiler ${build.solcVersion}`);
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
