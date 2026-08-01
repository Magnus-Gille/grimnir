import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const fixturesDir = path.join(root, "tests/fixtures/operational-observability");
const read = (name) => JSON.parse(fs.readFileSync(path.join(fixturesDir, name), "utf8"));
const schema = JSON.parse(fs.readFileSync(path.join(root, "docs/operational-observability-v1.schema.json"), "utf8"));
const servicesRegistry = JSON.parse(fs.readFileSync(path.join(root, "services.json"), "utf8"));

const positive = read("positive.json");
const mixedVersion = read("mixed-version.json");
const staleMissingPartial = read("stale-missing-partial.json");
const unsupportedMajorRollout = read("unsupported-major-rollout.json");
const inventoryDerivation = read("inventory-derivation.json");
const negative = read("negative.json");

const SUPPORTED_MAJOR = 1;
const MAX_SLOT_FRESHNESS_MS = 24 * 60 * 60 * 1000;
const SLOT_CLASS_ORDER = new Map([
  ["service_liveness", 0],
  ["service_readiness", 1],
  ["dependency_health", 2],
  ["exporter_health", 3],
  ["collector_health", 4]
]);

const fail = (message) => { throw new Error(message); };
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const id = /^[a-z][a-z0-9-]{2,62}$/;
const digest = /^sha256:[a-f0-9]{64}$/;
const utc = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const durationPattern = /^P(?=\d|T\d)(?:(\d+)D)?(?:T(?=\d)(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/;
const safeToken = /^[A-Za-z0-9][A-Za-z0-9._:+-]{0,79}$/;
const opaqueRef = /^ref:[a-z][a-z0-9-]{2,120}$/;
const traceId = /^[a-f0-9]{32}$/;
const spanId = /^[a-f0-9]{16}$/;
const privateIpv4 = /(?:^|[^0-9])(?:10(?:\.\d{1,3}){3}|127(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})(?:$|[^0-9])/;
const servicesByName = new Map(servicesRegistry.components.map((component) => [component.name, component]));

function canonicalJson(value) {
  if (value === null || typeof value === "number" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (plain(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  fail(`unsupported canonical value type ${typeof value}`);
}
const canonical = canonicalJson;
const typeMatches = (type, value) => ({
  object: plain(value),
  array: Array.isArray(value),
  string: typeof value === "string",
  integer: Number.isInteger(value),
  boolean: typeof value === "boolean",
  null: value === null
})[type];
const realDateTime = (value) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/.exec(value);
  if (!match) return false;
  const instant = new Date(value);
  if (Number.isNaN(instant.getTime())) return false;
  const [, year, month, day, hour, minute, second] = match;
  return instant.getUTCFullYear() === Number(year)
    && instant.getUTCMonth() + 1 === Number(month)
    && instant.getUTCDate() === Number(day)
    && instant.getUTCHours() === Number(hour)
    && instant.getUTCMinutes() === Number(minute)
    && instant.getUTCSeconds() === Number(second);
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
    return attempts.filter((errors) => errors.length === 0).length === 1
      ? []
      : [`${at}: expected exactly one branch (${attempts.flat().join("; ")})`];
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
    for (const [field, child] of Object.entries(node.properties ?? {})) {
      if (Object.hasOwn(value, field)) errors.push(...schemaErrors(child, value[field], `${at}.${field}`));
    }
    if (node.additionalProperties === false) {
      for (const field of Object.keys(value)) if (!Object.hasOwn(node.properties ?? {}, field)) errors.push(`${at}.${field}: additional property`);
    }
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
    if (/https?:\/\/|file:\/\/|\/Users\/|\/home\/|\.ssh\/|(?:^|[?&])(token|password|secret)=|Authorization:|Bearer\s+[A-Za-z0-9._-]+/i.test(value)) fail(`${label} contains a private locator, credential-like data, or a raw URL/query string`);
    if (privateIpv4.test(value)) fail(`${label} contains a private IP literal`);
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
function slotSortKey(slot) {
  return [
    SLOT_CLASS_ORDER.get(slot.slot_class) ?? 99,
    slot.slot_id,
    slot.surface,
    slot.applicability,
    slot.owner_kind,
    slot.owner_service_id,
    slot.dependency_service_id ?? ""
  ].join("\u0000");
}
function slotAuthorityProjection(slot) {
  const projection = structuredClone(slot);
  delete projection.max_freshness;
  return projection;
}
function authorityDigest(authority, slots) {
  const projection = {
    authority_kind: authority.authority_kind,
    authority_ref: authority.authority_ref,
    expected_slots: slots.map(slotAuthorityProjection).sort((left, right) => slotSortKey(left).localeCompare(slotSortKey(right)))
  };
  return `sha256:${crypto.createHash("sha256").update(canonicalJson(projection), "utf8").digest("hex")}`;
}
function derivedServicesJsonSlots(serviceId, maxFreshness) {
  const component = servicesByName.get(serviceId);
  if (!component) fail(`services_json authority cannot derive unknown service ${serviceId}`);
  const desiredRuntimeState = component.desired_runtime_state ?? "active";
  const applicability = desiredRuntimeState === "active" ? "required" : "not_applicable";
  return [
    {
      slot_id: "service-live",
      authority_kind: "services_json",
      slot_class: "service_liveness",
      surface: "liveness",
      applicability,
      owner_kind: "producer",
      owner_service_id: serviceId,
      max_freshness: maxFreshness
    },
    {
      slot_id: "service-ready",
      authority_kind: "services_json",
      slot_class: "service_readiness",
      surface: "readiness",
      applicability,
      owner_kind: "producer",
      owner_service_id: serviceId,
      max_freshness: maxFreshness
    }
  ];
}
function normalizedSlots(slots) {
  return slots.map((slot) => structuredClone(slot)).sort((left, right) => slotSortKey(left).localeCompare(slotSortKey(right)));
}
function validateInventory(value, label, aggregate, policiesByService) {
  exact(value, ["authorities", "expected_slots"], label);
  if (!Array.isArray(value.authorities) || value.authorities.length === 0) fail(`${label}.authorities must contain at least one binding`);
  if (!Array.isArray(value.expected_slots) || value.expected_slots.length === 0) fail(`${label}.expected_slots must contain at least one declared slot`);
  const authoritiesByKind = new Map();
  for (const authority of value.authorities) {
    exact(authority, ["authority_kind", "authority_ref", "authority_digest"], `${label}.authority`);
    if (!["services_json", "producer_contract", "consumer_contract"].includes(authority.authority_kind)) fail(`${label}.authority_kind invalid`);
    if (authoritiesByKind.has(authority.authority_kind)) fail(`${label}.authority_kind ${authority.authority_kind} duplicated`);
    if (!opaqueRef.test(authority.authority_ref) || !digest.test(authority.authority_digest)) fail(`${label}.authority binding malformed`);
    authoritiesByKind.set(authority.authority_kind, authority);
  }
  const seenSlotIds = new Set();
  const slotsByKind = new Map();
  for (const slot of value.expected_slots) {
    exact(slot, slot.dependency_service_id !== undefined
      ? ["slot_id", "authority_kind", "slot_class", "surface", "applicability", "owner_kind", "owner_service_id", "max_freshness", "dependency_service_id"]
      : ["slot_id", "authority_kind", "slot_class", "surface", "applicability", "owner_kind", "owner_service_id", "max_freshness"], `${label}.slot`);
    if (!id.test(slot.slot_id) || seenSlotIds.has(slot.slot_id)) fail(`${label}.slot_id invalid or duplicated`);
    seenSlotIds.add(slot.slot_id);
    if (!authoritiesByKind.has(slot.authority_kind)) fail(`${label}.slot ${slot.slot_id} references undeclared authority_kind ${slot.authority_kind}`);
    if (!["service_liveness", "service_readiness", "dependency_health", "exporter_health", "collector_health"].includes(slot.slot_class)) fail(`${label}.slot ${slot.slot_id} has invalid slot_class`);
    if (!["liveness", "readiness", "dependency"].includes(slot.surface)) fail(`${label}.slot ${slot.slot_id} surface invalid`);
    if (!["required", "not_applicable"].includes(slot.applicability)) fail(`${label}.slot ${slot.slot_id} applicability invalid`);
    if (!["producer", "consumer"].includes(slot.owner_kind) || !id.test(slot.owner_service_id)) fail(`${label}.slot ${slot.slot_id} owner invalid`);
    const maxFreshnessMs = durationToMs(slot.max_freshness);
    if (maxFreshnessMs <= 0 || maxFreshnessMs > MAX_SLOT_FRESHNESS_MS) fail(`${label}.slot ${slot.slot_id} max_freshness must be positive and no greater than P1D`);
    if (slot.slot_class === "service_liveness") {
      if (slot.authority_kind !== "services_json" || slot.surface !== "liveness" || slot.owner_kind !== "producer" || slot.owner_service_id !== aggregate.service.service_id || slot.dependency_service_id !== undefined) fail(`${label}.slot ${slot.slot_id} must be a services_json producer liveness slot`);
    } else if (slot.slot_class === "service_readiness") {
      if (slot.authority_kind !== "services_json" || slot.surface !== "readiness" || slot.owner_kind !== "producer" || slot.owner_service_id !== aggregate.service.service_id || slot.dependency_service_id !== undefined) fail(`${label}.slot ${slot.slot_id} must be a services_json producer readiness slot`);
    } else if (slot.slot_class === "dependency_health") {
      if (slot.authority_kind !== "producer_contract" || slot.surface !== "dependency" || slot.owner_kind !== "producer" || slot.owner_service_id !== aggregate.service.service_id || !id.test(slot.dependency_service_id)) fail(`${label}.slot ${slot.slot_id} must be a producer_contract dependency slot`);
    } else if (slot.slot_class === "exporter_health") {
      if (slot.authority_kind !== "producer_contract" || slot.surface !== "readiness" || slot.owner_kind !== "producer" || slot.owner_service_id !== aggregate.service.service_id || slot.dependency_service_id !== undefined) fail(`${label}.slot ${slot.slot_id} must be a producer_contract exporter slot`);
    } else if (slot.slot_class === "collector_health") {
      if (slot.authority_kind !== "consumer_contract" || slot.surface !== "readiness" || slot.owner_kind !== "consumer" || slot.owner_service_id !== aggregate.source.producer || slot.dependency_service_id !== undefined || slot.applicability !== "required") fail(`${label}.slot ${slot.slot_id} must be a required consumer_contract collector slot owned by the aggregating consumer`);
    }
    if (aggregate.aggregate_surface !== "service_overall" && slot.surface !== aggregate.aggregate_surface) fail(`${label}.slot ${slot.slot_id} does not match aggregate_surface=${aggregate.aggregate_surface}`);
    if (!slotsByKind.has(slot.authority_kind)) slotsByKind.set(slot.authority_kind, []);
    slotsByKind.get(slot.authority_kind).push(slot);
  }
  for (const [kind, authority] of authoritiesByKind.entries()) {
    const slots = slotsByKind.get(kind) ?? [];
    if (slots.length === 0) fail(`${label}.authority_kind ${kind} does not allocate any expected slots`);
    const expectedDigest = authorityDigest(authority, slots);
    if (authority.authority_digest !== expectedDigest) fail(`${label}.authority_kind ${kind} digest mismatch: expected ${expectedDigest}, got ${authority.authority_digest}`);
  }
  const registrySlots = normalizedSlots(slotsByKind.get("services_json") ?? []);
  if (registrySlots.length > 0) {
    const maxFreshness = registrySlots[0].max_freshness;
    const expectedRegistrySlots = normalizedSlots(derivedServicesJsonSlots(aggregate.service.service_id, maxFreshness));
    if (canonical(expectedRegistrySlots.map(slotAuthorityProjection)) !== canonical(registrySlots.map(slotAuthorityProjection))) fail(`${label}.services_json slots do not match the authoritative services.json derivation for ${aggregate.service.service_id}`);
  }
  if (aggregate.aggregate_surface === "service_overall") {
    const collectorSlots = value.expected_slots.filter((slot) => slot.slot_class === "collector_health" && slot.applicability === "required");
    if (collectorSlots.length !== 1) fail(`${label} must contain exactly one required collector_health slot for service_overall aggregates`);
    const policy = policiesByService.get(`${aggregate.service.service_id}:${aggregate.service.instance_id}`);
    if (policy?.default_state.export_enabled === true) {
      const exporterSlots = value.expected_slots.filter((slot) => slot.slot_class === "exporter_health" && slot.applicability === "required");
      if (exporterSlots.length === 0) fail(`${label} must include a required exporter_health slot when the bound service trace policy exports spans`);
    }
  }
}
function validateTracePolicy(record) {
  exact(record, ["kind", "contract_version", "policy_id", "source", "service", "default_state", "sampling", "serialization", "retention", "failure_behavior", "created_at", "extensions"], "trace-policy");
  requireSupportedMajor(record.contract_version, "trace-policy.contract_version");
  if (!id.test(record.policy_id)) fail("trace-policy.policy_id invalid");
  validateSource(record.source, "trace-policy.source");
  validateService(record.service, "trace-policy.service");
  if (record.source.producer !== record.service.service_id) fail("trace-policy.source.producer must match trace-policy.service.service_id");
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
  if (record.default_state.instrumentation_enabled === false) {
    if (record.default_state.export_enabled !== false) fail("trace-policy cannot export when instrumentation_enabled=false");
    if (record.default_state.automatic_instrumentation !== "disabled") fail("trace-policy automatic instrumentation must be disabled when instrumentation_enabled=false");
    if (record.sampling.rate_per_mille !== 0) fail("trace-policy sampling must be zero when instrumentation_enabled=false");
  }
  if (record.default_state.export_enabled === false && record.sampling.rate_per_mille !== 0) fail("trace-policy sampling must be zero when export_enabled=false");
}
function validateObservation(record) {
  exact(record, record.trace !== undefined
    ? ["kind", "contract_version", "observation_id", "source", "service", "slot_id", "check", "attempt_id", "observed_at", "collected_at", "freshness_window", "fresh_until", "outcome", "diagnostic_ref", "trace", "extensions"]
    : ["kind", "contract_version", "observation_id", "source", "service", "slot_id", "check", "attempt_id", "observed_at", "collected_at", "freshness_window", "fresh_until", "outcome", "diagnostic_ref", "extensions"], "observation");
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
function effectiveObservationOutcome(observation, slot, asOf) {
  const effectiveFreshnessMs = Math.min(durationToMs(observation.freshness_window), durationToMs(slot.max_freshness));
  const expired = Date.parse(asOf) > Date.parse(observation.observed_at) + effectiveFreshnessMs;
  if (!expired) return observation.outcome;
  if (observation.outcome === "ok" || observation.outcome === "degraded") return "stale";
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
function renderEffectiveAggregateOutcome(record, renderedAt) {
  if (Date.parse(renderedAt) <= Date.parse(record.fresh_until)) return record.outcome;
  if (record.outcome === "ok" || record.outcome === "degraded") return "stale";
  return record.outcome;
}
function validateAggregate(record, observations, policiesByService) {
  exact(record, record.trace !== undefined
    ? ["kind", "contract_version", "aggregate_id", "source", "service", "aggregate_surface", "attempt_id", "observed_at", "collected_at", "freshness_window", "fresh_until", "inventory", "observation_refs", "outcome", "diagnostic_ref", "trace", "extensions"]
    : ["kind", "contract_version", "aggregate_id", "source", "service", "aggregate_surface", "attempt_id", "observed_at", "collected_at", "freshness_window", "fresh_until", "inventory", "observation_refs", "outcome", "diagnostic_ref", "extensions"], "aggregate");
  requireSupportedMajor(record.contract_version, "aggregate.contract_version");
  if (!id.test(record.aggregate_id) || !id.test(record.attempt_id)) fail("aggregate identity invalid");
  validateSource(record.source, "aggregate.source");
  if (record.source.source_kind !== "aggregator") fail("aggregate.source.source_kind must be aggregator");
  validateService(record.service, "aggregate.service");
  if (!["liveness", "readiness", "dependency", "service_overall"].includes(record.aggregate_surface)) fail("aggregate.aggregate_surface invalid");
  validateTimedObservation(record, "aggregate");
  if (record.trace !== undefined) validateTraceLink(record.trace, "aggregate.trace");
  validateExtensions(record.extensions, "aggregate.extensions");
  if (!["ok", "degraded", "failed", "stale", "unknown"].includes(record.outcome)) fail("aggregate.outcome invalid");
  if (!opaqueRef.test(record.diagnostic_ref)) fail("aggregate.diagnostic_ref must remain content-blind");
  validateInventory(record.inventory, "aggregate.inventory", record, policiesByService);
  const slotMap = new Map(record.inventory.expected_slots.map((slot) => [slot.slot_id, slot]));
  const seenRefs = new Set();
  const bySlot = new Map();
  for (const ref of record.observation_refs) {
    exact(ref, ["slot_id", "observation_id"], "aggregate.observation_ref");
    if (!id.test(ref.slot_id) || !id.test(ref.observation_id)) fail("aggregate.observation_ref invalid");
    if (!slotMap.has(ref.slot_id)) fail(`aggregate references undeclared slot ${ref.slot_id}`);
    if (seenRefs.has(ref.slot_id)) fail(`aggregate has duplicate observation for slot ${ref.slot_id}`);
    const observation = observations.get(ref.observation_id);
    if (!observation) fail(`aggregate references missing accepted observation ${ref.observation_id}`);
    if (observation.slot_id !== ref.slot_id) fail(`observation ${ref.observation_id} does not bind slot ${ref.slot_id}`);
    if (observation.service.service_id !== record.service.service_id || observation.service.instance_id !== record.service.instance_id) fail(`observation ${ref.observation_id} is for a different service/instance`);
    const slot = slotMap.get(ref.slot_id);
    if (observation.check.surface !== slot.surface) fail(`observation ${ref.observation_id} surface mismatch for slot ${ref.slot_id}`);
    if (slot.surface === "dependency" && observation.check.dependency_service_id !== slot.dependency_service_id) fail(`observation ${ref.observation_id} dependency target mismatch for slot ${ref.slot_id}`);
    if (slot.slot_class === "collector_health" && observation.source.producer !== slot.owner_service_id) fail(`collector slot ${slot.slot_id} must be emitted by ${slot.owner_service_id}`);
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
    effectiveChildren.push(effectiveObservationOutcome(observation, slot, record.collected_at));
  }
  const expected = aggregateOutcome(effectiveChildren);
  if (record.outcome !== expected) fail(`aggregate outcome mismatch: expected ${expected}, got ${record.outcome}`);
}
function validateTraceSpan(record, policiesById) {
  exact(record, record.parent_span_id !== undefined
    ? ["kind", "contract_version", "policy_id", "source", "service", "trace_id", "span_id", "parent_span_id", "operation", "started_at", "ended_at", "collected_at", "sampled", "outcome", "attributes", "diagnostic_ref", "extensions"]
    : ["kind", "contract_version", "policy_id", "source", "service", "trace_id", "span_id", "operation", "started_at", "ended_at", "collected_at", "sampled", "outcome", "attributes", "diagnostic_ref", "extensions"], "trace-span");
  requireSupportedMajor(record.contract_version, "trace-span.contract_version");
  if (!id.test(record.policy_id)) fail("trace-span.policy_id invalid");
  if (!traceId.test(record.trace_id) || !spanId.test(record.span_id) || (record.parent_span_id !== undefined && !spanId.test(record.parent_span_id))) fail("trace-span must use W3C trace/span identifiers");
  validateSource(record.source, "trace-span.source");
  validateService(record.service, "trace-span.service");
  if (record.source.producer !== record.service.service_id) fail("trace-span.source.producer must match trace-span.service.service_id");
  const policy = policiesById.get(record.policy_id);
  if (!policy) fail(`trace-span references unknown policy ${record.policy_id}`);
  if (policy.service.service_id !== record.service.service_id || policy.service.instance_id !== record.service.instance_id) fail("trace-span policy must bind the same service and instance as the span");
  if (policy.default_state.instrumentation_enabled !== true || policy.default_state.export_enabled !== true || policy.sampling.rate_per_mille === 0) fail("trace-span cannot be emitted when instrumentation/export is disabled or sampling is zero");
  if (!realDateTime(record.started_at) || !realDateTime(record.ended_at) || !realDateTime(record.collected_at) || Date.parse(record.ended_at) < Date.parse(record.started_at) || Date.parse(record.collected_at) < Date.parse(record.ended_at)) fail("trace-span timestamps invalid");
  if (typeof record.sampled !== "boolean" || record.sampled !== true) fail("trace-span.sampled must be true for any emitted v1 span");
  if (!["ok", "degraded", "failed", "stale", "unknown"].includes(record.outcome)) fail("trace-span.outcome invalid");
  exact(record.operation, ["surface", "phase"], "trace-span.operation");
  if (!["task", "gateway", "service", "synthetic"].includes(record.operation.surface) || !["ingress", "queue", "execution", "dependency", "publication", "probe", "export"].includes(record.operation.phase)) fail("trace-span.operation invalid");
  validateExtensions(record.extensions, "trace-span.extensions");
  if (!opaqueRef.test(record.diagnostic_ref)) fail("trace-span.diagnostic_ref must remain content-blind");
  exact(record.attributes, Object.keys(record.attributes), "trace-span.attributes");
  const allowedKeys = new Set(["service_id", "instance_id", "dependency_service_id", "task_class", "runtime_lane", "retry_ordinal", "error_class", "check_surface"]);
  for (const key of Object.keys(record.attributes)) if (!allowedKeys.has(key)) fail(`trace-span.attributes.${key} is not on the v1 allowlist`);
  if (record.attributes.service_id !== undefined && record.attributes.service_id !== record.service.service_id) fail("trace-span.attributes.service_id must echo the top-level service_id");
  if (record.attributes.instance_id !== undefined && record.attributes.instance_id !== record.service.instance_id) fail("trace-span.attributes.instance_id must echo the top-level instance_id");
  if (record.attributes.dependency_service_id !== undefined && !id.test(record.attributes.dependency_service_id)) fail("trace-span.attributes.dependency_service_id invalid");
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
function validateTraceGraph(records, observationsById) {
  const spansByNode = new Map();
  for (const record of records) {
    if (record.kind !== "trace-span") continue;
    spansByNode.set(`${record.trace_id}:${record.span_id}`, record);
  }
  for (const record of records) {
    if (record.kind === "trace-span" && record.parent_span_id !== undefined) {
      if (record.parent_span_id === record.span_id) fail("trace-span cannot self-parent");
      const parent = spansByNode.get(`${record.trace_id}:${record.parent_span_id}`);
      if (!parent) fail(`trace-span parent ${record.parent_span_id} is missing from trace ${record.trace_id}`);
    }
    if ((record.kind === "service-observation" || record.kind === "observation-aggregate") && record.trace !== undefined) {
      const span = spansByNode.get(`${record.trace.trace_id}:${record.trace.span_id}`);
      if (!span) fail(`${record.kind} trace link must resolve to an emitted trace-span`);
      const observationService = record.service.service_id;
      if (span.service.service_id !== observationService) fail(`${record.kind} trace link must stay within the same service_id`);
      if (record.kind === "service-observation") {
        const observation = observationsById.get(record.observation_id);
        if (!observation) fail(`observation ${record.observation_id} missing from accepted set`);
      }
    }
  }
}
function validateRecordSet(records, label) {
  const observations = new Map();
  const policiesById = new Map();
  const policiesByService = new Map();
  for (const record of records) {
    rejectPrivate(record, `${label}.${record.kind ?? "record"}`);
    if (record.kind === "service-observation") observations.set(record.observation_id, record);
    if (record.kind === "trace-policy") {
      policiesById.set(record.policy_id, record);
      policiesByService.set(`${record.service.service_id}:${record.service.instance_id}`, record);
    }
  }
  for (const policy of policiesById.values()) validateTracePolicy(policy);
  for (const observation of observations.values()) validateObservation(observation);
  for (const record of records) {
    if (record.kind === "observation-aggregate") validateAggregate(record, observations, policiesByService);
    if (record.kind === "trace-span") validateTraceSpan(record, policiesById);
  }
  validateTraceGraph(records, observations);
}
function validateInventoryDerivationCases(file) {
  assert.ok(Array.isArray(file.cases) && file.cases.length > 0, "inventory-derivation fixture must contain at least one case");
  for (const testCase of file.cases) {
    exact(testCase, ["label", "authority", "service", "aggregate_producer", "expected_slots"], "inventory-derivation.case");
    validateService(testCase.service, `inventory-derivation.${testCase.label}.service`);
    if (!id.test(testCase.aggregate_producer)) fail(`inventory-derivation.${testCase.label}.aggregate_producer invalid`);
    exact(testCase.authority, ["authority_kind", "authority_ref", "authority_digest"], `inventory-derivation.${testCase.label}.authority`);
    const slots = normalizedSlots(testCase.expected_slots);
    for (const slot of slots) {
      const slotLabel = `inventory-derivation.${testCase.label}.slot.${slot.slot_id}`;
      exact(slot, slot.dependency_service_id !== undefined
        ? ["slot_id", "authority_kind", "slot_class", "surface", "applicability", "owner_kind", "owner_service_id", "max_freshness", "dependency_service_id"]
        : ["slot_id", "authority_kind", "slot_class", "surface", "applicability", "owner_kind", "owner_service_id", "max_freshness"], slotLabel);
      if (slot.authority_kind !== testCase.authority.authority_kind) fail(`${slotLabel} authority_kind must match the fixture case authority`);
      if (durationToMs(slot.max_freshness) <= 0 || durationToMs(slot.max_freshness) > MAX_SLOT_FRESHNESS_MS) fail(`${slotLabel} max_freshness must stay within the bounded ceiling`);
      if (slot.slot_class === "collector_health" && slot.owner_service_id !== testCase.aggregate_producer) fail(`inventory-derivation.${testCase.label} collector slot must be owned by ${testCase.aggregate_producer}`);
      if ((slot.slot_class === "service_liveness" || slot.slot_class === "service_readiness" || slot.slot_class === "dependency_health" || slot.slot_class === "exporter_health") && slot.owner_service_id !== testCase.service.service_id) fail(`inventory-derivation.${testCase.label} producer slot must be owned by ${testCase.service.service_id}`);
    }
    if (authorityDigest(testCase.authority, slots) !== testCase.authority.authority_digest) fail(`inventory-derivation.${testCase.label} authority digest mismatch`);
    if (testCase.authority.authority_kind === "services_json") {
      const expectedRegistrySlots = normalizedSlots(derivedServicesJsonSlots(testCase.service.service_id, slots[0].max_freshness));
      if (canonical(expectedRegistrySlots.map(slotAuthorityProjection)) !== canonical(slots.map(slotAuthorityProjection))) fail(`inventory-derivation.${testCase.label} does not match the authoritative services.json slot derivation`);
    }
  }
}

const reject = (fn, label) => assert.throws(fn, undefined, label);

checkSchema(schema);

for (const record of positive.records) schemaValid(record, `positive:${record.kind}`);
validateRecordSet(positive.records, "positive");

for (const record of mixedVersion.records) schemaValid(record, `mixed-version:${record.kind}`);
validateRecordSet(mixedVersion.records, "mixed-version");

for (const record of staleMissingPartial.records) schemaValid(record, `stale-missing-partial:${record.kind}`);
validateRecordSet(staleMissingPartial.records, "stale-missing-partial");

for (const record of unsupportedMajorRollout.records) schemaValid(record, `unsupported-major-rollout:${record.kind}`);
schemaInvalid(unsupportedMajorRollout.rejected_record, "unsupported-major-rollout:rejected-record");
validateRecordSet(unsupportedMajorRollout.records, "unsupported-major-rollout");

validateInventoryDerivationCases(inventoryDerivation);

schemaInvalid(negative.schema_malformed_diagnostic_ref, "schema-malformed-diagnostic-ref");
schemaInvalid(negative.schema_unsupported_major_observation, "schema-unsupported-major-observation");
schemaInvalid(negative.schema_tokenized_trace_error_class, "schema-tokenized-trace-error-class");
schemaInvalid(negative.schema_lifecycle_outcome_trace_attribute, "schema-lifecycle-outcome-trace-attribute");
schemaInvalid(negative.schema_extension_payload, "schema-extension-payload");

for (const [name, scenario] of Object.entries(negative)) {
  if (name.startsWith("schema_") || name === "failed_aggregate_expiry") continue;
  for (const record of scenario.records) schemaValid(record, `${name}:${record.kind}`);
  reject(() => validateRecordSet(scenario.records, name), name);
}

assert.doesNotThrow(() => rejectPrivate("git-10.0.0"), "semantic versions must not be mistaken for private IPs");

const degradedAggregate = positive.records.find((record) => record.kind === "observation-aggregate" && record.aggregate_id === "agg-hugin-overall-degraded");
assert.equal(renderEffectiveAggregateOutcome(degradedAggregate, "2026-07-31T09:16:03Z"), "stale", "render-time expiry downgrades degraded aggregate truth to stale");
const failedAggregate = negative.failed_aggregate_expiry.records.find((record) => record.kind === "observation-aggregate");
assert.equal(renderEffectiveAggregateOutcome(failedAggregate, "2026-07-31T12:16:02Z"), "failed", "render-time expiry preserves failed aggregates");

console.log("Operational-observability v1 schema, inventory digests, freshness rules, rollout handling, and trace/privacy fixtures validated.");
