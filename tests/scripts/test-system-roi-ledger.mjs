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
run("tests/fixtures/system-roi-ledger/reviewed-positive.json", true);
run("tests/fixtures/system-roi-ledger/missing-provenance.json", false);
run("tests/fixtures/system-roi-ledger/false-precision.json", false);
run("tests/fixtures/system-roi-ledger/reviewed-missing-rationale.json", false);
run("tests/fixtures/system-roi-ledger/not-reviewed-service-decision.json", false);
run("tests/fixtures/system-roi-ledger/service-provenance-mismatch.json", false);
run("tests/fixtures/system-roi-ledger/system-provenance-mismatch.json", false);

const doc = readFileSync(resolve(root, "docs/system-roi-ledger.md"), "utf8");
const schema = JSON.parse(readFileSync(resolve(root, "docs/system-roi-ledger-v1.schema.json"), "utf8"));
if (schema.$id !== "https://grimnir.gille.ai/contracts/system-roi-ledger/v1/schema.json") {
  throw new Error("ledger schema must use the public Grimnir contract identifier");
}
if (!schema.properties.period.oneOf.some((branch) => branch.const === "YYYY-MM")) {
  throw new Error("schema must accept the shipped YYYY-MM template placeholder");
}
for (const required of ["unknown", "estimate", "measured", "provenance", "keep", "fix", "cut", "revisit"]) {
  if (!doc.includes(required)) throw new Error(`ledger guide omits ${required}`);
}
console.log("PASS: system ROI ledger template and evidence guards");
