import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const schema = JSON.parse(fs.readFileSync(path.join(root, "docs/learning-task-contract-v1.schema.json"), "utf8"));
const positive = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/positive.json"), "utf8"));
const positiveErased = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/positive-erased.json"), "utf8"));
const negative = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/negative.json"), "utf8"));

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function resolveRef(ref) {
  assert.match(ref, /^#\//, `only local schema refs are supported: ${ref}`);
  return ref.slice(2).split("/").reduce((value, token) => value[token.replaceAll("~1", "/").replaceAll("~0", "~")], schema);
}

function typeMatches(type, value) {
  switch (type) {
    case "object": return value !== null && typeof value === "object" && !Array.isArray(value);
    case "array": return Array.isArray(value);
    case "string": return typeof value === "string";
    case "integer": return Number.isInteger(value);
    case "boolean": return typeof value === "boolean";
    case "null": return value === null;
    default: throw new Error(`unsupported schema type ${type}`);
  }
}

function validateNode(node, value, at = "$") {
  if (node === true) return [];
  if (node === false) return [`${at}: field is forbidden for this record_kind`];
  if (node.$ref) return validateNode(resolveRef(node.$ref), value, at);

  const errors = [];
  if (node.allOf) {
    for (const branch of node.allOf) errors.push(...validateNode(branch, value, at));
  }
  if (node.oneOf) {
    const attempts = node.oneOf.map((branch) => validateNode(branch, value, at));
    const passing = attempts.filter((result) => result.length === 0);
    if (passing.length !== 1) {
      errors.push(`${at}: expected exactly one schema branch; ${attempts.flat().join("; ")}`);
    }
    return errors;
  }
  if (Object.hasOwn(node, "const") && canonical(value) !== canonical(node.const)) {
    errors.push(`${at}: expected constant ${JSON.stringify(node.const)}`);
  }
  if (node.enum && !node.enum.some((candidate) => canonical(candidate) === canonical(value))) {
    errors.push(`${at}: value ${JSON.stringify(value)} is outside enum ${node.enum.join("|")}`);
  }
  if (node.type && !typeMatches(node.type, value)) {
    errors.push(`${at}: expected ${node.type}`);
    return errors;
  }
  if (typeof value === "string") {
    if (node.minLength !== undefined && value.length < node.minLength) errors.push(`${at}: shorter than minLength ${node.minLength}`);
    if (node.pattern && !(new RegExp(node.pattern).test(value))) errors.push(`${at}: does not match ${node.pattern}`);
    if (node.format === "date-time" && (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value) || Number.isNaN(Date.parse(value)))) {
      errors.push(`${at}: invalid RFC 3339 UTC date-time`);
    }
  }
  if (typeof value === "number" && node.minimum !== undefined && value < node.minimum) {
    errors.push(`${at}: below minimum ${node.minimum}`);
  }
  if (Array.isArray(value)) {
    if (node.minItems !== undefined && value.length < node.minItems) errors.push(`${at}: fewer than ${node.minItems} items`);
    if (node.uniqueItems) {
      const seen = new Set();
      value.forEach((item, index) => {
        const key = canonical(item);
        if (seen.has(key)) errors.push(`${at}[${index}]: duplicate array item`);
        seen.add(key);
      });
    }
    if (node.items) value.forEach((item, index) => errors.push(...validateNode(node.items, item, `${at}[${index}]`)));
  }
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    for (const required of node.required ?? []) {
      if (!Object.hasOwn(value, required)) errors.push(`${at}.${required}: required property missing`);
    }
    for (const [key, child] of Object.entries(node.properties ?? {})) {
      if (Object.hasOwn(value, key)) errors.push(...validateNode(child, value[key], `${at}.${key}`));
    }
    if (node.additionalProperties === false) {
      for (const key of Object.keys(value)) {
        if (!Object.hasOwn(node.properties ?? {}, key)) errors.push(`${at}: additional property ${key}`);
      }
    }
  }
  return errors;
}

function isUnknown(value) {
  return value && typeof value === "object" && value.value === null && typeof value.unknown_reason === "string";
}

function pointer(record, jsonPointer) {
  return jsonPointer.slice(1).split("/").reduce((value, token) => value?.[token.replaceAll("~1", "/").replaceAll("~0", "~")], record);
}

