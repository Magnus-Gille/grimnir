import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const fixtureDir = path.join(root, "tests/fixtures/physical-agent-control");
const readJson = (file) => JSON.parse(fs.readFileSync(path.join(fixtureDir, file), "utf8"));
const readDocJson = (file) => JSON.parse(fs.readFileSync(path.join(root, "docs", file), "utf8"));
const schema = readDocJson("physical-agent-control-v1.schema.json");
const profileSchema = readDocJson("physical-agent-control-profile-v1.schema.json");
const profile = readJson("active-profile.json");
const intents = readJson("positive-intents.json");
const states = readJson("positive-states.json");
const negative = readJson("negative.json");
const context = readJson("validation-context.json");

const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const utcPattern = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;

function canonicalize(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonicalize).join(",") + "]";
  return "{" + Object.keys(value).sort().map((key) => JSON.stringify(key) + ":" + canonicalize(value[key])).join(",") + "}";
}

const jsonEqual = (left, right) => canonicalize(left) === canonicalize(right);

function dateTime(value) {
  const match = utcPattern.exec(value);
  if (!match) return false;
  const instant = new Date(value);
  if (Number.isNaN(instant.getTime())) return false;
  const [, year, month, day, hour, minute, second] = match;
  return (
    instant.getUTCFullYear() === Number(year) &&
    instant.getUTCMonth() + 1 === Number(month) &&
    instant.getUTCDate() === Number(day) &&
    instant.getUTCHours() === Number(hour) &&
    instant.getUTCMinutes() === Number(minute) &&
    instant.getUTCSeconds() === Number(second)
  );
}

function resolve(rootSchema, ref) {
  assert.ok(ref.startsWith("#/"), "schema references must stay inside the contract");
  const resolved = ref.slice(2).split("/").reduce(
    (value, raw) => value?.[raw.replaceAll("~1", "/").replaceAll("~0", "~")],
    rootSchema
  );
  assert.ok(resolved, "schema reference must resolve: " + ref);
  return resolved;
}

const supportedSchemaKeywords = new Set([
  "$schema", "$id", "$defs", "$ref", "title", "description", "oneOf", "const", "enum",
  "type", "minLength", "maxLength", "pattern", "format", "minimum", "maximum",
  "minItems", "maxItems", "uniqueItems", "items", "required", "properties", "additionalProperties"
]);

function checkSchema(rootSchema, node = rootSchema, at = "$") {
  if (typeof node === "boolean") return;
  assert.ok(plain(node), "schema node must be an object at " + at);
  for (const keyword of Object.keys(node)) {
    assert.ok(supportedSchemaKeywords.has(keyword), "unsupported JSON Schema keyword " + keyword + " at " + at);
  }
  if (node.$ref) {
    resolve(rootSchema, node.$ref);
    const siblings = Object.keys(node).filter((key) => !["$ref", "title", "description"].includes(key));
    assert.deepEqual(siblings, [], "$ref validation siblings are unsupported at " + at);
  }
  if (node.oneOf) {
    const siblings = Object.keys(node).filter(
      (key) => !["oneOf", "title", "description", "$schema", "$id", "$defs"].includes(key)
    );
    assert.deepEqual(siblings, [], "oneOf validation siblings are unsupported at " + at);
  }
  if (node.type) {
    assert.ok(
      ["object", "array", "string", "integer", "boolean", "null"].includes(node.type),
      "unsupported schema type at " + at
    );
  }
  if (node.format) assert.equal(node.format, "date-time", "unsupported schema format at " + at);
  if (node.additionalProperties !== undefined) {
    assert.equal(typeof node.additionalProperties, "boolean", "additionalProperties must be boolean at " + at);
  }
  for (const [key, child] of Object.entries(node.properties ?? {})) {
    checkSchema(rootSchema, child, at + ".properties." + key);
  }
  for (const [key, child] of Object.entries(node.$defs ?? {})) {
    checkSchema(rootSchema, child, at + ".$defs." + key);
  }
  if (node.items) checkSchema(rootSchema, node.items, at + ".items");
  for (const [index, child] of (node.oneOf ?? []).entries()) {
    checkSchema(rootSchema, child, at + ".oneOf[" + index + "]");
  }
}

