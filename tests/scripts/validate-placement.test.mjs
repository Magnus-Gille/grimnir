import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const validator = path.join(root, "scripts", "validate-placement.js");
const fixtures = path.join(root, "tests", "fixtures", "placement-validation");
const require = createRequire(import.meta.url);
const schemaSubset = require(path.join(root, "scripts", "lib", "json-schema-subset.js"));
const now = "2026-07-23T10:15:00Z";
const run = (registry, observation) => JSON.parse(execFileSync(process.execPath, [validator,
  "--registry", registry, "--observation", observation, "--now", now], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }));
const canonical = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value !== null && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};
const evidenceDigest = (record) => {
  const unsigned = structuredClone(record);
  delete unsigned.evidence.digest;
  return `sha256:${crypto.createHash("sha256").update(canonical(unsigned)).digest("hex")}`;
};
const seal = (observation) => {
  for (const node of observation.node_capabilities) node.evidence.digest = evidenceDigest(node);
  observation.evidence.digest = evidenceDigest(observation);
  return observation;
};
const fixture = (name) => JSON.parse(fs.readFileSync(path.join(fixtures, name), "utf8"));
const writeFixture = (directory, name, value) => {
  const target = path.join(directory, name);
  fs.writeFileSync(target, JSON.stringify(value));
  return target;
};

const current = run(path.join(root, "services.json"), path.join(fixtures, "current.json"));
assert.equal(current.compliant, true, "captured current huginmunin/nas/m5 fixture is compliant");
assert.deepEqual(current.drift, [], "current fixture has no desired-vs-observed drift");
assert.deepEqual(current.states.map((state) => state.workload_id), [...current.states.map((state) => state.workload_id)].sort((a, b) => a.localeCompare(b, "en", { numeric: true })), "states have stable natural ordering");
assert.ok(current.states.every((state) => Object.hasOwn(state, "declared") && Object.hasOwn(state, "deployed") && Object.hasOwn(state, "running") && Object.hasOwn(state, "healthy")), "declared/deployed/running/healthy remain distinct");

const unsupportedSchema = JSON.parse(fs.readFileSync(path.join(root, "docs", "placement-validation-v1.schema.json"), "utf8"));
unsupportedSchema.unevaluatedProperties = false;
assert.throws(() => schemaSubset.createValidator({ rootName: "placement-validation-v1.schema.json", schemas: [{ name: "placement-validation-v1.schema.json", schema: unsupportedSchema }] }), /unsupported JSON Schema keyword/, "tracked schema drift outside the supported subset fails closed");
const unresolvedSchema = JSON.parse(fs.readFileSync(path.join(root, "docs", "placement-validation-v1.schema.json"), "utf8"));
const nodeSchema = JSON.parse(fs.readFileSync(path.join(root, "docs", "node-substrate-contract-v1.schema.json"), "utf8"));
unresolvedSchema.properties.node_capabilities.items.$ref = "missing-node-schema.json#/$defs/node-capability";
assert.throws(() => schemaSubset.createValidator({ rootName: "placement-validation-v1.schema.json", schemas: [{ name: "placement-validation-v1.schema.json", schema: unresolvedSchema }, { name: "node-substrate-contract-v1.schema.json", schema: nodeSchema }] }), /unresolved external schema ref/, "tracked schema reference drift fails closed before observation validation");
const oneOfWithSibling = schemaSubset.createValidator({
  rootName: "root.json",
  schemas: [{
    name: "root.json",
    schema: { type: "integer", minimum: 10, oneOf: [{ const: 5 }, { const: 10 }] }
  }]
});
assert.deepEqual(oneOfWithSibling.validate(5), ["$: minimum"], "oneOf is conjunctive with sibling constraints");
assert.throws(() => schemaSubset.createValidator({
  rootName: "schemas/root.json",
  schemas: [
    { name: "schemas/root.json", schema: { $ref: "renamed/node.json" } },
    { name: "contracts/node.json", schema: { type: "object" } }
  ]
}), /unresolved external schema ref/, "external refs cannot drift through a matching basename alias");
assert.deepEqual(schemaSubset.createValidator({
  rootName: "schemas/root.json",
  schemas: [
    { name: "schemas/root.json", schema: { $ref: "node.json" } },
    { name: "schemas/node.json", schema: { type: "object", required: ["node_id"] } }
  ]
}).validate({ node_id: "node-exact" }), [], "relative external refs resolve only to the exact registered path");