function expectedGovernanceRefs(record) {
  const refs = new Set([`source:${record.task.origin_component}:${record.task.source.id}`, "fingerprint:raw"]);
  const prompts = record.execution.prompt_identity;
  if (!isUnknown(prompts.hugin_rendered) || ["erased", "expired", "redacted"].includes(prompts.hugin_rendered.unknown_reason)) refs.add("fingerprint:hugin-rendered");
  if (!isUnknown(prompts.gateway_rendered) || ["erased", "expired", "redacted"].includes(prompts.gateway_rendered.unknown_reason)) refs.add("fingerprint:gateway-rendered");
  for (const artifact of record.artifacts.items) refs.add(artifact.ref);
  const changedFilesRef = record.artifacts.repository?.changed_files_ref;
  if (typeof changedFilesRef === "string") refs.add(changedFilesRef);
  return [...refs];
}

function effectiveGovernance(record) {
  const policies = record.governance.policies;
  const sensitivityRank = { public: 0, internal: 1, private: 2 };
  const erasureRank = { active: 0, requested: 1, expired: 2, erased: 3 };
  const sensitivity = policies.reduce((strictest, policy) => sensitivityRank[policy.sensitivity] > sensitivityRank[strictest] ? policy.sensitivity : strictest, "public");
  const allowedUses = policies.slice(1).reduce(
    (intersection, policy) => intersection.filter((use) => policy.allowed_uses.includes(use)),
    [...policies[0].allowed_uses],
  ).sort();
  const expiries = policies.map((policy) => policy.retention.expires_at).filter((value) => typeof value === "string").sort();
  const expiresAt = expiries[0] ?? { value: null, unknown_reason: "not-applicable" };
  const erasureState = policies.reduce((strictest, policy) => erasureRank[policy.erasure.state] > erasureRank[strictest] ? policy.erasure.state : strictest, "active");
  return { sensitivity, allowedUses, expiresAt, erasureState };
}

function validateSemantics(record) {
  const errors = [];
  if (record.lifecycle_state === "content-removed-tombstone") {
    if (Date.parse(record.recorded_at) < Date.parse(record.tombstone.effective_at)) {
      errors.push("tombstone recorded_at precedes effective_at");
    }
    const counterOwners = {
      "hugin-capture-denominator": "hugin",
      "hugin-m5-join-denominator": "hugin",
      "direct-m5-exposure-denominator": "gille-inference",
      "evaluation-candidate-denominator": "hugin",
    };
    const counterPeriods = new Set();
    for (const entry of record.tombstone.counter_audit) {
      if (counterOwners[entry.counter] !== record.producer.component) {
        errors.push(`producer ${record.producer.component} does not own counter ${entry.counter}`);
      }
      const key = `${entry.counter}|${entry.period_utc}`;
      if (counterPeriods.has(key)) errors.push(`duplicate counter audit key ${key}`);
      counterPeriods.add(key);
    }
    return errors;
  }

  if (record.task.origin_component !== record.task.source.component) {
    errors.push("task origin_component must equal task.source.component");
  }
  if (Date.parse(record.task.source.accepted_at) < Date.parse(record.task.source.created_at)) {
    errors.push("task source accepted_at precedes created_at");
  }
  if (!isUnknown(record.execution.ended_at) && Date.parse(record.execution.ended_at) < Date.parse(record.execution.started_at)) {
    errors.push("execution ended_at precedes started_at");
  }

  const policyRefs = record.governance.policies.map((policy) => policy.subject_ref);
  if (new Set(policyRefs).size !== policyRefs.length) errors.push("duplicate governance subject_ref");
  for (const ref of expectedGovernanceRefs(record)) {
    if (!policyRefs.includes(ref)) errors.push(`missing governance policy for ${ref}`);
  }

  const computed = effectiveGovernance(record);
  const declared = record.governance.effective;
  if (declared.sensitivity !== computed.sensitivity) errors.push(`effective sensitivity ${declared.sensitivity} does not equal strictest ${computed.sensitivity}`);
  if (canonical([...declared.allowed_uses].sort()) !== canonical(computed.allowedUses)) errors.push("effective allowed_uses is not the policy intersection");
  if (canonical(declared.expires_at) !== canonical(computed.expiresAt)) errors.push("effective expires_at is not the earliest policy expiry");
  if (declared.erasure_state !== computed.erasureState) errors.push("effective erasure_state is not the strictest policy state");
  if (canonical([...declared.derived_from_subject_refs].sort()) !== canonical([...policyRefs].sort())) errors.push("effective derived_from_subject_refs does not name every policy");

  for (const policy of record.governance.policies) {
    if (["erased", "expired"].includes(policy.erasure.state) && policy.erasure.digest_disposition !== "removed") {
      errors.push(`policy ${policy.subject_ref} retains digest after ${policy.erasure.state}`);
    }
    if (["erased", "expired"].includes(policy.erasure.state) && isUnknown(policy.erasure.effective_at)) {
      errors.push(`policy ${policy.subject_ref} lacks erasure/expiry effective_at`);
    }
  }
  if (["erased", "expired"].includes(declared.erasure_state)) {
    errors.push("erased/expired content MUST use reduced tombstone projection");
  }

  for (const namespace of Object.keys(record.extensions)) {
    if (namespace !== record.producer.component) errors.push(`extension namespace ${namespace} is not owned by producer ${record.producer.component}`);
  }

  if (record.record_kind === "inference-exposure" && record.exposure.state === "unseen-covered" && !record.exposure.coverage.complete) {
    errors.push("unseen-covered exposure requires complete coverage");
  }
  if (record.record_kind === "capability-evidence" && record.capability.verifier.kind === "advisory-judge" && record.capability.routing_effect !== "none-shadow") {
    errors.push("advisory judge cannot affect routing");
  }
  return errors;
}

