#!/usr/bin/env node
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { keccak256 } = require("ethers");
const { getStorageUpgradeErrors } = require("@openzeppelin/upgrades-core");
const names = [
  "YieldManagerV2",
  "RethSupporterVault",
  "YsyBoldSupporterVault",
  "SebaV2Executor",
  "LegacyProtocolPrincipalHandoff",
  "LegacyIntakeStopper",
];
const write = process.argv.includes("--write-layouts");
const snapshots = path.resolve("storage-layout/v2");
const enums = new Map();
const indexEnums = (node) => {
  if (!node || typeof node !== "object") return;
  if (node.nodeType === "EnumDefinition")
    enums.set(
      `enum ${node.canonicalName}`,
      node.members.map((m) => m.name),
    );
  for (const value of Object.values(node))
    if (Array.isArray(value)) value.forEach(indexEnums);
    else if (value && typeof value === "object") indexEnums(value);
};
indexEnums(JSON.parse(fs.readFileSync("out/IV2SupporterVault.sol/IV2SupporterVault.json", "utf8")).ast);
for (const name of names) {
  const artifact = JSON.parse(fs.readFileSync(`out/${name}.sol/${name}.json`, "utf8"));
  const runtime = (artifact.deployedBytecode.object.length - 2) / 2;
  const init = (artifact.bytecode.object.length - 2) / 2;
  if (runtime === 0 || runtime > 24_576 || init > 49_152)
    throw new Error(`${name} violates production EVM size limits (${runtime}/${init})`);
  console.log(`${name}: runtime ${runtime}/24576, initcode ${init}/49152`);
  if (!["YieldManagerV2", "RethSupporterVault", "YsyBoldSupporterVault"].includes(name)) continue;
  const layout = artifact.storageLayout;
  // Raw solc storageLayout omits enum members. Include their AST semantics; never waive custom-type checks.
  for (const [id, type] of Object.entries(layout.types))
    if (id.startsWith("t_enum(")) {
      if (!enums.has(type.label)) throw new Error(`Unresolved enum ${type.label}`);
      type.members = enums.get(type.label);
    }
  if (getStorageUpgradeErrors(layout, layout).length) throw new Error("Identical-layout positive control failed");
  const corrupted = structuredClone(layout);
  corrupted.storage[0].slot = "999";
  if (!getStorageUpgradeErrors(layout, corrupted).length)
    throw new Error("Layout corruption negative control was not detected");
  const implementationSlot = BigInt("0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");
  if (layout.storage.some((v) => BigInt(v.slot) === implementationSlot)) throw new Error("EIP-1967 collision");
  // Compiler AST/type IDs change after unrelated tests are added. Compare actual storage semantics instead.
  const expand = (id) => {
    const t = layout.types[id];
    if (!t) throw new Error(`Missing type ${id}`);
    return {
      encoding: t.encoding,
      label: t.label,
      numberOfBytes: t.numberOfBytes,
      ...(t.key ? { key: expand(t.key) } : {}),
      ...(t.value ? { value: expand(t.value) } : {}),
      ...(t.base ? { base: expand(t.base) } : {}),
      ...(t.members
        ? {
            members: t.members.map((m) =>
              typeof m === "string" ? m : { label: m.label, slot: m.slot, offset: m.offset, type: expand(m.type) },
            ),
          }
        : {}),
    };
  };
  const normalized = {
    contract: name,
    storage: layout.storage.map((v) => ({ label: v.label, slot: v.slot, offset: v.offset, type: expand(v.type) })),
  };
  const canonical = JSON.stringify(normalized, null, 2) + "\n";
  const file = path.join(snapshots, `${name}.json`);
  if (write) {
    fs.mkdirSync(snapshots, { recursive: true });
    fs.writeFileSync(file, canonical);
  } else if (fs.readFileSync(file, "utf8") !== canonical)
    throw new Error(`${name} storage snapshot changed: review compatibility before updating`);
  console.log(`${name}: layout commitment ${keccak256(Buffer.from(canonical))}`);
}