function typeMatches(type, value) {
  return {
    object: plain(value),
    array: Array.isArray(value),
    string: typeof value === "string",
    integer: Number.isInteger(value),
    boolean: typeof value === "boolean",
    null: value === null
  }[type] === true;
}

function schemaErrors(rootSchema, node, value, at = "$") {
  if (node === true) return [];
  if (node === false) return [at + ": forbidden"];
  if (node.$ref) return schemaErrors(rootSchema, resolve(rootSchema, node.$ref), value, at);
  if (node.oneOf) {
    const attempts = node.oneOf.map((child) => schemaErrors(rootSchema, child, value, at));
    return attempts.filter((errors) => errors.length === 0).length === 1
      ? []
      : [at + ": expected exactly one schema branch (" + attempts.flat().join("; ") + ")"];
  }
  const errors = [];
  if (Object.hasOwn(node, "const") && !jsonEqual(value, node.const)) errors.push(at + ": const mismatch");
  if (node.enum && !node.enum.some((candidate) => jsonEqual(value, candidate))) errors.push(at + ": enum mismatch");
  if (node.type && !typeMatches(node.type, value)) return errors.concat(at + ": expected " + node.type);
  if (typeof value === "string") {
    if (node.minLength !== undefined && value.length < node.minLength) errors.push(at + ": minLength");
    if (node.maxLength !== undefined && value.length > node.maxLength) errors.push(at + ": maxLength");
    if (node.pattern && !new RegExp(node.pattern).test(value)) errors.push(at + ": pattern");
    if (node.format === "date-time" && !dateTime(value)) errors.push(at + ": date-time");
  }
  if (typeof value === "number") {
    if (node.minimum !== undefined && value < node.minimum) errors.push(at + ": minimum");
    if (node.maximum !== undefined && value > node.maximum) errors.push(at + ": maximum");
  }
  if (Array.isArray(value)) {
    if (node.minItems !== undefined && value.length < node.minItems) errors.push(at + ": minItems");
    if (node.maxItems !== undefined && value.length > node.maxItems) errors.push(at + ": maxItems");
    if (node.uniqueItems && new Set(value.map(canonicalize)).size !== value.length) {
      errors.push(at + ": duplicate items");
    }
    if (node.items) {
      value.forEach((item, index) => errors.push(...schemaErrors(rootSchema, node.items, item, at + "[" + index + "]")));
    }
  }
  if (plain(value)) {
    for (const field of node.required ?? []) {
      if (!Object.hasOwn(value, field)) errors.push(at + "." + field + ": required");
    }
    for (const [field, child] of Object.entries(node.properties ?? {})) {
      if (Object.hasOwn(value, field)) {
        errors.push(...schemaErrors(rootSchema, child, value[field], at + "." + field));
      }
    }
    if (node.additionalProperties === false) {
      for (const field of Object.keys(value)) {
        if (!Object.hasOwn(node.properties ?? {}, field)) errors.push(at + "." + field + ": additional property");
      }
    }
  }
  return errors;
}

const actionPolicy = {
  "refresh-local-state": ["presentation", "local-only", "none", "none"],
  "open-session": ["presentation", "local-only", "none", "none"],
  "focus-session": ["presentation", "local-only", "none", "none"],
  "set-notification-level": ["preference", "local-only", "none", "none"],
  "set-effort": ["preference", "local-only", "none", "none"],
  "set-verbosity": ["preference", "local-only", "none", "none"],
  "set-display-detail": ["preference", "local-only", "none", "none"],
  "set-delegation-preference": ["preference", "local-only", "none", "none"],
  "request-status-turn": ["read-only", "target-read-only", "hold", "none"],
  "request-read-only-review": ["read-only", "target-read-only", "hold", "none"],
  "request-task-template": ["consequential", "hugin-gated", "hold", "none"],
  interrupt: ["authority-reducing", "local-reducing", "hold", "reduce"],
  pause: ["authority-reducing", "local-reducing", "hold", "reduce"]
};

