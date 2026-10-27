const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const names = [
  "NativeSupporterVault",
  "RethSupporterVault",
  "YsyBoldSupporterVault",
  "YieldManagerV2",
  "SebaV2Executor",
  "LegacyProtocolPrincipalHandoff",
  "LegacyIntakeStopper",
];
const record = (source, branches = 1) =>
  `SF:${source}\nLF:1\nLH:1\nBRF:${branches}\nBRH:${branches}\nFNF:1\nFNH:1\nend_of_record\n`;
const complete = () => names.map((n) => record(`src/v2/${n}.sol`, n === "LegacyIntakeStopper" ? 0 : 1)).join("");
function run(t, content, deployment = false) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "seba-coverage-test-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, "fixture.lcov");
  fs.writeFileSync(file, content);
  return spawnSync(
    process.execPath,
    [path.join(__dirname, "check-coverage.cjs"), file, ...(deployment ? ["--deployment"] : [])],
    { encoding: "utf8" },
  );
}
test("accepts complete seven-source coverage including branchless stopper", (t) => {
  assert.equal(run(t, complete()).status, 0);
});
test("rejects an uncovered line, branch or function", (t) => {
  for (const field of ["LH", "BRH", "FNH"])
    assert.notEqual(run(t, complete().replace(`${field}:1`, `${field}:0`)).status, 0);
});
test("rejects a missing source instead of excluding it", (t) => {
  assert.notEqual(
    run(
      t,
      names
        .slice(1)
        .map((n) => record(`src/v2/${n}.sol`))
        .join(""),
    ).status,
    0,
  );
});
test("deployment mode requires actual script coverage, not implementation coverage", (t) => {
  assert.equal(run(t, record("script/v2/DeploySebaV2.s.sol"), true).status, 0);
  assert.notEqual(run(t, complete(), true).status, 0);
});
