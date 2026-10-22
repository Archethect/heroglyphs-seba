#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const report = fs.readFileSync(process.argv[2] || "lcov.info", "utf8");
for (const file of ["src/YBoldYieldVault.sol", "src/YBoldConfigValidator.sol"]) {
  const record = report.split("end_of_record").find((block) => {
    const source = block.match(/^SF:(.+)$/m)?.[1];
    return source === file || source?.endsWith(`/${file}`);
  });
  if (!record) throw new Error(`Missing coverage record: ${file}`);
  for (const [found, hit] of [
    ["LF", "LH"],
    ["BRF", "BRH"],
    ["FNF", "FNH"],
  ]) {
    const total = Number(record.match(new RegExp(`^${found}:(\\d+)$`, "m"))?.[1]);
    const covered = Number(record.match(new RegExp(`^${hit}:(\\d+)$`, "m"))?.[1]);
    if (!Number.isSafeInteger(total) || total <= 0 || covered !== total) {
      throw new Error(`${file}: ${hit}/${found}=${covered}/${total}; 100% required`);
    }
  }
  console.log(`PASS 100% lines/branches/functions: ${file}`);
}