function sourceSelector(source) {
  if (source.device === "stream-deck") {
    const { device, transport, control, gesture } = source;
    return { device, transport, control, gesture };
  }
  const { device, transport, midi_channel, cc, gesture } = source;
  return { device, transport, midi_channel, cc, gesture };
}

function validateTx6Selector(source, effect) {
  const { cc, gesture } = source;
  if (cc >= 1 && cc <= 24) {
    if (gesture !== "absolute") throw new Error("TX-6 controls 1-24 require an absolute selector");
    if (effect !== "preference") throw new Error("continuous TX-6 controls may only set local preferences");
  } else if (cc === 31) {
    if (gesture !== "relative") throw new Error("TX-6 encoder CC31 requires a relative selector");
    if (effect !== "preference") throw new Error("continuous TX-6 controls may only set local preferences");
  } else if (!["press", "release", "hold"].includes(gesture)) {
    throw new Error("TX-6 button controls require a press, release, or hold selector");
  }
}

function profileDigest(record) {
  const payload = structuredClone(record);
  delete payload.profile_digest;
  return "sha256:" + crypto.createHash("sha256").update(canonicalize(payload), "utf8").digest("hex");
}

function validateProfile(record) {
  const errors = schemaErrors(profileSchema, profileSchema, record);
  if (errors.length) throw new Error("profile schema: " + errors.join("; "));
  if (record.digest_algorithm !== "profile-jcs-sha256-v1" || record.profile_digest !== profileDigest(record)) {
    throw new Error("profile digest mismatch");
  }
  const bindingIds = new Set();
  const selectors = new Set();
  for (const binding of record.bindings) {
    if (bindingIds.has(binding.binding_id)) throw new Error("duplicate profile binding_id");
    bindingIds.add(binding.binding_id);
    const selector = canonicalize(binding.source);
    if (selectors.has(selector)) throw new Error("duplicate profile source selector");
    selectors.add(selector);

    const policy = actionPolicy[binding.action.name];
    if (!policy) throw new Error("unknown profile action");
    if (binding.source.device === "tx-6") validateTx6Selector(binding.source, policy[0]);
    if (policy[2] === "hold" && binding.source.gesture !== "hold") {
      throw new Error("hold-confirmed profile action requires a hold selector");
    }
    if (policy[0] === "authority-reducing" && binding.target.ownership !== "adapter-owned") {
      throw new Error("authority-reducing profile action requires an adapter-owned target");
    }
  }
}

function validateIntent(record, evaluatedAt) {
  if (!dateTime(evaluatedAt)) throw new Error("trusted intent evaluation time is required");
  const expected = actionPolicy[record.action.name];
  if (!expected) throw new Error("unknown action policy");
  const actual = [
    record.safety.effect,
    record.safety.route,
    record.safety.confirmation,
    record.safety.authority_delta
  ];
  if (!jsonEqual(actual, expected)) throw new Error("action safety policy mismatch for " + record.action.name);

  const occurred = Date.parse(record.occurred_at);
  const received = Date.parse(record.received_at);
  const evaluated = Date.parse(evaluatedAt);
  const expires = Date.parse(record.expires_at);
  if (received < occurred) throw new Error("intent received before it occurred");
  if (received >= expires) throw new Error("intent expired before receipt");
  if (evaluated < received) throw new Error("intent evaluated before receipt");
  if (evaluated >= expires) throw new Error("intent expired at evaluation");
  if (expires <= occurred || expires - occurred > 5000) {
    throw new Error("intent lifetime must be positive and at most five seconds");
  }

  if (record.source.device === "tx-6") {
    const { cc, gesture, value } = record.source;
    validateTx6Selector(record.source, record.safety.effect);
    if (cc >= 1 && cc <= 24 && (value < 0 || value > 127)) {
      throw new Error("TX-6 continuous controls 1-24 require absolute 0-127 values");
    }
    if (cc === 31 && (value < -64 || value > 63)) {
      throw new Error("TX-6 encoder CC31 requires a relative -64..63 value");
    }
    if (
      cc !== 31 &&
      (cc < 1 || cc > 24) &&
      (gesture === "release" ? value !== 0 : value !== 127)
    ) {
      throw new Error("TX-6 button controls require press/hold 127 or release 0");
    }
  }

  if (
    record.binding.profile_id !== profile.profile_id ||
    record.binding.profile_version !== profile.profile_version ||
    record.binding.profile_digest !== profile.profile_digest
  ) {
    throw new Error("inactive profile binding");
  }
  if (record.safety.confirmation === "hold" && record.source.gesture !== "hold") {
    throw new Error("hold-confirmed actions require a physical hold gesture");
  }
  if (record.safety.effect === "authority-reducing" && record.target.ownership !== "adapter-owned") {
    throw new Error("authority-reducing actions require an exact adapter-owned target");
  }
  const binding = profile.bindings.find((candidate) => candidate.binding_id === record.binding.binding_id);
  if (
    !binding ||
    !jsonEqual(binding.source, sourceSelector(record.source)) ||
    !jsonEqual(binding.target, record.target) ||
    binding.action.name !== record.action.name ||
    (binding.action.name === "request-task-template" && binding.action.template_id !== record.action.template_id)
  ) {
    throw new Error("profile binding mismatch");
  }
}