function joinedIdentityErrors(records) {
  const errors = [];
  const groups = new Map();
  for (const record of records) {
    if (record.lifecycle_state !== "active" || record.task.origin_component !== "hugin") continue;
    const key = `${record.task.instance_id}|${record.execution.attempt_id}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(record);
  }

  function compareKnown(left, right, at) {
    if (isUnknown(left) || isUnknown(right)) return;
    if (left !== null && right !== null && typeof left === "object" && typeof right === "object") {
      for (const key of new Set([...Object.keys(left), ...Object.keys(right)])) compareKnown(left[key], right[key], `${at}.${key}`);
      return;
    }
    if (canonical(left) !== canonical(right)) errors.push(`joined identity mismatch at ${at}`);
  }

  for (const group of groups.values()) {
    for (let index = 1; index < group.length; index += 1) {
      const reference = group[0];
      const candidate = group[index];
      compareKnown(reference.task.raw_fingerprint, candidate.task.raw_fingerprint, "task.raw_fingerprint");
      compareKnown(reference.execution.prompt_identity, candidate.execution.prompt_identity, "execution.prompt_identity");
      compareKnown(reference.execution.routing, candidate.execution.routing, "execution.routing");
      compareKnown(reference.execution.serving, candidate.execution.serving, "execution.serving");
    }
  }
  return [...new Set(errors)];
}

function conflictKey(record, fields) {
  return fields.map((field) => canonical(pointer(record, field))).join("|");
}

function validateDataset(records) {
  const errors = [];
  for (const [index, record] of records.entries()) {
    const schemaErrors = validateNode(schema, record);
    errors.push(...schemaErrors.map((error) => `record ${index}: ${error}`));
    if (schemaErrors.length === 0) errors.push(...validateSemantics(record).map((error) => `record ${index}: ${error}`));
  }
  if (errors.length > 0) return errors;

  errors.push(...joinedIdentityErrors(records));
  const activeIds = new Set(records.filter((record) => record.lifecycle_state === "active").map((record) => record.record_id));
  for (const record of records) {
    if (record.lifecycle_state === "content-removed-tombstone" && activeIds.has(record.tombstone.superseded_record_id)) {
      errors.push(`tombstone supersedes content-bearing record still present: ${record.tombstone.superseded_record_id}`);
    }
  }
  if (errors.length > 0) return errors;

  const keyDefinitions = schema["x-grimnir-conflict-keys"];
  for (const [name, fields] of Object.entries(keyDefinitions)) {
    const seen = new Map();
    for (const record of records) {
      if (name !== "record" && (record.record_kind !== name || record.lifecycle_state !== "active")) continue;
      const key = conflictKey(record, fields);
      const body = canonical(record);
      if (seen.has(key) && seen.get(key) !== body) errors.push(`conflicting ${name} key ${key}`);
      else seen.set(key, body);
    }
  }
  return errors;
}

function mutate(record, mutation) {
  const tokens = mutation.path.slice(1).split("/").map((token) => token.replaceAll("~1", "/").replaceAll("~0", "~"));
  const key = tokens.pop();
  const parent = tokens.reduce((value, token) => value[token], record);
  if (mutation.op === "set") parent[key] = structuredClone(mutation.value);
  else if (mutation.op === "delete") delete parent[key];
  else if (mutation.op === "delete-array-item") parent[key].splice(mutation.index, 1);
  else throw new Error(`unsupported fixture mutation ${mutation.op}`);
}

assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
assert.deepEqual(schema.oneOf.map((entry) => entry.$ref), [
  "#/$defs/taskOutcomeRecord",
  "#/$defs/inferenceExposureRecord",
  "#/$defs/capabilityEvidenceRecord",
  "#/$defs/experimentObservationRecord",
]);
assert.deepEqual(Object.keys(schema["x-grimnir-conflict-keys"]), ["record", "task-outcome", "inference-exposure", "capability-evidence", "experiment-observation"]);
const ownerMap = schema["x-grimnir-field-owners"];
for (const requiredOwnerGroup of ["/tombstone/**", "/exposure/**", "/capability/**", "/experiment/**", "/extensions/{producer.component}/**"]) {
  assert.equal(typeof ownerMap[requiredOwnerGroup], "string", `machine ownership map must cover ${requiredOwnerGroup}`);
}

const positiveErrors = validateDataset(positive);
assert.deepEqual(positiveErrors, [], `positive fixtures must validate:\n${positiveErrors.join("\n")}`);
assert.deepEqual(new Set(positive.map((record) => record.record_kind)), new Set(["task-outcome", "inference-exposure", "capability-evidence", "experiment-observation"]));
assert.equal(positive.some((record) => record.task.origin_component === "gille-inference"), true, "positive fixtures must cover direct gateway origin");
const joinedOutcome = positive.find((record) => record.record_kind === "task-outcome");
const joinedCapability = positive.find((record) => record.record_kind === "capability-evidence");
const joinedExposure = positive.find((record) => record.record_kind === "inference-exposure" && record.task.origin_component === "hugin");
assert.equal(joinedCapability.task.instance_id, joinedOutcome.task.instance_id, "positive fixtures must contain a joined Hugin task");
assert.equal(joinedCapability.execution.attempt_id, joinedOutcome.execution.attempt_id, "joined fixtures must bind the same attempt");
assert.equal(joinedExposure.task.instance_id, joinedOutcome.task.instance_id, "positive fixtures must contain gateway exposure for the joined Hugin task");
assert.equal(joinedExposure.execution.attempt_id, joinedOutcome.execution.attempt_id, "joined exposure must bind the same attempt");
for (const record of [joinedCapability, joinedExposure]) {
  for (const field of ["source", "task_type", "raw_fingerprint"]) assert.deepEqual(record.task[field], joinedOutcome.task[field], `joined task ${field} must match`);
  for (const field of ["prompt_identity", "routing", "serving"]) assert.deepEqual(record.execution[field], joinedOutcome.execution[field], `joined execution ${field} must match`);
}
const qualifiedUnknownJoin = structuredClone(joinedExposure);
qualifiedUnknownJoin.execution.prompt_identity.gateway_rendered = { value: null, unknown_reason: "not-observed" };
assert.deepEqual(validateDataset([joinedOutcome, qualifiedUnknownJoin]), [], "schema-qualified unknown may defer an explicitly nullable joined identity");

const erasedErrors = validateDataset([positiveErased]);
assert.deepEqual(erasedErrors, [], `erased tombstone fixture must validate:\n${erasedErrors.join("\n")}`);
assert.deepEqual(Object.keys(positiveErased).sort(), ["contract_version", "lifecycle_state", "producer", "record_id", "record_kind", "recorded_at", "schema_revision", "tombstone"].sort(), "tombstone must expose only its reduced envelope");
const noCounterTombstone = structuredClone(positiveErased);
noCounterTombstone.tombstone.counter_audit = [];
assert.deepEqual(validateDataset([noCounterTombstone]), [], "tombstone may omit counter adjustments rather than fabricate them");

for (const testCase of negative) {
  const first = structuredClone(testCase.from_erased ? positiveErased : positive[testCase.from_positive]);
  for (const mutation of testCase.mutations ?? []) mutate(first, mutation);
  const records = [first];
  if (testCase.second_record_mutations) {
    const second = structuredClone(testCase.second_from_erased ? positiveErased : positive[testCase.second_from_positive ?? testCase.from_positive]);
    for (const mutation of testCase.second_record_mutations) mutate(second, mutation);
    records.push(second);
  }
  const errors = validateDataset(records);
  assert.ok(errors.length > 0, `${testCase.name}: negative fixture unexpectedly passed`);
  assert.ok(errors.join("\n").includes(testCase.expected_error), `${testCase.name}: expected ${JSON.stringify(testCase.expected_error)} in:\n${errors.join("\n")}`);
}

console.log(`LearningTaskContract schema validation passed: ${positive.length + 1} positive records and ${negative.length} negative cases.`);