const proposed = run(path.join(fixtures, "hugin-to-m5-services.json"), path.join(fixtures, "hugin-to-m5.json"));
assert.equal(proposed.compliant, true, "proposed Hugin-to-M5 placement can be evaluated without live access");

const drifted = run(path.join(root, "services.json"), path.join(fixtures, "drift.json"));
assert.equal(drifted.compliant, false, "drift fixture fails closed");
assert.deepEqual([...new Set(drifted.drift.map((item) => item.category))], ["incompatible-capability", "extra-live-unit", "missing-live-unit", "missing-workload", "stale-evidence", "missing-evidence", "deployment-state", "running-state", "health-state"], "drift categories are separate and deterministic");
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

  const tampered = fixture("current.json");
  tampered.workloads[0].running = "stopped";
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "tampered.json", tampered)), /digest mismatch/, "top-level digest detects workload tampering");

  const nestedTamper = fixture("current.json");
  nestedTamper.node_capabilities[0].resources.cpu_cores = 8;
  nestedTamper.evidence.digest = evidenceDigest(nestedTamper);
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "nested-tamper.json", nestedTamper)), /node-capability\.evidence\.digest mismatch/, "nested digest detects node-capability tampering even when the top-level record is resealed");

  const wrongRequirement = fixture("current.json");
  wrongRequirement.capability_assessments[0].requirement_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
  seal(wrongRequirement);
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "wrong-requirement.json", wrongRequirement)), /requirement.*mismatch/, "assessment must match the registry-pinned requirement digest");

  const wrongProducer = fixture("current.json");
  wrongProducer.capability_assessments[0].requirement_producer = "other-producer";
  seal(wrongProducer);
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "wrong-producer.json", wrongProducer)), /requirement.*mismatch/, "assessment must match the registry-pinned requirement producer");

  const staleNested = fixture("current.json");
  staleNested.node_capabilities[0].valid_until = "2026-07-23T10:10:00Z";
  seal(staleNested);
  const staleResult = run(path.join(root, "services.json"), writeFixture(tmp, "stale-nested.json", staleNested));
  assert.ok(staleResult.drift.some((item) => item.category === "stale-evidence" && item.node_id === "node-huginmunin"), "stale nested evidence fails closed as deterministic drift");

  const futureTop = fixture("current.json");
  futureTop.observed_at = "2026-07-23T10:16:00Z";
  futureTop.evidence.observed_at = futureTop.observed_at;
  for (const node of futureTop.node_capabilities) {
    node.observed_at = futureTop.observed_at;
    node.evidence.observed_at = futureTop.observed_at;
  }
  seal(futureTop);
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "future-top.json", futureTop)), /observation\.observed_at.*--now/, "top-level evidence cannot be observed after the evaluation instant");

  const futureNested = fixture("current.json");
  futureNested.node_capabilities[0].observed_at = "2026-07-23T10:16:00Z";
  futureNested.node_capabilities[0].evidence.observed_at = "2026-07-23T10:16:00Z";
  seal(futureNested);
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "future-nested.json", futureNested)), /node-capability\.observed_at.*--now/, "nested node evidence cannot be observed after the evaluation instant");

  const desiredRegistry = JSON.parse(fs.readFileSync(path.join(root, "services.json"), "utf8"));
  const invalidDesiredCases = [
    ["invalid-deploy", (data) => { data.components[0].deploy = "true"; }, /components\[0\]\.deploy must be boolean/],
    ["invalid-state", (data) => { data.components[0].desired_runtime_state = "running"; }, /components\[0\]\.desired_runtime_state is invalid/],
    ["invalid-port", (data) => { data.components[0].port = 70000; }, /components\[0\]\.port/],
    ["hugin-port-collision", (data) => {
      data.components.find((component) => component.name === "hugin").port = 3030;
    }, /duplicate desired port 3030.*munin-memory.*hugin/],
    ["duplicate-node", (data) => { data.nodes[1].node_id = data.nodes[0].node_id; }, /duplicate desired node_id/],
    ["duplicate-workload", (data) => { data.components[1].workload_id = data.components[0].workload_id; }, /duplicate desired workload_id/],
    ["unknown-target", (data) => { data.components[0].target_node_id = "node-unknown"; }, /target_node_id.*registered node/],
    ["host-target-mismatch", (data) => { data.components[0].host = "elsewhere.example"; }, /host.*target node.*disagree/],
    ["invalid-unit-type", (data) => { data.components[0].systemd_units[0].type = "socket"; }, /systemd_units\[0\]\.type is invalid/],
    ["duplicate-unit", (data) => { data.components[1].systemd_units.push(structuredClone(data.components[1].systemd_units[0])); }, /duplicate desired unit/],
    ["invalid-contract-producer", (data) => { data.components[0].workload_contract.producer = "other-owner"; }, /workload_contract\.producer must equal repo/]
  ];
  for (const [name, mutate, expected] of invalidDesiredCases) {
    const invalidRegistry = structuredClone(desiredRegistry);
    mutate(invalidRegistry);
    assert.throws(() => run(writeFixture(tmp, `${name}-registry.json`, invalidRegistry), path.join(fixtures, "current.json")), expected, `desired registry rejects ${name} before reconciliation`);
  }

  const missingUnit = fixture("current.json");
  const huginObservation = missingUnit.workloads.find((workload) => workload.workload_id === "workload-hugin");
  huginObservation.units = huginObservation.units.filter((unit) => unit !== "hugin-daily-analysis");
  seal(missingUnit);
  const missingUnitResult = run(path.join(root, "services.json"), writeFixture(tmp, "missing-unit.json", missingUnit));
  assert.ok(missingUnitResult.drift.some((item) => item.category === "missing-live-unit" && item.workload_id === "workload-hugin" && item.unit_id === "hugin-daily-analysis"), "declared units absent from observation are explicit symmetric drift");

  const unknownNode = fixture("current.json");
  unknownNode.workloads[0].node_id = "node-unknown";
  seal(unknownNode);
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "unknown-node.json", unknownNode)), /unknown observed node/, "workload observations must reference an observed node");

  const unknownAssessmentNode = fixture("current.json");
  unknownAssessmentNode.capability_assessments[0].node_id = "node-unknown";
  seal(unknownAssessmentNode);
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "unknown-assessment-node.json", unknownAssessmentNode)), /unknown observed node/, "capability assessments must reference an observed node");

  const outsideInterval = fixture("current.json");
  outsideInterval.node_capabilities[0].observed_at = "2026-07-23T09:59:59Z";
  outsideInterval.node_capabilities[0].evidence.observed_at = "2026-07-23T09:59:59Z";
  seal(outsideInterval);
  assert.throws(() => run(path.join(root, "services.json"), writeFixture(tmp, "outside-interval.json", outsideInterval)), /interval falls outside/, "nested node evidence must fall inside the top-level observation interval");

  const extra = fixture("current.json");
  extra.workloads.push({ workload_id: "workload-extra-2", node_id: "node-huginmunin", deployed: "deployed", running: "running", healthy: "healthy", units: ["extra-10", "extra-2"] });
  seal(extra);
  const extraResult = run(path.join(root, "services.json"), writeFixture(tmp, "extra.json", extra));
  assert.ok(extraResult.drift.some((item) => item.category === "extra-workload" && item.workload_id === "workload-extra-2"), "wholly extra workload is deterministic drift");
  assert.deepEqual(extraResult.drift.filter((item) => item.workload_id === "workload-extra-2" && item.category === "extra-live-unit").map((item) => item.unit_id), ["extra-2", "extra-10"], "units from wholly extra workloads are numeric-sorted drift");

  const extraNodes = fixture("current.json");
  for (const suffix of ["10", "2", "9007199254740992", "09007199254740993"]) {
    const node = structuredClone(extraNodes.node_capabilities[0]);
    node.node_id = `node-extra-${suffix}`;
    node.evidence.evidence_id = `evidence-extra-${suffix}`;
    extraNodes.node_capabilities.push(node);
  }
  extraNodes.workloads.push({ workload_id: "workload-extra-node", node_id: "node-extra-2", deployed: "deployed", running: "running", healthy: "healthy", units: ["extra-node-unit"] });
  seal(extraNodes);
  const extraNodeResult = run(path.join(root, "services.json"), writeFixture(tmp, "extra-nodes.json", extraNodes));
  assert.deepEqual(extraNodeResult.drift.filter((item) => item.category === "extra-node").map((item) => item.node_id), ["node-extra-2", "node-extra-10", "node-extra-9007199254740992", "node-extra-09007199254740993"], "wholly extra nodes are arbitrary-precision numeric-sorted drift");
  assert.ok(extraNodeResult.drift.some((item) => item.category === "extra-workload" && item.workload_id === "workload-extra-node" && item.node_id === "node-extra-2"), "workload on an undeclared node remains explicit drift");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log("Placement validation v1 fixtures and fail-closed drift categories validated.");