function validateState(record, evaluatedAt) {
  if (!dateTime(evaluatedAt)) throw new Error("trusted state evaluation time is required");
  const evaluated = Date.parse(evaluatedAt);
  const observed = Date.parse(record.observed_at);
  const updated = Date.parse(record.updated_at);
  if (observed > evaluated) throw new Error("state observation cannot be later than evaluation");
  if (updated > observed) throw new Error("state update cannot be later than observation");

  const expectedAdapter = {
    codex: "codex-app-server",
    "claude-code": "claude-stream-json",
    pi: "pi-rpc"
  }[record.target.harness];
  if (record.producer.adapter !== expectedAdapter) throw new Error("state producer adapter mismatch");
  const nativeSource = context.native_sources.find(
    (candidate) =>
      candidate.adapter === record.producer.adapter &&
      candidate.source_ref === record.producer.source_ref &&
      candidate.harness === record.target.harness &&
      candidate.session_ref === record.target.session_ref
  );
  if (!nativeSource) throw new Error("state producer source/target mismatch");

  const evidence = record.workflow_evidence;
  if (record.workflow === "done" && evidence.kind !== "structured-report") {
    throw new Error("done requires a structured workflow report");
  }
  if (evidence.kind === "none" && record.workflow !== "unknown") {
    throw new Error("workflow evidence none is valid only for unknown workflow state");
  }
  if (evidence.kind === "structured-report") {
    const report = context.native_reports.find(
      (candidate) =>
        candidate.report_ref === evidence.report_ref &&
        candidate.report_digest === evidence.report_digest &&
        candidate.adapter === record.producer.adapter &&
        candidate.source_ref === record.producer.source_ref &&
        candidate.harness === record.target.harness &&
        candidate.session_ref === record.target.session_ref &&
        candidate.workflow === record.workflow
    );
    if (!report) throw new Error("structured workflow report mismatch");
  }

  const ageSeconds = (evaluated - updated) / 1000;
  const expectedFreshness = ageSeconds <= context.freshness_seconds.fresh_through
    ? "fresh"
    : ageSeconds <= context.freshness_seconds.aging_through
      ? "aging"
      : "stale";
  if (record.freshness !== expectedFreshness) throw new Error("state freshness mismatch");
}

function validateRecord(record, evaluatedAt) {
  const errors = schemaErrors(schema, schema, record);
  if (errors.length) throw new Error("schema: " + errors.join("; "));
  if (record.kind === "physical-control-intent") validateIntent(record, evaluatedAt);
  else if (record.kind === "physical-control-state") validateState(record, evaluatedAt);
  else throw new Error("unknown record kind");
}

