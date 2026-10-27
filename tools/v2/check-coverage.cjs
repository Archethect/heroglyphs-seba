#!/usr/bin/env node
"use strict";
const fs = require("node:fs");
const file = process.argv[2];
if (!file) throw new Error("Provide V2 unit LCOV file");
const deployment = process.argv.includes("--deployment");
const targets = deployment
  ? ["DeploySebaV2"]
  : [
      "NativeSupporterVault",
      "RethSupporterVault",
      "YsyBoldSupporterVault",
      "YieldManagerV2",
      "SebaV2Executor",
      "LegacyProtocolPrincipalHandoff",
      "LegacyIntakeStopper",
    ];
const records = fs.readFileSync(file, "utf8").split("end_of_record");
let failed = false;
for (const name of targets) {
  const source = deployment ? `script/v2/${name}.s.sol` : `src/v2/${name}.sol`;
  const record = records.find((x) => x.includes(`SF:${source}\n`));
  if (!record) throw new Error(`Missing ${name} coverage`);
  const get = (k) => Number(record.match(new RegExp(`^${k}:(\\d+)$`, "m"))?.[1] ?? 0);
  const result = {
    contract: name,
    lines: `${get("LH")}/${get("LF")}`,
    branches: `${get("BRH")}/${get("BRF")}`,
    functions: `${get("FNH")}/${get("FNF")}`,
  };
  console.log(JSON.stringify(result));
  if (!get("LF") || get("LH") !== get("LF") || get("BRH") !== get("BRF") || get("FNH") !== get("FNF")) failed = true;
}
if (failed) throw new Error("V2 coverage gate failed. Do not claim full coverage or hide exclusions.");
