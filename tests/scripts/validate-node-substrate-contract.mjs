import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const fixtureDir = path.join(root, "tests/fixtures/node-substrate-contract");
const read = (name) => JSON.parse(fs.readFileSync(path.join(fixtureDir, name), "utf8"));
const schema = JSON.parse(fs.readFileSync(path.join(root, "docs/node-substrate-contract-v1.schema.json"), "utf8"));
const positive = read("positive.json");
const partialDrain = read("partial-drain.json");
const partialSubstrate = read("partial-substrate.json");
const negative = read("negative.json");
const consumers = read("consumer-fixture-set.json");

const id = /^[a-z][a-z0-9-]{2,62}$/;
const digest = /^sha256:[a-f0-9]{64}$/;
const utc = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const fail = (message) => { throw new Error(message); };
const object = (value, label) => {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label} must be an object`);
};
const requireFields = (value, fields, label) => {
  object(value, label);
  for (const field of fields) if (!(field in value)) fail(`${label}.${field} is required`);
};
const rejectPrivate = (value, label = "$") => {
  if (typeof value === "string") {
    if (/(?:\b(?:10|127|192\.168)\.|\b172\.(?:1[6-9]|2\d|3[01])\.)|\/Users\/|\.ssh\/|wifi|ssid|password=|token=/i.test(value)) fail(`${label} contains private topology, path, Wi-Fi identity, or credential-like data`);
  } else if (Array.isArray(value)) value.forEach((item, index) => rejectPrivate(item, `${label}[${index}]`));
  else if (value && typeof value === "object") Object.entries(value).forEach(([key, child]) => rejectPrivate(child, `${label}.${key}`));
};
const exactKeys = (value, allowed, label) => {
  for (const key of Object.keys(value)) if (!allowed.includes(key)) fail(`${label}.${key} is not an allowed v1 field`);
};
function validateExtensions(extensions, label) {
  if (!Array.isArray(extensions)) fail(`${label}.extensions must be an array`);
  for (const extension of extensions) {
    requireFields(extension, ["id", "version", "decision_effect"], `${label}.extension`);
    if (!id.test(extension.id) || !/^v[1-9][0-9]*$/.test(extension.version)) fail(`${label}.extension has invalid identity`);
    if (extension.decision_effect !== "informational") fail(`${label}.extension may not silently affect a v1 decision`);
  }
}
function validateNode(record, now) {
  exactKeys(record, ["kind", "schema_version", "node_id", "observed_at", "valid_until", "evidence", "capability_status", "architecture", "resources", "uptime_class", "network_capabilities", "logical_storage", "service_manager", "deployment_mechanisms", "health_reporting", "extensions"], "node");
  requireFields(record, ["node_id", "observed_at", "valid_until", "evidence", "architecture", "resources", "network_capabilities", "extensions"], "node");
  if (!id.test(record.node_id) || !utc.test(record.observed_at) || !utc.test(record.valid_until)) fail("node has invalid identity or timestamp");
  if (Date.parse(record.valid_until) <= Date.parse(record.observed_at) || Date.parse(record.valid_until) <= now) fail("node observation is stale or invalid");
  requireFields(record.evidence, ["evidence_id", "producer", "observed_at", "digest"], "node.evidence");
  exactKeys(record.evidence, ["evidence_id", "producer", "observed_at", "digest"], "node.evidence");
  if (record.evidence.producer !== "brokkr" || !id.test(record.evidence.evidence_id) || !digest.test(record.evidence.digest)) fail("node evidence must be Brokkr-provenanced and digest-bound");
  if (!["arm64", "x86_64"].includes(record.architecture) || record.capability_status !== "known") fail("node cannot drive a placement with unknown or unsupported architecture");
  validateExtensions(record.extensions, "node");
}
function validateWorkload(record) {
  exactKeys(record, ["kind", "schema_version", "workload_id", "supported_architectures", "persistent_data", "ports", "units", "timers", "secrets_boundary", "dependencies", "backup_restore", "health", "hooks", "extensions"], "workload");
  requireFields(record, ["workload_id", "supported_architectures", "persistent_data", "secrets_boundary", "backup_restore", "hooks", "extensions"], "workload");
  if (!id.test(record.workload_id) || !Array.isArray(record.supported_architectures) || record.supported_architectures.length === 0) fail("workload must declare a stable identity and architecture support");
  if (["unknown", "not_applicable"].includes(record.persistent_data) || ["unknown", "not_applicable"].includes(record.secrets_boundary) || ["unknown", "not_applicable"].includes(record.backup_restore)) fail("workload unknown decision-driving requirements fail closed");
  const hooks = new Map(record.hooks.map((hook) => [hook.name, hook]));
  for (const required of ["preflight", "verify"]) if (!hooks.has(required) || hooks.get(required).mode !== "read_only") fail(`workload lacks read-only ${required} hook`);
  const drain = hooks.get("drain");
  if (drain) {
    if (drain.mode !== "mutating" || !["rollback", "compensate"].includes(drain.compensation_hook) || !hooks.has(drain.compensation_hook)) fail("mutating drain requires declared workload compensation");
  }
  for (const hook of record.hooks) if (!Array.isArray(hook.contract_versions) || !hook.contract_versions.includes("v1") || hook.idempotency_required !== true || !Number.isInteger(hook.deadline_seconds) || hook.deadline_seconds < 1) fail("hook lacks v1/idempotency/deadline contract");
  validateExtensions(record.extensions, "workload");
}
function validateLifecycle(record) {
  exactKeys(record, ["kind", "schema_version", "result_id", "attempt_id", "plan_id", "plan_digest", "desired_revision", "observation_evidence_id", "action", "deadline", "idempotency_key", "phase", "outcome", "drift", "hook_results", "substrate", "created_at", "extensions"], "lifecycle");
  requireFields(record, ["result_id", "attempt_id", "plan_id", "plan_digest", "desired_revision", "observation_evidence_id", "action", "deadline", "idempotency_key", "phase", "outcome", "drift", "hook_results", "substrate", "created_at", "extensions"], "lifecycle");
  for (const field of ["attempt_id", "plan_id", "observation_evidence_id", "idempotency_key"]) if (!id.test(record[field])) fail(`lifecycle ${field} must be stable`);
  for (const field of ["plan_digest", "desired_revision"]) if (!digest.test(record[field])) fail(`lifecycle ${field} must be a digest`);
  if (!utc.test(record.deadline)) fail("lifecycle requires an explicit deadline");
  for (const hook of record.hook_results) {
    exactKeys(hook, ["result_id", "hook", "attempt_id", "plan_id", "desired_revision", "observation_evidence_id", "action", "deadline", "idempotency_key", "outcome"], "hook_result");
    for (const field of ["attempt_id", "plan_id", "desired_revision", "observation_evidence_id", "action", "deadline", "idempotency_key"]) if (hook[field] !== record[field]) fail(`hook result is not bound to lifecycle ${field}`);
  }
  const outcomes = record.hook_results.map((hook) => hook.outcome);
  if (record.outcome === "promoted" && (record.drift !== "planned" && record.drift !== "none" || record.substrate.outcome !== "success" || !record.hook_results.some((hook) => hook.hook === "verify" && hook.outcome === "success"))) fail("promotion requires planned/no drift, successful substrate and verification");
  if (outcomes.includes("partial") && (record.outcome !== "blocked" || record.phase !== "compensate" || !record.hook_results.some((hook) => hook.hook === "compensate" || hook.hook === "rollback") || !record.hook_results.some((hook) => hook.hook === "verify" && hook.outcome === "success"))) fail("partial workload action must be blocked, compensated, and baseline-verified");
  if (!id.test(record.substrate.pre_state_evidence_id)) fail("substrate result must bind recorded Brokkr pre-state evidence");
  if (record.substrate.outcome === "partial" && (record.outcome !== "blocked" || record.phase !== "substrate_rollback" || record.substrate.rollback !== "verified")) fail("partial substrate action needs a verified Brokkr rollback");
  validateExtensions(record.extensions, "lifecycle");
}
function validateRecord(record, now = Date.parse("2026-07-23T10:15:00Z")) {
  requireFields(record, ["kind", "schema_version"], "record");
  if (record.schema_version !== "v1") fail("unsupported schema version fails closed");
  rejectPrivate(record);
  switch (record.kind) {
    case "node-capability": return validateNode(record, now);
    case "workload-requirement": return validateWorkload(record);
    case "placement-intent":
      exactKeys(record, ["kind", "schema_version", "placement_id", "workload_id", "target_node_id", "desired_revision", "created_at", "planned_drift", "extensions"], "placement");
      requireFields(record, ["placement_id", "workload_id", "target_node_id", "desired_revision", "planned_drift", "extensions"], "placement");
      if (![record.placement_id, record.workload_id, record.target_node_id].every((value) => id.test(value)) || !digest.test(record.desired_revision)) fail("placement must use stable identities and a desired revision");
      validateExtensions(record.extensions, "placement"); return;
    case "lifecycle-result": return validateLifecycle(record);
    default: fail("unknown record kind fails closed");
  }
}
const mustReject = (fn, label) => assert.throws(fn, undefined, label);

assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
assert.deepEqual(Object.keys(schema.$defs).filter((key) => ["node-capability", "workload-requirement", "placement-intent", "lifecycle-result"].includes(key)).sort(), ["lifecycle-result", "node-capability", "placement-intent", "workload-requirement"]);
assert.deepEqual(consumers.consumers.sort(), ["brokkr", "hugin", "mimir"]);
assert.deepEqual(consumers.fixtures.sort(), ["partial-drain.json", "partial-substrate.json", "positive.json"]);

for (const record of positive.records) validateRecord(record);
for (const record of partialDrain.records) validateRecord(record, Date.parse("2026-07-23T12:15:00Z"));
for (const record of partialSubstrate.records) validateRecord(record, Date.parse("2026-07-23T13:15:00Z"));

mustReject(() => validateRecord(negative.mixed_version), "mixed version");
mustReject(() => validateRecord(negative.stale_evidence), "stale evidence");
mustReject(() => validateWorkload(negative.missing_hook), "missing hook");
mustReject(() => validateLifecycle({ kind: "lifecycle-result", schema_version: "v1", result_id: "result-x", plan_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", desired_revision: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", observation_evidence_id: "obs-x", action: "relocate", deadline: "2026-07-23T12:30:00Z", phase: "verify", outcome: "blocked", drift: "planned", hook_results: [negative.replayed_result.hook_result], substrate: { outcome: "not_started", rollback: "not_needed" }, extensions: [], attempt_id: negative.replayed_result.attempt_id, plan_id: "plan-x", idempotency_key: negative.replayed_result.idempotency_key }), "replay/idempotency binding");
mustReject(() => { if (!negative.incompatible_placement.workload_supported_architectures.includes(negative.incompatible_placement.node_architecture)) fail("incompatible placement"); }, "incompatible placement");
mustReject(() => { if (negative.unexpected_drift.outcome === "promoted" && negative.unexpected_drift.drift === "unexpected") fail("unexpected drift cannot promote"); }, "unexpected drift");
mustReject(() => rejectPrivate(negative.privacy_adversarial), "privacy adversarial");

console.log("Node/substrate v1 schema and 10 fixture scenarios validated hermetically.");