function activationFingerprint(record) {
  return canonicalize({
    binding: record.binding,
    source: record.source,
    target: record.target,
    action: record.action,
    safety: record.safety
  });
}

function classifyActivation(history, candidate) {
  const sameId = history.find((entry) => entry.record.intent_id === candidate.intent_id);
  if (sameId) {
    return jsonEqual(sameId.record, candidate)
      ? {
          status: "ignored-duplicate-intent",
          prior_intent_id: sameId.record.intent_id,
          prior_disposition: sameId.disposition
        }
      : {
          status: "rejected-intent-conflict",
          prior_intent_id: sameId.record.intent_id,
          prior_disposition: sameId.disposition
        };
  }
  const sameKey = history.find((entry) => entry.record.idempotency_key === candidate.idempotency_key);
  if (sameKey) {
    return activationFingerprint(sameKey.record) === activationFingerprint(candidate)
      ? {
          status: "replayed-prior-disposition",
          prior_intent_id: sameKey.record.intent_id,
          prior_disposition: sameKey.disposition
        }
      : {
          status: "rejected-idempotency-conflict",
          prior_intent_id: sameKey.record.intent_id,
          prior_disposition: sameKey.disposition
        };
  }
  const previousSequence = history
    .map((entry) => entry.record)
    .filter((record) => record.stream_id === candidate.stream_id)
    .reduce((maximum, record) => Math.max(maximum, record.sequence), 0);
  if (candidate.sequence <= previousSequence) return { status: "rejected-out-of-order" };
  return { status: "accepted" };
}

checkSchema(schema);
checkSchema(profileSchema);
validateProfile(profile);

const acceptedHistory = [];
for (const record of intents) {
  validateRecord(record, context.intent_evaluated_at[record.intent_id]);
  assert.equal(
    classifyActivation(acceptedHistory, record).status,
    "accepted",
    record.intent_id + " must activate once"
  );
  acceptedHistory.push({ record, disposition: "accepted" });
}
for (const record of states) validateRecord(record, context.state_evaluated_at);

const bases = new Map(
  [...intents, ...states].map((record) => [
    record.kind === "physical-control-intent" ? record.intent_id : record.state_id,
    record
  ])
);

for (const testCase of negative) {
  if (testCase.scope === "profile") {
    const candidate = structuredClone(profile);
    for (const mutation of testCase.mutations) {
      let target = candidate;
      for (const segment of mutation.path.slice(0, -1)) target = target[segment];
      target[mutation.path.at(-1)] = mutation.value;
    }
    if (testCase.recompute_digest) candidate.profile_digest = profileDigest(candidate);
    assert.throws(() => validateProfile(candidate), new RegExp(testCase.expected), testCase.name + " must fail closed");
    continue;
  }

  const base = bases.get(testCase.base);
  assert.ok(base, "negative fixture " + testCase.name + " references an unknown base");
  const candidate = structuredClone(base);
  for (const mutation of testCase.mutations) {
    let target = candidate;
    for (const segment of mutation.path.slice(0, -1)) target = target[segment];
    target[mutation.path.at(-1)] = mutation.value;
  }
  const evaluatedAt = testCase.evaluated_at ?? (
    candidate.kind === "physical-control-intent"
      ? context.intent_evaluated_at[testCase.base]
      : context.state_evaluated_at
  );

  if (testCase.scope === "collection") {
    validateRecord(candidate, evaluatedAt);
    const disposition = classifyActivation(acceptedHistory, candidate);
    assert.equal(
      disposition.status,
      testCase.expected_disposition,
      testCase.name + " must suppress activation with the expected disposition"
    );
    if (testCase.expected_prior_disposition) {
      assert.equal(
        disposition.prior_disposition,
        testCase.expected_prior_disposition,
        testCase.name + " must return the stored prior disposition"
      );
    }
  } else {
    assert.throws(
      () => validateRecord(candidate, evaluatedAt),
      new RegExp(testCase.expected),
      testCase.name + " must fail closed"
    );
  }
}

console.log(
  "PASS: physical-agent-control v1 intents, canonical profile, replay dispositions, derived states, and adversarial fixtures"
);
