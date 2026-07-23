import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const validator = path.join(root, "scripts", "validate-placement.js");
const fixtures = path.join(root, "tests", "fixtures", "placement-validation");
const now = "2026-07-23T10:15:00Z";
const run = (registry, observation) => JSON.parse(execFileSync(process.execPath, [validator,
  "--registry", registry, "--observation", observation, "--now", now], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }));

const current = run(path.join(root, "services.json"), path.join(fixtures, "current.json"));
assert.equal(current.compliant, true, "captured current huginmunin/nas/m5 fixture is compliant");
assert.deepEqual(current.drift, [], "current fixture has no desired-vs-observed drift");
assert.deepEqual(current.states.map((state) => state.workload_id), [...current.states.map((state) => state.workload_id)].sort((a, b) => a.localeCompare(b, "en", { numeric: true })), "states have stable natural ordering");
assert.ok(current.states.every((state) => Object.hasOwn(state, "declared") && Object.hasOwn(state, "deployed") && Object.hasOwn(state, "running") && Object.hasOwn(state, "healthy")), "declared/deployed/running/healthy remain distinct");

const proposed = run(path.join(fixtures, "hugin-to-m5-services.json"), path.join(fixtures, "hugin-to-m5.json"));
assert.equal(proposed.compliant, true, "proposed Hugin-to-M5 placement can be evaluated without live access");

const drifted = run(path.join(root, "services.json"), path.join(fixtures, "drift.json"));
assert.equal(drifted.compliant, false, "drift fixture fails closed");
assert.deepEqual([...new Set(drifted.drift.map((item) => item.category))], ["incompatible-capability", "extra-live-unit", "missing-workload", "stale-evidence", "missing-evidence", "deployment-state", "running-state", "health-state"], "drift categories are separate and deterministic");
assert.deepEqual(drifted.drift.filter((item) => item.category === "extra-live-unit").map((item) => item.unit_id), ["hugin-2", "hugin-10"], "numeric identifiers sort numerically");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "grimnir-placement-"));
try {
  const missing = path.join(tmp, "missing.json");
  fs.writeFileSync(missing, JSON.stringify({ schema_version: "v1", kind: "brokkr-placement-observation" }));
  assert.throws(() => run(path.join(root, "services.json"), missing), /validation FAILED/, "malformed or missing evidence cannot be compliant");
  const malformedNode = JSON.parse(fs.readFileSync(path.join(fixtures, "current.json"), "utf8"));
  malformedNode.node_capabilities[0].unexpected_decision_field = true;
  const malformedNodePath = path.join(tmp, "malformed-node.json");
  fs.writeFileSync(malformedNodePath, JSON.stringify(malformedNode));
  assert.throws(() => run(path.join(root, "services.json"), malformedNodePath), /validation FAILED/, "node capability must match the exact v1 schema");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log("Placement validation v1 fixtures and fail-closed drift categories validated.");
