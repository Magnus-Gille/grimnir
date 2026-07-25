import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const fixturesDir = path.join(root, "tests/fixtures/maintenance-policy");
const read = (name) => JSON.parse(fs.readFileSync(path.join(fixturesDir, name), "utf8"));
const schema = JSON.parse(fs.readFileSync(path.join(root, "docs/maintenance-policy-v1.schema.json"), "utf8"));

const normalWindow = read("normal-window.json");
const dstTransition = read("dst-transition.json");
const hold = read("hold.json");
const missedWindow = read("missed-window-decision.json");
const negative = read("negative.json");

const fail = (message) => { throw new Error(message); };
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const id = /^[a-z][a-z0-9-]{2,62}$/;
const digest = /^sha256:[a-f0-9]{64}$/;
const utc = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const durationPattern = /^P(?=\d|T\d)(?:(\d+)D)?(?:T(?=\d)(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/;

// ---- generic structural JSON-Schema-subset checker (mirrors tests/scripts/validate-node-substrate-contract.mjs) ----
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
const realCalendarDate = (value) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const [, year, month, day] = match;
  const asUtc = new Date(Date.UTC(Number(year), Number(month) - 1, Number(day)));
  return asUtc.getUTCFullYear() === Number(year) && asUtc.getUTCMonth() + 1 === Number(month) && asUtc.getUTCDate() === Number(day);
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
  if (node.$ref) { assert.ok(resolve(node.$ref), `unresolved ref ${node.$ref}`); assert.deepEqual(Object.keys(node).filter((key) => key !== "$ref" && !["title", "description"].includes(key)), [], `$ref siblings unsupported at ${at}`); }
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
  if (typeof value === "string") { if (node.minLength !== undefined && value.length < node.minLength) errors.push(`${at}: minLength`); if (node.pattern && !new RegExp(node.pattern).test(value)) errors.push(`${at}: pattern`); if (node.format === "date-time" && !utc.test(value)) errors.push(`${at}: date-time`); }
  if (typeof value === "number") { if (node.minimum !== undefined && value < node.minimum) errors.push(`${at}: minimum`); if (node.maximum !== undefined && value > node.maximum) errors.push(`${at}: maximum`); }
  if (Array.isArray(value)) { if (node.minItems !== undefined && value.length < node.minItems) errors.push(`${at}: minItems`); if (node.uniqueItems && new Set(value.map(canonical)).size !== value.length) errors.push(`${at}: duplicate items`); if (node.items) value.forEach((item, index) => errors.push(...schemaErrors(node.items, item, `${at}[${index}]`))); }
  if (plain(value)) {
    for (const field of node.required ?? []) if (!Object.hasOwn(value, field)) errors.push(`${at}.${field}: required`);
    for (const [field, child] of Object.entries(node.properties ?? {})) if (Object.hasOwn(value, field)) errors.push(...schemaErrors(child, value[field], `${at}.${field}`));
    if (node.additionalProperties === false) for (const field of Object.keys(value)) if (!Object.hasOwn(node.properties ?? {}, field)) errors.push(`${at}.${field}: additional property`);
  }
  return errors;
}
const schemaValid = (record, label) => assert.deepEqual(schemaErrors(schema, record), [], `${label} violates the normative v1 schema`);
const schemaInvalid = (record, label) => assert.notDeepEqual(schemaErrors(schema, record), [], `${label} must be rejected by the normative schema`);

// ---- shared helpers ----
const fields = (value, names, label) => { if (!plain(value)) fail(`${label} must be object`); for (const name of names) if (!Object.hasOwn(value, name)) fail(`${label}.${name} missing`); };
const exact = (value, names, label) => { fields(value, names, label); for (const key of Object.keys(value)) if (!names.includes(key)) fail(`${label}.${key} is not a v1 field`); };
function rejectPrivate(value, label = "$") {
  if (typeof value === "string") { if (/(?:\b(?:10|127|192\.168)\.|\b172\.(?:1[6-9]|2\d|3[01])\.)|\/Users\/|\.ssh\/|password=|token=|\bsudo\b|\brm\s+-rf\b|\bssh\s+\S+@/i.test(value)) fail(`${label} contains private locator, credential-like data, or a shell command`); return; }
  if (Array.isArray(value)) return value.forEach((item, index) => rejectPrivate(item, `${label}[${index}]`));
  if (plain(value)) for (const [key, item] of Object.entries(value)) { if (/^(?:wifi_?ssid|ssid|wifi_?name|credential|token|password|shell_hint)$/i.test(key)) fail(`${label}.${key} is private identity or shell material`); rejectPrivate(item, `${label}.${key}`); }
}
function extensions(value, label) { if (!Array.isArray(value)) fail(`${label}.extensions must be array`); const seen = new Set(); for (const item of value) { exact(item, ["id", "version", "decision_effect"], `${label}.extension`); if (!id.test(item.id) || !/^v[1-9][0-9]*$/.test(item.version) || item.decision_effect !== "informational" || seen.has(item.id)) fail(`${label}.extension invalid or decision-driving`); seen.add(item.id); } }

// ---- canonical JCS-style digest (maintenance-policy-digest-jcs-v1); must match docs/maintenance-policy-contract.md ----
function canonicalJson(value) {
  if (value === null || typeof value === "number" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
  if (plain(value)) return "{" + Object.keys(value).sort().map((key) => JSON.stringify(key) + ":" + canonicalJson(value[key])).join(",") + "}";
  fail(`unsupported value type for canonicalization: ${typeof value}`);
}
function policyDigest(record) {
  const rest = { ...record };
  delete rest.policy_digest;
  return "sha256:" + crypto.createHash("sha256").update(canonicalJson(rest), "utf8").digest("hex");
}

// ---- duration ----
function durationToMs(value) {
  const match = durationPattern.exec(value);
  if (!match) fail(`invalid duration ${value}`);
  const [, d, h, mi, s] = match;
  return ((Number(d || 0) * 24 + Number(h || 0)) * 60 + Number(mi || 0)) * 60000 + Number(s || 0) * 1000;
}

// ---- IANA timezone ----
const knownTimeZones = new Set(Intl.supportedValuesOf("timeZone"));
const isValidTimeZone = (tz) => tz === "UTC" || knownTimeZones.has(tz);

// ---- DST-aware local-time resolution (uses only built-in Intl; no external tz database) ----
function wallClockParts(instantMs, timeZone) {
  const dtf = new Intl.DateTimeFormat("en-US", { timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const parts = Object.fromEntries(dtf.formatToParts(new Date(instantMs)).filter((p) => p.type !== "literal").map((p) => [p.type, parseInt(p.value, 10)]));
  return { year: parts.year, month: parts.month, day: parts.day, hour: parts.hour === 24 ? 0 : parts.hour, minute: parts.minute, second: parts.second };
}
function tzOffsetMinutes(instantMs, timeZone) {
  const p = wallClockParts(instantMs, timeZone);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return Math.round((asUtc - instantMs) / 60000);
}
function classifyLocalTime(year, month, day, hour, minute, second, timeZone) {
  const wallAsUtc = Date.UTC(year, month - 1, day, hour, minute, second);
  const DAY = 24 * 3600 * 1000;
  const offsetEarly = tzOffsetMinutes(wallAsUtc - DAY, timeZone);
  const offsetLate = tzOffsetMinutes(wallAsUtc + DAY, timeZone);
  const candEarly = wallAsUtc - offsetEarly * 60000;
  const candLate = wallAsUtc - offsetLate * 60000;
  const reads = (instant) => { const p = wallClockParts(instant, timeZone); return p.year === year && p.month === month && p.day === day && p.hour === hour && p.minute === minute && p.second === second; };
  if (offsetEarly === offsetLate) return { kind: "normal", instant: candEarly };
  const earlyOk = reads(candEarly);
  const lateOk = reads(candLate);
  if (earlyOk && lateOk) return { kind: "ambiguous", first: Math.min(candEarly, candLate), second: Math.max(candEarly, candLate) };
  if (!earlyOk && !lateOk) return { kind: "nonexistent", shiftForward: Math.max(candEarly, candLate) };
  return { kind: "normal", instant: earlyOk ? candEarly : candLate };
}
const weekdayOf = (localDate) => { const [y, m, d] = localDate.split("-").map(Number); return ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][new Date(Date.UTC(y, m - 1, d)).getUTCDay()]; };

// ---- semantic: maintenance-policy ----
const POLICY_FIELDS = ["kind", "schema_version", "policy_id", "selector", "timezone", "dst_policy", "window", "missed_window", "overdue", "maximum_deferral", "state", "updates", "reboot", "execution_limits", "concurrency", "failure_limits", "policy_digest", "created_at", "extensions"];
function validatePolicy(record) {
  exact(record, POLICY_FIELDS, "policy");
  if (!id.test(record.policy_id)) fail("policy_id invalid");
  exact(record.selector, ["node_ids", "workload_ids"], "policy.selector");
  if (!record.selector.node_ids.every((v) => id.test(v)) || !record.selector.workload_ids.every((v) => id.test(v))) fail("selector ids invalid");
  if (record.selector.node_ids.length + record.selector.workload_ids.length === 0) fail("selector must reference at least one node or workload");
  if (!isValidTimeZone(record.timezone)) fail(`unknown IANA timezone ${record.timezone}`);
  exact(record.dst_policy, ["nonexistent_time", "ambiguous_time"], "policy.dst_policy");
  exact(record.window, ["days_of_week", "start_local_time", "duration"], "policy.window");
  const windowMs = durationToMs(record.window.duration);
  if (windowMs < 60000 || windowMs > 86400000) fail("window duration must be between PT1M and P1D");
  exact(record.missed_window, ["behavior"], "policy.missed_window");
  exact(record.overdue, ["after_missed_windows", "behavior"], "policy.overdue");
  exact(record.maximum_deferral, ["duration"], "policy.maximum_deferral");
  if (durationToMs(record.maximum_deferral.duration) <= 0) fail("maximum_deferral must be positive");
  exact(record.state, ["enabled", "hold"], "policy.state");
  const hold = record.state.hold;
  if (hold.active) { exact(hold, ["active", "reason", "until"], "policy.state.hold"); if (hold.reason === "not_applicable") fail("active hold requires a real reason"); }
  else { exact(hold, ["active", "reason"], "policy.state.hold"); if (hold.reason !== "not_applicable") fail("inactive hold must use reason not_applicable and omit until"); }
  exact(record.updates, ["allowed_classes", "allowed_sources"], "policy.updates");
  exact(record.reboot, ["policy", "max_reboot_wait"], "policy.reboot");
  const rebootWaitMs = durationToMs(record.reboot.max_reboot_wait);
  if (record.reboot.policy === "never" ? rebootWaitMs !== 0 : rebootWaitMs <= 0) fail("max_reboot_wait inconsistent with reboot policy");
  exact(record.execution_limits, ["timeout", "retry"], "policy.execution_limits");
  if (durationToMs(record.execution_limits.timeout) <= 0) fail("execution timeout must be positive");
  exact(record.execution_limits.retry, ["max_attempts", "backoff"], "policy.execution_limits.retry");
  const backoffMs = durationToMs(record.execution_limits.retry.backoff);
  if (record.execution_limits.retry.max_attempts === 1 ? backoffMs !== 0 : backoffMs <= 0) fail("retry backoff inconsistent with max_attempts");
  exact(record.concurrency, record.concurrency.canary_count !== undefined ? ["max_concurrent_targets", "ordering", "canary_count"] : ["max_concurrent_targets", "ordering"], "policy.concurrency");
  const totalTargets = record.selector.node_ids.length + record.selector.workload_ids.length;
  if (record.concurrency.ordering === "canary_then_remaining") { if (!(record.concurrency.canary_count >= 1) || record.concurrency.canary_count >= totalTargets) fail("canary_count must be set and smaller than the total selector target count"); }
  else if (record.concurrency.canary_count !== undefined) fail("canary_count is only valid with ordering=canary_then_remaining");
  exact(record.failure_limits, ["max_consecutive_failures", "on_limit_exceeded"], "policy.failure_limits");
  if (!realDateTime(record.created_at)) fail("created_at is not a real calendar instant");
  extensions(record.extensions, "policy");
  if (record.policy_digest !== policyDigest(record)) fail("policy_digest does not match the recomputed maintenance-policy-digest-jcs-v1 digest");
}

// ---- semantic: maintenance-decision ----
const DECISION_FIELDS = ["kind", "schema_version", "decision_id", "policy_id", "policy_digest", "evidence", "as_of", "window_occurrence", "missed_occurrences", "deferral_elapsed", "effect", "reason", "extensions"];
function decisionEffect(policy, decision) {
  if (policy.state.enabled === false) return { effect: "held", reason: "disabled" };
  if (policy.state.hold.active === true) return { effect: "held", reason: "hold_active" };
  if (decision.missed_occurrences === 0) return { effect: "on_schedule", reason: "on_schedule" };
  const deferralMs = durationToMs(decision.deferral_elapsed);
  const maxDeferralMs = durationToMs(policy.maximum_deferral.duration);
  if (deferralMs > maxDeferralMs) return { effect: "escalate_operator_gate", reason: "maximum_deferral_reached" };
  if (decision.missed_occurrences >= policy.overdue.after_missed_windows) {
    return { escalate_operator_gate: { effect: "escalate_operator_gate", reason: "overdue_after_missed_windows" }, run_as_soon_as_possible: { effect: "run_deferred", reason: "overdue_after_missed_windows" }, hold: { effect: "held", reason: "overdue_after_missed_windows" } }[policy.overdue.behavior];
  }
  return { run_at_next_window: { effect: "deferred_to_next_window", reason: "missed_window" }, run_as_soon_as_possible: { effect: "run_deferred", reason: "missed_window" }, skip_occurrence: { effect: "skip_occurrence", reason: "missed_window" } }[policy.missed_window.behavior];
}
function validateDecision(record, policies) {
  exact(record, DECISION_FIELDS, "decision");
  if (!id.test(record.decision_id) || !id.test(record.policy_id)) fail("decision id invalid");
  const policy = policies[record.policy_id];
  if (!policy) fail(`decision references unknown policy_id ${record.policy_id}`);
  if (record.policy_digest !== policyDigest(policy)) fail("decision policy_digest does not match the referenced policy's recomputed digest");
  exact(record.evidence, ["evidence_id", "producer", "observed_at", "digest"], "decision.evidence");
  if (!id.test(record.evidence.evidence_id) || record.evidence.producer !== "brokkr" || !digest.test(record.evidence.digest)) fail("decision evidence malformed");
  if (!realDateTime(record.evidence.observed_at) || !realDateTime(record.as_of)) fail("decision clocks are not real calendar instants");
  if (Date.parse(record.evidence.observed_at) > Date.parse(record.as_of)) fail("evidence cannot be later than the decision instant");
  exact(record.window_occurrence, ["local_date", "start", "end", "local_time_kind"], "decision.window_occurrence");
  if (!realCalendarDate(record.window_occurrence.local_date)) fail("window_occurrence.local_date is not a real calendar date");
  if (!realDateTime(record.window_occurrence.start) || !realDateTime(record.window_occurrence.end)) fail("window_occurrence clocks are not real calendar instants");
  if (Date.parse(record.window_occurrence.end) <= Date.parse(record.window_occurrence.start)) fail("window_occurrence.end must be after start");
  if (Date.parse(record.window_occurrence.end) - Date.parse(record.window_occurrence.start) !== durationToMs(policy.window.duration)) fail("window_occurrence span does not match the policy window duration");
  if (!policy.window.days_of_week.includes(weekdayOf(record.window_occurrence.local_date))) fail("window_occurrence.local_date does not fall on a scheduled weekday");
  const [hh, mm] = policy.window.start_local_time.split(":").map(Number);
  const [y, mo, d] = record.window_occurrence.local_date.split("-").map(Number);
  const resolved = classifyLocalTime(y, mo, d, hh, mm, 0, policy.timezone);
  if (resolved.kind !== record.window_occurrence.local_time_kind) fail(`window_occurrence.local_time_kind should be ${resolved.kind}`);
  const startMs = Date.parse(record.window_occurrence.start);
  if (resolved.kind === "normal") { if (startMs !== resolved.instant) fail("window_occurrence.start does not match the unambiguous resolved instant"); }
  else if (resolved.kind === "nonexistent") {
    if (policy.dst_policy.nonexistent_time !== "shift_forward_to_next_valid") fail(`a decision cannot exist for a nonexistent local time under nonexistent_time=${policy.dst_policy.nonexistent_time}`);
    if (startMs !== resolved.shiftForward) fail("window_occurrence.start does not match the shift-forward resolved instant");
  } else {
    if (policy.dst_policy.ambiguous_time === "fail_closed") fail("a decision cannot exist for an ambiguous local time under ambiguous_time=fail_closed");
    const expected = policy.dst_policy.ambiguous_time === "use_first_instant" ? resolved.first : resolved.second;
    if (startMs !== expected) fail(`window_occurrence.start does not match the ${policy.dst_policy.ambiguous_time} resolved instant`);
  }
  if (record.missed_occurrences === 0) { if (durationToMs(record.deferral_elapsed) !== 0) fail("deferral_elapsed must be PT0S when nothing was missed"); }
  else { if (durationToMs(record.deferral_elapsed) !== Date.parse(record.as_of) - startMs) fail("deferral_elapsed must equal as_of minus the earliest missed occurrence's start"); }
  extensions(record.extensions, "decision");
  const expected = decisionEffect(policy, record);
  if (record.effect !== expected.effect || record.reason !== expected.reason) fail(`decision-effect mismatch: expected ${expected.effect}/${expected.reason}, got ${record.effect}/${record.reason}`);
}

function semantic(record, policies) {
  rejectPrivate(record);
  if (record.schema_version !== "v1") fail("unsupported schema_version");
  if (record.kind === "maintenance-policy") return validatePolicy(record);
  if (record.kind === "maintenance-decision") return validateDecision(record, policies);
  fail(`unknown record kind ${record.kind}`);
}
const reject = (fn, label) => assert.throws(fn, undefined, label);

// ---- run ----
checkSchema(schema);

const positiveFiles = [normalWindow, dstTransition, hold, missedWindow];
const policies = {};
for (const file of positiveFiles) for (const record of file.records) if (record.kind === "maintenance-policy") { schemaValid(record, record.policy_id); validatePolicy(record); policies[record.policy_id] = record; }
schemaValid(negative.fail_closed_ambiguous_policy, "fail_closed_ambiguous_policy");
validatePolicy(negative.fail_closed_ambiguous_policy);
policies[negative.fail_closed_ambiguous_policy.policy_id] = negative.fail_closed_ambiguous_policy;

for (const file of positiveFiles) for (const record of file.records) if (record.kind === "maintenance-decision") { schemaValid(record, record.decision_id); validateDecision(record, policies); }

// digest determinism: recompute + stable across (deep, nested) key reordering + independently recomputable
function shuffleKeysDeep(value) {
  if (Array.isArray(value)) return value.map(shuffleKeysDeep);
  if (plain(value)) { const out = {}; for (const key of Object.keys(value).reverse()) out[key] = shuffleKeysDeep(value[key]); return out; }
  return value;
}
for (const p of Object.values(policies)) {
  assert.equal(policyDigest(p), p.policy_digest, `${p.policy_id} digest must be recomputable`);
  const reordered = shuffleKeysDeep(p);
  assert.notDeepEqual(Object.keys(reordered), Object.keys(p), `${p.policy_id} reordering fixture must actually change top-level key order`);
  assert.deepEqual(reordered, p, `${p.policy_id} reordering must not change any value`);
  assert.equal(policyDigest(reordered), p.policy_digest, `${p.policy_id} digest must be stable across deep key reordering`);
}

// ---- adversarial: fail closed for the intended reason ----
schemaValid(negative.invalid_timezone, "invalid_timezone (schema-valid shape)");
reject(() => validatePolicy(negative.invalid_timezone), "invalid IANA timezone");
schemaInvalid(negative.invalid_dst_policy, "invalid dst_policy enum value");
schemaInvalid(negative.unknown_field, "unknown top-level field");
schemaInvalid(negative.invalid_duration, "invalid ISO 8601 duration (year component)");
schemaInvalid(negative.unsafe_update, "unsafe update source");
schemaValid(negative.impossible_calendar_date, "impossible_calendar_date (schema-valid shape)");
reject(() => validatePolicy(negative.impossible_calendar_date), "impossible calendar date (2026-02-30)");
schemaValid(negative.fail_closed_ambiguous_decision, "fail_closed_ambiguous_decision (schema-valid shape)");
reject(() => validateDecision(negative.fail_closed_ambiguous_decision, policies), "decision for an ambiguous time under ambiguous_time=fail_closed");
schemaValid(negative.decision_digest_mismatch, "decision_digest_mismatch (schema-valid shape)");
reject(() => validateDecision(negative.decision_digest_mismatch, policies), "decision policy_digest binding mismatch");
schemaValid(negative.decision_effect_mismatch, "decision_effect_mismatch (schema-valid shape)");
reject(() => validateDecision(negative.decision_effect_mismatch, policies), "decision-effect rule mismatch");
schemaValid(negative.decision_unknown_policy, "decision_unknown_policy (schema-valid shape)");
reject(() => validateDecision(negative.decision_unknown_policy, policies), "decision references an unknown policy");
reject(() => rejectPrivate(negative.privacy_adversarial), "privacy/credential/shell-command adversarial fixture");

// extra inline adversarial: unsafe update *class* (not just source), and duration edge forms
const unsafeClass = structuredClone(policies["policy-normal-window"]);
unsafeClass.updates = { allowed_classes: ["feature"], allowed_sources: ["distro_repository"] };
schemaInvalid(unsafeClass, "unsafe update class");
for (const bad of ["P", "PT", "P1M", "7D", "PT-1H", "P1D1H"]) assert.ok(!durationPattern.test(bad), `duration pattern must reject ${bad}`);
for (const good of ["P1D", "PT1H", "PT1M", "PT1S", "P1DT2H3M4S", "PT0S"]) assert.ok(durationPattern.test(good), `duration pattern must accept ${good}`);

console.log("Maintenance-policy v1 normative schema plus hermetic positive/adversarial fixture scenarios validated.");
