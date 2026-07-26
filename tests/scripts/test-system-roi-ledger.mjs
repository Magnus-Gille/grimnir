#!/usr/bin/env node
// Regression guards for the evidence-honest monthly ROI ledger (grimnir#67).
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const run = (file, expectSuccess) => {
  const result = spawnSync("node", ["scripts/validate-system-roi-ledger.mjs", file], {
    cwd: root,
    encoding: "utf8",
  });
  if ((result.status === 0) !== expectSuccess) {
    throw new Error(`unexpected validation result for ${file}: ${result.stdout}${result.stderr}`);
  }
};

run("docs/system-roi-ledger-template.json", true);
run("tests/fixtures/system-roi-ledger/missing-provenance.json", false);
run("tests/fixtures/system-roi-ledger/false-precision.json", false);

const doc = readFileSync(resolve(root, "docs/system-roi-ledger.md"), "utf8");
for (const required of ["unknown", "estimate", "measured", "provenance", "keep", "fix", "cut", "revisit"]) {
  if (!doc.includes(required)) throw new Error(`ledger guide omits ${required}`);
}
console.log("PASS: system ROI ledger template and evidence guards");
