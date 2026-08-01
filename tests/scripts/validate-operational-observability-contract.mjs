import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const fixturesDir = path.join(root, "tests/fixtures/operational-observability");
const read = (name) => JSON.parse(fs.readFileSync(path.join(fixturesDir, name), "utf8"));
const schema = JSON.parse(fs.readFileSync(path.join(root, "docs/operational-observability-v1.schema.json"), "utf8"));

const positive = read("positive.json");
const mixedVersion = read("mixed-version.json");
const staleMissingPartial = read("stale-missing-partial.json");
const negative = read("negative.json");

const SUPPORTED_MAJOR = 1;
const fail = (message) => { throw new Error(message); };
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const id = /^[a-z][a-z0-9-]{2,62}$/;
const digest = /^sha256:[a-f0-9]{64}$/;
const utc = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const durationPattern = /^P(?=\d|T\d)(?:(\d+)D)?(?:T(?=\d)(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/;
const safeToken = /^[A-Za-z0-9._:+-]{1,80}$/;
const opaqueRef = /^ref:[a-z][a-z0-9-]{2,120}$/;
const traceId = /^[a-f0-9]{32}$/;
const spanId = /^[a-f0-9]{16}$/;

const canonical = (value) => JSON.stringify(value, Object.keys(value ?? {}).sort());
const typeMatches = (type, value) => ({ object: plain(value), array: Array.isArray(value), string: typeof value === "string", integer: Number.isInteger(value), boolean: typeof value === "boolean", null: value === null })[type];
const realDateTime = (value) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/.exec(value);
  if (!match) return false;
  const instant = new Date(value);
  if (Number.isNaN(instant.getTime())) return false;
  const [, year, month, day, hour, minute, second] = match;
  return instant.getUTCFullYear() === Number(year) && instant.getUTCMonth() + 1 === Number(month) && instant.getUTCDate() === Number(day) && instant.getUTCHours() === Number(hour) && instant.getUTCMinutes() === Number(minute) && instant.getUTCSeconds() === Number(second);
};
const resolve = (ref) => {
  if (!ref.startsWith("#/")) fail(`unsupported external schema ref ${ref}`);
  return ref.slice(2).split("/").reduce((value, raw) => value?.[raw.replaceAll("~1", "/").replaceAll("~0", "~")], schema);
};
const keywordSet = new Set(["$schema", "$id", "$defs", "$ref", "title", "description", "oneOf", "const", "enum", "type", "minLength", "pattern", "format", "minimum", "maximum", "minItems", "uniqueItems", "items", "required", "properties", "additionalProperties"]);
function checkSchema(node, at = "$") {
  if (typeof node === "boolean") return;
  assert.ok(plain(node), `schema node must be an object at ${at}`);
  for (const key of Object.keys(node)) assert.ok(keywordSet.has(key), `unsupported JSON Schema keyword ${key} at ${at}`);
  if (node.$ref) {
    assert.ok(resolve(node.$ref), `unresolved ref ${node.$ref}`);
    assert.deepEqual(Object.keys(node).filter((key) => key !== "$ref" && !["title", "description"].includes(key)), [], `$ref siblings unsupported at ${at}`);
  }
  if (node.type) assert.ok(["object", "array", "string", "integer", "boolean", "null"].includes(node.type), `unsupported type at ${at}`);
  if (node.format) assert.equal(node.format, "date-time", `unsupported format at ${at}`);
  if (node.additionalProperties !== undefined) assert.equal(typeof node.additionalProperties, "boolean", `additionalProperties must be boolean at ${at}`);
  for (const [key, child] of Object.entries(node.properties ?? {})) checkSchema(child, `${at}.properties.${key}`);
  for (const [key, child] of Object.entries(node.$defs ?? {})) checkSchema(child, `${at}.$defs.${key}`);
  if (node.items) checkSchema(node.items, `${at}.items`);
  for (const [index, child] of (node.oneOf ?? []).entries()) checkSchema(child, `${at}.oneOf[${index}]`);
}
function schemaErrors(node, value, at = "$") {
  if (node === true) return [];
  if (node === false) return [`${at}: forbidden`];
  if (node.$ref) return schemaErrors(resolve(node.$ref), value, at);
  if (node.oneOf) {
    const attempts = node.oneOf.map((child) => schemaErrors(child, value, at));
    return attempts.filter((errors) => errors.length === 0).length === 1 ? [] : [`${at}: expected exactly one branch (${attempts.flat().join("; ")})`];
  }
  const errors = [];
  if (Object.hasOwn(node, "const") && canonical(value) !== canonical(node.const)) errors.push(`${at}: const mismatch`);
  if (node.enum && !node.enum.some((candidate) => canonical(candidate) === canonical(value))) errors.push(`${at}: enum mismatch`);
  if (node.type && !typeMatches(node.type, value)) return [...errors, `${at}: expected ${node.type}`];
  if (typeof value === "string") {
    if (node.minLength !== undefined && value.length < node.minLength) errors.push(`${at}: minLength`);
    if (node.pattern && !new RegExp(node.pattern).test(value)) errors.push(`${at}: pattern`);
    if (node.format === "date-time" && !utc.test(value)) errors.push(`${at}: date-time`);
  }
  if (typeof value === "number") {
    if (node.minimum !== undefined && value < node.minimum) errors.push(`${at}: minimum`);
    if (node.maximum !== undefined && value > node.maximum) errors.push(`${at}: maximum`);
  }
  if (Array.isArray(value)) {
    if (node.minItems !== undefined && value.length < node.minItems) errors.push(`${at}: minItems`);
    if (node.uniqueItems && new Set(value.map(canonical)).size !== value.length) errors.push(`${at}: duplicate items`);
    if (node.items) value.forEach((item, index) => errors.push(...schemaErrors(node.items, item, `${at}[${index}]`)));
  }
  if (plain(value)) {
    for (const field of node.required ?? []) if (!Object.hasOwn(value, field)) errors.push(`${at}.${field}: required`);
    for (const [field, child] of Object.entries(node.properties ?? {})) if (Object.hasOwn(value, field)) errors.push(...schemaErrors(child, value[field], `${at}.${field}`));
    if (node.additionalProperties === false) for (const field of Object.keys(value)) if (!Object.hasOwn(node.properties ?? {}, field)) errors.push(`${at}.${field}: additional property`);
  }
  return errors;
}
const schemaValid = (record, label) => assert.deepEqual(schemaErrors(schema, record), [], `${label} violates the normative v1 schema`);
const schemaInvalid = (record, label) => assert.notDeepEqual(schemaErrors(schema, record), [], `${label} must be rejected by the normative schema`);

const fields = (value, names, label) => {
  if (!plain(value)) fail(`${label} must be object`);
  for (const name of names) if (!Object.hasOwn(value, name)) fail(`${label}.${name} missing`);
};
const exact = (value, names, label) => {
  fields(value, names, label);
  for (const key of Object.keys(value)) if (!names.includes(key)) fail(`${label}.${key} is not a v1 field`);
};
function durationToMs(value) {
  const match = durationPattern.exec(value);
  if (!match) fail(`invalid duration ${value}`);
  const [, d, h, m, s] = match;
  return ((Number(d || 0) * 24 + Number(h || 0)) * 60 + Number(m || 0)) * 60000 + Number(s || 0) * 1000;
}
function parseVersion(value, label) {
  const match = /^v([1-9][0-9]*)\.(\d+)$/.exec(value);
  if (!match) fail(`${label} must use major.minor contract_version`);
  return { major: Number(match[1]), minor: Number(match[2]) };
}
function requireSupportedMajor(value, label) {
  const parsed = parseVersion(value, label);
  if (parsed.major !== SUPPORTED_MAJOR) fail(`${label} uses unsupported major version ${value}`);
  return parsed;
}
function requireSafeToken(value, label) {
  if (typeof value !== "string" || !safeToken.test(value)) fail(`${label} must be a bounded, low-cardinality token`);
}
function rejectPrivate(value, label = "$") {
  if (typeof value === "string") {
    if (/https?:\/\/|file:\/\/|\/Users\/|\/home\/|\.ssh\/|(?:^|[?&])(token|password|secret)=|Authorization:|Bearer\s+[A-Za-z0-9._-]+|(?:\b(?:10|127|192\.168)\.|\b172\.(?:1[6-9]|2\d|3[01])\.)/i.test(value)) fail(`${label} contains a private locator, credential-like data, or a raw URL/query string`);
    return;
  }
  if (Array.isArray(value)) return value.forEach((item, index) => rejectPrivate(item, `${label}[${index}]`));
  if (plain(value)) {
    for (const [key, item] of Object.entries(value)) {
      if (/^(?:prompt|output|message|telegram_text|memory_content|file_content|raw_url|query_string|db_statement|exception_message|exception_stack|credential|secret|token|password|customer_data|accounting_data)$/i.test(key)) fail(`${label}.${key} is forbidden content-bearing telemetry`);
      rejectPrivate(item, `${label}.${key}`);
    }
  }
}
function validateExtensions(value, label) {
  if (!Array.isArray(value)) fail(`${label} must be array`);
  const seen = new Set();
  for (const item of value) {
    exact(item, ["id", "version", "decision_effect"], `${label}.extension`);
    if (!id.test(item.id) || !/^v[1-9][0-9]*$/.test(item.version) || item.decision_effect !== "informational" || seen.has(item.id)) fail(`${label}.extension invalid or decision-driving`);
    seen.add(item.id);
  }
}
function validateSource(value, label) {
  exact(value, ["source_kind", "producer", "producer_version"], label);
  if (!["service_internal", "service_probe", "systemd", "substrate", "synthetic", "aggregator"].includes(value.source_kind)) fail(`${label}.source_kind invalid`);
  if (!id.test(value.producer)) fail(`${label}.producer invalid`);
  requireSafeToken(value.producer_version, `${label}.producer_version`);
}
function validateService(value, label) {
  exact(value, ["service_id", "instance_id"], label);
  if (!id.test(value.service_id) || !id.test(value.instance_id)) fail(`${label} invalid`);
}
function validateTraceLink(value, label) {
  exact(value, ["trace_id", "span_id"], label);
  if (!traceId.test(value.trace_id) || !spanId.test(value.span_id)) fail(`${label} must use W3C trace/span identifiers`);
}
function validateTimedObservation(record, label) {
  if (!realDateTime(record.observed_at) || !realDateTime(record.collected_at) || !realDateTime(record.fresh_until)) fail(`${label} timestamps must be real UTC instants`);
  const freshnessMs = durationToMs(record.freshness_window);
  if (freshnessMs <= 0) fail(`${label}.freshness_window must be positive`);
  if (Date.parse(record.collected_at) < Date.parse(record.observed_at)) fail(`${label}.collected_at cannot precede observed_at`);
  if (Date.parse(record.fresh_until) - Date.parse(record.observed_at) !== freshnessMs) fail(`${label}.fresh_until must equal observed_at plus freshness_window`);
}
function validateCheck(value, label) {
  exact(value, value.dependency_service_id !== undefined ? ["surface", "dependency_service_id"] : ["surface"], label);
  if (!["liveness", "readiness", "dependency"].includes(value.surface)) fail(`${label}.surface invalid`);
  if (value.surface === "dependency") {
    if (!id.test(value.dependency_service_id)) fail(`${label}.dependency_service_id invalid`);
  } else if (value.dependency_service_id !== undefined) {
    fail(`${label}.dependency_service_id is only valid for dependency checks`);
  }
}
function validateInventory(value, label, aggregateSurface) {
  exact(value, ["authority_kind", "authority_ref", "authority_digest", "expected_slots"], label);
  if (!["services_json", "component_contract", "producer_registry"].includes(value.authority_kind)) fail(`${label}.authority_kind invalid`);
  if (!opaqueRef.test(value.authority_ref) || !digest.test(value.authority_digest)) fail(`${label} must bind to an opaque authority ref and digest`);
  if (!Array.isArray(value.expected_slots) || value.expected_slots.length === 0) fail(`${label}.expected_slots must contain at least one declared slot`);
  const seen = new Set();
  for (const slot of value.expected_slots) {
    exact(slot, slot.dependency_service_id !== undefined ? ["slot_id", "surface", "applicability", "dependency_service_id"] : ["slot_id", "surface", "applicability"], `${label}.slot`);
    if (!id.test(slot.slot_id) || seen.has(slot.slot_id)) fail(`${label}.slot_id invalid or duplicated`);
    seen.add(slot.slot_id);
    if (!["liveness", "readiness", "dependency"].includes(slot.surface)) fail(`${label}.slot.surface invalid`);
    if (!["required", "not_applicable"].includes(slot.applicability)) fail(`${label}.slot.applicability invalid`);
    if (slot.surface === "dependency") {
      if (!id.test(slot.dependency_service_id)) fail(`${label}.slot.dependency_service_id invalid`);
    } else if (slot.dependency_service_id !== undefined) {
      fail(`${label}.slot.dependency_service_id is only valid for dependency slots`);
    }
    if (aggregateSurface !== "service_overall" && slot.surface !== aggregateSurface) fail(`${label}.slot ${slot.slot_id} does not match aggregate_surface=${aggregateSurface}`);
  }
}
function validateTracePolicy(record) {
  exact(record, ["kind", "contract_version", "policy_id", "source", "service", "default_state", "sampling", "serialization", "retention", "failure_behavior", "created_at", "extensions"], "trace-policy");
  requireSupportedMajor(record.contract_version, "trace-policy.contract_version");
  if (!id.test(record.policy_id)) fail("trace-policy.policy_id invalid");
  validateSource(record.source, "trace-policy.source");
  validateService(record.service, "trace-policy.service");
  exact(record.default_state, ["instrumentation_enabled", "export_enabled", "automatic_instrumentation"], "trace-policy.default_state");
  if (typeof record.default_state.instrumentation_enabled !== "boolean" || typeof record.default_state.export_enabled !== "boolean") fail("trace-policy.default_state must use booleans");
  if (!["disabled", "allowlisted_only"].includes(record.default_state.automatic_instrumentation)) fail("trace-policy.default_state.automatic_instrumentation invalid");
  exact(record.sampling, ["mode", "rate_per_mille"], "trace-policy.sampling");
  if (record.sampling.mode !== "head" || !Number.isInteger(record.sampling.rate_per_mille) || record.sampling.rate_per_mille < 0 || record.sampling.rate_per_mille > 1000) fail("trace-policy.sampling invalid");
  exact(record.serialization, ["allowlist_version", "deny_by_default", "max_attributes", "max_string_length"], "trace-policy.serialization");
  if (record.serialization.allowlist_version !== "v1" || record.serialization.deny_by_default !== true || !Number.isInteger(record.serialization.max_attributes) || record.serialization.max_attributes < 1 || record.serialization.max_attributes > 64 || !Number.isInteger(record.serialization.max_string_length) || record.serialization.max_string_length < 1 || record.serialization.max_string_length > 256) fail("trace-policy.serialization invalid");
  exact(record.retention, ["policy_ref", "data_class", "deletion_owner"], "trace-policy.retention");
  if (!opaqueRef.test(record.retention.policy_ref) || record.retention.policy_ref !== "ref:data-lifecycle-v1" || record.retention.data_class !== "operational_telemetry" || !["producer", "authoritative_store"].includes(record.retention.deletion_owner)) fail("trace-policy.retention invalid");
  exact(record.failure_behavior, ["export_failure", "instrumentation_failure"], "trace-policy.failure_behavior");
  if (record.failure_behavior.export_failure !== "drop_and_count" || record.failure_behavior.instrumentation_failure !== "must_not_fail_request") fail("trace-policy.failure_behavior invalid");
  if (!realDateTime(record.created_at)) fail("trace-policy.created_at invalid");
  validateExtensions(record.extensions, "trace-policy.extensions");
}
function validateObservation(record) {
  exact(record, record.trace !== undefined ? ["kind", "contract_version", "observation_id", "source", "service", "slot_id", "check", "attempt_id", "observed_at", "collected_at", "freshness_window", "fresh_until", "outcome", "diagnostic_ref", "trace", "extensions"] : ["kind", "contract_version", "observation_id", "source", "service", "slot_id", "check", "attempt_id", "observed_at", "collected_at", "freshness_window", "fresh_until", "outcome", "diagnostic_ref", "extensions"], "observation");
  requireSupportedMajor(record.contract_version, "observation.contract_version");
  if (!id.test(record.observation_id) || !id.test(record.slot_id) || !id.test(record.attempt_id)) fail("observation identity invalid");
  validateSource(record.source, "observation.source");
  validateService(record.service, "observation.service");
  validateCheck(record.check, "observation.check");
  validateTimedObservation(record, "observation");
  if (!["ok", "degraded", "failed", "stale", "unknown", "not_applicable"].includes(record.outcome)) fail("observation.outcome invalid");
  if (!opaqueRef.test(record.diagnostic_ref)) fail("observation.diagnostic_ref must remain content-blind");
  if (record.trace !== undefined) validateTraceLink(record.trace, "observation.trace");
  validateExtensions(record.extensions, "observation.extensions");
}
function effectiveObservationOutcome(observation, aggregateCollectedAt) {
  if (observation.outcome === "ok" && Date.parse(observation.fresh_until) < Date.parse(aggregateCollectedAt)) return "stale";
  return observation.outcome;
}
function aggregateOutcome(effectiveChildren) {
  const material = effectiveChildren.filter((outcome) => outcome !== "not_applicable");
  if (material.length === 0) return "unknown";
  if (material.includes("failed")) return "failed";
  if (material.includes("stale")) return "stale";
  if (material.includes("unknown")) return "unknown";
  if (material.includes("degraded")) return "degraded";
  return "ok";
}
function validateAggregate(record, observations) {
  exact(record, record.trace !== undefined ? ["kind", "contract_version", "aggregate_id", "source", "service", "aggregate_surface", "attempt_id", "observed_at", "collected_at", "freshness_window", "fresh_until", "inventory", "observation_refs", "outcome", "diagnostic_ref", "trace", "extensions"] : ["kind", "contract_version", "aggregate_id", "source", "service", "aggregate_surface", "attempt_id", "observed_at", "collected_at", "freshness_window", "fresh_until", "inventory", "observation_refs", "outcome", "diagnostic_ref", "extensions"], "aggregate");
  requireSupportedMajor(record.contract_version, "aggregate.contract_version");
  if (!id.test(record.aggregate_id) || !id.test(record.attempt_id)) fail("aggregate identity invalid");
  validateSource(record.source, "aggregate.source");
  if (record.source.source_kind !== "aggregator") fail("aggregate.source.source_kind must be aggregator");
  validateService(record.service, "aggregate.service");
  if (!["liveness", "readiness", "dependency", "service_overall"].includes(record.aggregate_surface)) fail("aggregate.aggregate_surface invalid");
  validateTimedObservation(record, "aggregate");
  validateInventory(record.inventory, "aggregate.inventory", record.aggregate_surface);
  if (record.trace !== undefined) validateTraceLink(record.trace, "aggregate.trace");
  validateExtensions(record.extensions, "aggregate.extensions");
  if (!["ok", "degraded", "failed", "stale", "unknown"].includes(record.outcome)) fail("aggregate.outcome invalid");
  if (!opaqueRef.test(record.diagnostic_ref)) fail("aggregate.diagnostic_ref must remain content-blind");
  const slotMap = new Map(record.inventory.expected_slots.map((slot) => [slot.slot_id, slot]));
  const seenRefs = new Set();
  const bySlot = new Map();
  for (const ref of record.observation_refs) {
    exact(ref, ["slot_id", "observation_id"], "aggregate.observation_ref");
    if (!id.test(ref.slot_id) || !id.test(ref.observation_id)) fail("aggregate.observation_ref invalid");
    if (!slotMap.has(ref.slot_id)) fail(`aggregate references undeclared slot ${ref.slot_id}`);
    if (seenRefs.has(ref.slot_id)) fail(`aggregate has duplicate observation for slot ${ref.slot_id}`);
    const observation = observations.get(ref.observation_id);
    if (!observation) fail(`aggregate references missing observation ${ref.observation_id}`);
    if (observation.slot_id !== ref.slot_id) fail(`observation ${ref.observation_id} does not bind slot ${ref.slot_id}`);
    if (observation.service.service_id !== record.service.service_id || observation.service.instance_id !== record.service.instance_id) fail(`observation ${ref.observation_id} is for a different service/instance`);
    const slot = slotMap.get(ref.slot_id);
    if (observation.check.surface !== slot.surface) fail(`observation ${ref.observation_id} surface mismatch for slot ${ref.slot_id}`);
    if (slot.surface === "dependency" && observation.check.dependency_service_id !== slot.dependency_service_id) fail(`observation ${ref.observation_id} dependency target mismatch for slot ${ref.slot_id}`);
    seenRefs.add(ref.slot_id);
    bySlot.set(ref.slot_id, observation);
  }
  const effectiveChildren = [];
  for (const slot of record.inventory.expected_slots) {
    const observation = bySlot.get(slot.slot_id);
    if (slot.applicability === "not_applicable") {
      if (observation && observation.outcome !== "not_applicable") fail(`slot ${slot.slot_id} is not_applicable but the bound observation is ${observation.outcome}`);
      continue;
    }
    if (!observation) {
      effectiveChildren.push("unknown");
      continue;
    }
    if (observation.outcome === "not_applicable") fail(`required slot ${slot.slot_id} cannot report not_applicable`);
    effectiveChildren.push(effectiveObservationOutcome(observation, record.collected_at));
  }
  const expected = aggregateOutcome(effectiveChildren);
  if (record.outcome !== expected) fail(`aggregate outcome mismatch: expected ${expected}, got ${record.outcome}`);
}
function validateTraceSpan(record, policies) {
  exact(record, record.parent_span_id !== undefined ? ["kind", "contract_version", "policy_id", "source", "service", "trace_id", "span_id", "parent_span_id", "operation", "started_at", "ended_at", "collected_at", "sampled", "outcome", "attributes", "diagnostic_ref", "extensions"] : ["kind", "contract_version", "policy_id", "source", "service", "trace_id", "span_id", "operation", "started_at", "ended_at", "collected_at", "sampled", "outcome", "attributes", "diagnostic_ref", "extensions"], "trace-span");
  requireSupportedMajor(record.contract_version, "trace-span.contract_version");
  if (!id.test(record.policy_id)) fail("trace-span.policy_id invalid");
  if (!traceId.test(record.trace_id) || !spanId.test(record.span_id) || (record.parent_span_id !== undefined && !spanId.test(record.parent_span_id))) fail("trace-span must use W3C trace/span identifiers");
  validateSource(record.source, "trace-span.source");
  validateService(record.service, "trace-span.service");
  const policy = policies.get(record.policy_id);
  if (!policy) fail(`trace-span references unknown policy ${record.policy_id}`);
  if (!realDateTime(record.started_at) || !realDateTime(record.ended_at) || !realDateTime(record.collected_at) || Date.parse(record.ended_at) < Date.parse(record.started_at) || Date.parse(record.collected_at) < Date.parse(record.ended_at)) fail("trace-span timestamps invalid");
  if (typeof record.sampled !== "boolean") fail("trace-span.sampled must be boolean");
  if (!["ok", "degraded", "failed", "stale", "unknown"].includes(record.outcome)) fail("trace-span.outcome invalid");
  exact(record.operation, ["surface", "phase"], "trace-span.operation");
  if (!["task", "gateway", "service", "synthetic"].includes(record.operation.surface) || !["ingress", "queue", "execution", "dependency", "publication", "probe", "export"].includes(record.operation.phase)) fail("trace-span.operation invalid");
  validateExtensions(record.extensions, "trace-span.extensions");
  if (!opaqueRef.test(record.diagnostic_ref)) fail("trace-span.diagnostic_ref must remain content-blind");
  exact(record.attributes, Object.keys(record.attributes), "trace-span.attributes");
  const allowedKeys = new Set(["service_id", "instance_id", "dependency_service_id", "lifecycle_outcome", "task_class", "runtime_lane", "retry_ordinal", "error_class", "check_surface"]);
  for (const key of Object.keys(record.attributes)) if (!allowedKeys.has(key)) fail(`trace-span.attributes.${key} is not on the v1 allowlist`);
  if (record.attributes.service_id !== undefined && record.attributes.service_id !== record.service.service_id) fail("trace-span.attributes.service_id must echo the top-level service_id");
  if (record.attributes.instance_id !== undefined && record.attributes.instance_id !== record.service.instance_id) fail("trace-span.attributes.instance_id must echo the top-level instance_id");
  if (record.attributes.dependency_service_id !== undefined && !id.test(record.attributes.dependency_service_id)) fail("trace-span.attributes.dependency_service_id invalid");
  if (record.attributes.lifecycle_outcome !== undefined && !["ok", "degraded", "failed", "stale", "unknown", "not_applicable"].includes(record.attributes.lifecycle_outcome)) fail("trace-span.attributes.lifecycle_outcome invalid");
  if (record.attributes.task_class !== undefined && !["diagnostic", "delegation", "maintenance", "publication", "read_only", "not_applicable"].includes(record.attributes.task_class)) fail("trace-span.attributes.task_class invalid");
  if (record.attributes.runtime_lane !== undefined && !["default", "reason-hard", "reason-fast", "numeric", "review", "not_applicable"].includes(record.attributes.runtime_lane)) fail("trace-span.attributes.runtime_lane invalid");
  if (record.attributes.retry_ordinal !== undefined && (!Number.isInteger(record.attributes.retry_ordinal) || record.attributes.retry_ordinal < 0 || record.attributes.retry_ordinal > 10)) fail("trace-span.attributes.retry_ordinal invalid");
  if (record.attributes.error_class !== undefined) requireSafeToken(record.attributes.error_class, "trace-span.attributes.error_class");
  if (record.attributes.check_surface !== undefined && !["liveness", "readiness", "dependency", "not_applicable"].includes(record.attributes.check_surface)) fail("trace-span.attributes.check_surface invalid");
  if (record.attributes.check_surface === "dependency" && record.attributes.dependency_service_id === undefined) fail("trace-span dependency spans must identify the dependency_service_id");
  if (record.attributes.check_surface !== "dependency" && record.attributes.dependency_service_id !== undefined) fail("trace-span dependency_service_id is only valid when check_surface=dependency");
  const stringValues = Object.values(record.attributes).filter((value) => typeof value === "string");
  if (Object.keys(record.attributes).length > policy.serialization.max_attributes) fail("trace-span emitted more attributes than the bound trace policy permits");
  if (stringValues.some((value) => value.length > policy.serialization.max_string_length)) fail("trace-span emitted an attribute string longer than the bound trace policy permits");
}
function validateRecordSet(records, label) {
  const observations = new Map();
  const policies = new Map();
  for (const record of records) {
    rejectPrivate(record, `${label}.${record.kind ?? "record"}`);
    if (record.kind === "service-observation") observations.set(record.observation_id, record);
    if (record.kind === "trace-policy") policies.set(record.policy_id, record);
  }
  for (const policy of policies.values()) validateTracePolicy(policy);
  for (const observation of observations.values()) validateObservation(observation);
  for (const record of records) {
    if (record.kind === "observation-aggregate") validateAggregate(record, observations);
    if (record.kind === "trace-span") validateTraceSpan(record, policies);
  }
}
const reject = (fn, label) => assert.throws(fn, undefined, label);

checkSchema(schema);

for (const record of positive.records) schemaValid(record, `positive:${record.kind}`);
validateRecordSet(positive.records, "positive");

for (const record of mixedVersion.records) schemaValid(record, `mixed:${record.kind}`);
validateRecordSet(mixedVersion.records, "mixed-version");

for (const record of staleMissingPartial.records) schemaValid(record, `stale-missing-partial:${record.kind}`);
validateRecordSet(staleMissingPartial.records, "stale-missing-partial");

schemaInvalid(negative.schema_malformed_diagnostic_ref, "schema-malformed-diagnostic-ref");
schemaValid(negative.unsupported_major_observation, "unsupported-major-observation");
reject(() => validateRecordSet([negative.unsupported_major_observation], "unsupported-major-observation"), "unsupported major version fails visibly");

for (const [name, scenario] of Object.entries(negative)) {
  if (name === "schema_malformed_diagnostic_ref" || name === "unsupported_major_observation") continue;
  for (const record of scenario.records) schemaValid(record, `${name}:${record.kind}`);
  reject(() => validateRecordSet(scenario.records, name), name);
}

console.log("Operational-observability v1 normative schema plus 8 fixture scenarios validated.");
