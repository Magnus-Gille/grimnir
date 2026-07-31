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
const voiceDraftSchema = readDocJson("physical-agent-voice-draft-v1.schema.json");
const voiceCancellationSchema = readDocJson("physical-agent-voice-capture-cancellation-v1.schema.json");
const profile = readJson("active-profile.json");
const intents = readJson("positive-intents.json");
const states = readJson("positive-states.json");
const voiceDrafts = readJson("positive-voice-drafts.json");
const voiceCancellations = readJson("positive-voice-cancellations.json");
const negative = readJson("negative.json");
const context = readJson("validation-context.json");

const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const utcPattern = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
const idPattern = /^[a-z][a-z0-9-]{2,127}$/;
const versionPattern = /^v[1-9][0-9]*$/;

function canonicalize(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonicalize).join(",") + "]";
  return "{" + Object.keys(value).sort().map((key) => JSON.stringify(key) + ":" + canonicalize(value[key])).join(",") + "}";
}

const jsonEqual = (left, right) => canonicalize(left) === canonicalize(right);

function assertExactKeys(record, keys, label) {
  assert.ok(plain(record), label + " must be an object");
  assert.deepEqual(Object.keys(record).sort(), [...keys].sort(), label + " fields must be exact");
}

function voiceContentBinding(content) {
  const payload = {
    draft_id: content.draft_id,
    transcript_version: content.transcript_version,
    utf8_text: content.content_utf8
  };
  return "hmac-sha256:" + crypto
    .createHmac("sha256", Buffer.from(content.hmac_key_hex, "hex"))
    .update(canonicalize(payload), "utf8")
    .digest("hex");
}

function targetSnapshotDigest(snapshot) {
  const payload = structuredClone(snapshot);
  delete payload.snapshot_digest;
  return "sha256:" + crypto.createHash("sha256").update(canonicalize(payload), "utf8").digest("hex");
}

function validateContext(runtimeContext) {
  assert.ok(plain(runtimeContext), "validation context must be an object");

  const captureRefs = new Set();
  for (const [index, source] of runtimeContext.capture_sources.entries()) {
    assertExactKeys(
      source,
      ["capture_source_ref", "coreaudio_uid_ref", "interface_generation_ref", "channel_set", "available"],
      `capture source ${index}`
    );
    for (const field of ["capture_source_ref", "coreaudio_uid_ref", "interface_generation_ref", "channel_set"]) {
      assert.match(source[field], idPattern, `capture source ${field} must be an opaque id`);
    }
    assert.equal(typeof source.available, "boolean", "capture source availability must be boolean");
    assert.ok(!captureRefs.has(source.capture_source_ref), "capture source refs must be unique");
    captureRefs.add(source.capture_source_ref);
  }

  const runtimePins = new Set();
  for (const [index, runtime] of runtimeContext.stt_runtimes.entries()) {
    assertExactKeys(
      runtime,
      ["engine_ref", "engine_version", "model_ref", "model_version", "boundary", "network_access", "available"],
      `STT runtime ${index}`
    );
    assert.match(runtime.engine_ref, idPattern, "STT engine ref must be an opaque id");
    assert.match(runtime.engine_version, versionPattern, "STT engine version must be versioned");
    assert.match(runtime.model_ref, idPattern, "STT model ref must be an opaque id");
    assert.match(runtime.model_version, versionPattern, "STT model version must be versioned");
    assert.equal(runtime.boundary, "workstation-local", "STT runtime must stay workstation-local");
    assert.equal(runtime.network_access, "disabled", "STT runtime networking must be disabled");
    assert.equal(typeof runtime.available, "boolean", "STT runtime availability must be boolean");
    const pin = canonicalize([
      runtime.engine_ref,
      runtime.engine_version,
      runtime.model_ref,
      runtime.model_version
    ]);
    assert.ok(!runtimePins.has(pin), "STT runtime pins must be unique");
    runtimePins.add(pin);
  }

  const snapshotRefs = new Set();
  for (const [index, snapshot] of runtimeContext.native_sessions.entries()) {
    assertExactKeys(
      snapshot,
      [
        "harness",
        "session_ref",
        "ownership",
        "snapshot_ref",
        "snapshot_digest",
        "adapter_instance_ref",
        "native_session_ref",
        "project_ref",
        "worktree_ref",
        "runtime_at_capture"
      ],
      `native target snapshot ${index}`
    );
    for (const field of [
      "session_ref",
      "snapshot_ref",
      "adapter_instance_ref",
      "native_session_ref",
      "project_ref",
      "worktree_ref"
    ]) {
      assert.match(snapshot[field], idPattern, `native target snapshot ${field} must be an opaque id`);
    }
    assert.equal(
      snapshot.snapshot_digest,
      targetSnapshotDigest(snapshot),
      "native target snapshot digest mismatch"
    );
    assert.ok(!snapshotRefs.has(snapshot.snapshot_ref), "native target snapshot refs must be unique");
    snapshotRefs.add(snapshot.snapshot_ref);
  }

  const contentRefs = new Set();
  for (const [index, content] of runtimeContext.volatile_contents.entries()) {
    assertExactKeys(
      content,
      [
        "draft_id",
        "content_ref",
        "content_binding",
        "transcript_version",
        "utf8_bytes",
        "content_utf8",
        "hmac_key_hex",
        "available"
      ],
      `volatile content ${index}`
    );
    assert.match(content.draft_id, idPattern, "volatile content draft id must be an opaque id");
    assert.match(content.content_ref, idPattern, "volatile content ref must be an opaque id");
    assert.match(content.hmac_key_hex, /^[a-f0-9]{64}$/, "synthetic HMAC key must contain 32 bytes");
    assert.equal(
      content.utf8_bytes,
      Buffer.byteLength(content.content_utf8, "utf8"),
      "volatile content UTF-8 byte count mismatch"
    );
    assert.equal(content.content_binding, voiceContentBinding(content), "volatile content HMAC mismatch");
    assert.equal(typeof content.available, "boolean", "volatile content availability must be boolean");
    const ref = canonicalize([content.draft_id, content.content_ref, content.transcript_version]);
    assert.ok(!contentRefs.has(ref), "volatile content references must be unique");
    contentRefs.add(ref);
  }
}

function validateVoicePolicyResolution(record, runtimeContext) {
  if (!record.voice_capture) return;
  const policy = record.voice_capture;
  const captureSource = runtimeContext.capture_sources.find(
    (source) =>
      source.capture_source_ref === policy.capture_source_ref &&
      source.coreaudio_uid_ref === policy.coreaudio_uid_ref &&
      source.interface_generation_ref === policy.interface_generation_ref &&
      source.channel_set === policy.channel_set &&
      source.available === true
  );
  if (!captureSource) throw new Error("voice profile capture source does not resolve");
  const sttRuntime = runtimeContext.stt_runtimes.find(
    (runtime) =>
      runtime.engine_ref === policy.stt_engine_ref &&
      runtime.engine_version === policy.stt_engine_version &&
      runtime.model_ref === policy.stt_model_ref &&
      runtime.model_version === policy.stt_model_version &&
      runtime.boundary === policy.transcription_boundary &&
      runtime.network_access === policy.network_access &&
      runtime.available === true
  );
  if (!sttRuntime) throw new Error("voice profile STT runtime does not resolve");
}

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
  "begin-voice-capture": ["capture", "local-capture", "none", "none"],
  "end-voice-capture": ["capture", "local-capture", "none", "none"],
  "open-voice-draft": ["presentation", "local-only", "none", "none"],
  "discard-voice-draft": ["data-reducing", "local-reducing", "hold", "none"],
  "request-status-turn": ["read-only", "target-read-only", "hold", "none"],
  "request-read-only-review": ["read-only", "target-read-only", "hold", "none"],
  "request-task-template": ["consequential", "hugin-gated", "hold", "none"],
  interrupt: ["authority-reducing", "local-reducing", "hold", "reduce"],
  pause: ["authority-reducing", "local-reducing", "hold", "reduce"]
};

function sourceSelector(source) {
  const { device, transport, control, gesture } = source;
  return { device, transport, control, gesture };
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
    if (policy[2] === "hold" && binding.source.gesture !== "hold") {
      throw new Error("hold-confirmed profile action requires a hold selector");
    }
    if (policy[0] === "authority-reducing" && binding.target.ownership !== "adapter-owned") {
      throw new Error("authority-reducing profile action requires an adapter-owned target");
    }
    if (
      ["begin-voice-capture", "end-voice-capture", "open-voice-draft", "discard-voice-draft"].includes(
        binding.action.name
      ) && binding.target.ownership !== "adapter-owned"
    ) {
      throw new Error("voice capture and draft actions require an adapter-owned target");
    }
    if (binding.action.name === "begin-voice-capture" && binding.source.gesture !== "press") {
      throw new Error("voice capture must begin on Stream Deck key-down");
    }
    if (binding.action.name === "end-voice-capture" && binding.source.gesture !== "release") {
      throw new Error("voice capture must end on Stream Deck key-up");
    }
    if (
      ["begin-voice-capture", "end-voice-capture"].includes(binding.action.name) &&
      !binding.source.control.startsWith("key-")
    ) {
      throw new Error("voice capture requires a dedicated Stream Deck key");
    }
  }

  const beginBindings = record.bindings.filter((binding) => binding.action.name === "begin-voice-capture");
  const endBindings = record.bindings.filter((binding) => binding.action.name === "end-voice-capture");
  const draftBindings = record.bindings.filter((binding) =>
    ["open-voice-draft", "discard-voice-draft"].includes(binding.action.name)
  );
  if (!record.voice_capture && beginBindings.length + endBindings.length + draftBindings.length > 0) {
    throw new Error("voice bindings require a voice capture policy");
  }
  if (record.voice_capture && (beginBindings.length === 0 || beginBindings.length !== endBindings.length)) {
    throw new Error("voice capture requires paired key-down and key-up bindings");
  }
  for (const begin of beginBindings) {
    const pair = endBindings.find(
      (end) => end.source.control === begin.source.control && jsonEqual(end.target, begin.target)
    );
    if (!pair) throw new Error("voice capture binding has no exact key-up pair");
  }
}

function captureTargetKey(record) {
  return canonicalize({
    harness: record.target.harness,
    session_ref: record.target.session_ref,
    ownership: record.target.ownership
  });
}

function validateCaptureTransition(history, candidate, runtimeContext = context) {
  if (!["begin-voice-capture", "end-voice-capture"].includes(candidate.action.name)) return;

  const activeByTarget = new Map();
  const usedCaptureRefs = new Set();
  const cancellationEvents = voiceCancellations
    .filter((record) => Date.parse(record.occurred_at) < Date.parse(candidate.occurred_at))
    .map((record) => ({ kind: "cancellation", record }));
  const timeline = history
    .map((entry) => ({ kind: "intent", record: entry.record }))
    .concat(cancellationEvents)
    .sort((left, right) => Date.parse(left.record.occurred_at) - Date.parse(right.record.occurred_at));

  for (const event of timeline) {
    const prior = event.record;
    if (event.kind === "cancellation") {
      const matching = [...activeByTarget.entries()].find(([, active]) =>
        active.capture_ref === prior.capture_ref &&
        active.adapter_instance_ref === prior.gate.adapter_instance_ref &&
        active.target_snapshot_ref === prior.gate.target_snapshot_ref &&
        active.target_snapshot_digest === prior.gate.target_snapshot_digest &&
        active.stream_id === prior.gate.stream_id &&
        active.control === prior.gate.control
      );
      if (!matching) throw new Error("orphan voice capture cancellation");
      activeByTarget.delete(matching[0]);
      continue;
    }
    if (prior.action.name === "begin-voice-capture") {
      usedCaptureRefs.add(prior.action.capture_ref);
      activeByTarget.set(captureTargetKey(prior), {
        capture_ref: prior.action.capture_ref,
        adapter_instance_ref: prior.action.adapter_instance_ref,
        target_snapshot_ref: prior.action.target_snapshot_ref,
        target_snapshot_digest: prior.action.target_snapshot_digest,
        stream_id: prior.stream_id,
        control: prior.source.control,
        started_at: prior.occurred_at
      });
    } else if (prior.action.name === "end-voice-capture") {
      const active = activeByTarget.get(captureTargetKey(prior));
      if (
        active &&
        active.capture_ref === prior.action.capture_ref &&
        active.adapter_instance_ref === prior.action.adapter_instance_ref &&
        active.target_snapshot_ref === prior.action.target_snapshot_ref &&
        active.target_snapshot_digest === prior.action.target_snapshot_digest &&
        active.stream_id === prior.stream_id &&
        active.control === prior.source.control
      ) {
        activeByTarget.delete(captureTargetKey(prior));
      }
    }
  }

  const targetKey = captureTargetKey(candidate);
  const active = activeByTarget.get(targetKey);
  if (candidate.action.name === "begin-voice-capture") {
    if (active) throw new Error("voice capture is already active for the exact target");
    if (usedCaptureRefs.has(candidate.action.capture_ref)) {
      throw new Error("voice capture reference was already used");
    }
    return;
  }

  if (!active || active.stream_id !== candidate.stream_id) {
    throw new Error("orphan voice capture end");
  }
  if (
    Date.parse(candidate.occurred_at) - Date.parse(active.started_at) >
    profile.voice_capture.max_capture_seconds * 1000
  ) {
    throw new Error("voice capture exceeded the watchdog ceiling");
  }
  if (active.control !== candidate.source.control) {
    throw new Error("voice capture end control mismatch");
  }
  if (active.capture_ref !== candidate.action.capture_ref) {
    throw new Error("voice capture end reference mismatch");
  }
  if (active.adapter_instance_ref !== candidate.action.adapter_instance_ref) {
    throw new Error("voice capture end adapter generation mismatch");
  }
  if (
    active.target_snapshot_ref !== candidate.action.target_snapshot_ref ||
    active.target_snapshot_digest !== candidate.action.target_snapshot_digest
  ) {
    throw new Error("voice capture end target snapshot mismatch");
  }
}

function validateIntent(record, evaluatedAt, history = [], runtimeContext = context) {
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
  if (
    ["begin-voice-capture", "end-voice-capture", "open-voice-draft", "discard-voice-draft"].includes(
      record.action.name
    ) && record.target.ownership !== "adapter-owned"
  ) {
    throw new Error("voice capture and draft actions require an exact adapter-owned target");
  }
  if (record.action.name === "begin-voice-capture" && record.source.gesture !== "press") {
    throw new Error("voice capture must begin on Stream Deck key-down");
  }
  if (record.action.name === "end-voice-capture" && record.source.gesture !== "release") {
    throw new Error("voice capture must end on Stream Deck key-up");
  }
  if (
    ["begin-voice-capture", "end-voice-capture"].includes(record.action.name) &&
    !record.source.control.startsWith("key-")
  ) {
    throw new Error("voice capture requires a dedicated Stream Deck key");
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

  if (["open-voice-draft", "discard-voice-draft"].includes(record.action.name)) {
    const draft = voiceDrafts.find((candidate) => candidate.draft_id === record.action.draft_ref);
    if (!draft) throw new Error("voice draft reference does not resolve");
    if (record.action.content_binding !== draft.content.content_binding) {
      throw new Error("voice draft content binding mismatch");
    }
    const snapshotTarget = {
      harness: draft.target_snapshot.harness,
      session_ref: draft.target_snapshot.session_ref,
      ownership: draft.target_snapshot.ownership
    };
    if (!jsonEqual(snapshotTarget, record.target)) throw new Error("voice draft target mismatch");
    if (evaluated >= Date.parse(draft.expires_at)) throw new Error("voice draft is unavailable or expired");
  }

  const isReplay = history.some(
    (entry) =>
      entry.record.intent_id === record.intent_id ||
      entry.record.idempotency_key === record.idempotency_key
  );
  if (!isReplay) validateCaptureTransition(history, record, runtimeContext);
  if (["begin-voice-capture", "end-voice-capture"].includes(record.action.name)) {
    const nativeSession = runtimeContext.native_sessions.find(
      (session) =>
        session.harness === record.target.harness &&
        session.session_ref === record.target.session_ref &&
        session.ownership === record.target.ownership &&
        session.adapter_instance_ref === record.action.adapter_instance_ref &&
        session.snapshot_ref === record.action.target_snapshot_ref &&
        session.snapshot_digest === record.action.target_snapshot_digest
    );
    if (!nativeSession) throw new Error("voice capture target snapshot does not resolve");
  }
}

function validateVoiceDraft(record, evaluatedAt, runtimeContext = context) {
  if (!dateTime(evaluatedAt)) throw new Error("trusted voice-draft evaluation time is required");
  const evaluated = Date.parse(evaluatedAt);
  const created = Date.parse(record.created_at);
  const updated = Date.parse(record.updated_at);
  const expires = Date.parse(record.expires_at);
  const keyDown = Date.parse(record.gate.key_down_at);
  const keyUp = Date.parse(record.gate.key_up_at);
  const started = Date.parse(record.capture.started_at);
  const ended = Date.parse(record.capture.ended_at);

  if (keyDown !== started || keyUp !== ended) throw new Error("voice draft PTT/capture timestamps mismatch");
  if (keyUp <= keyDown) throw new Error("voice draft key-up must follow key-down");
  if (record.capture.duration_ms !== keyUp - keyDown) throw new Error("voice draft duration mismatch");
  if (record.capture.duration_ms > profile.voice_capture.max_capture_seconds * 1000) {
    throw new Error("voice draft exceeds the profile capture ceiling");
  }
  if (created < ended) throw new Error("voice draft cannot be created before capture ends");
  if (updated < created || updated > evaluated) throw new Error("voice draft update time is invalid");
  if (
    expires <= created ||
    expires - ended > profile.voice_capture.transcript_retention_seconds * 1000
  ) {
    throw new Error("voice draft retention exceeds the profile ceiling");
  }
  if (evaluated >= expires) throw new Error("voice draft is expired at evaluation");

  if (
    record.gate.profile_id !== profile.profile_id ||
    record.gate.profile_version !== profile.profile_version ||
    record.gate.profile_digest !== profile.profile_digest
  ) {
    throw new Error("inactive voice capture profile");
  }
  const beginBinding = profile.bindings.find(
    (binding) => binding.binding_id === record.gate.begin_binding_id
  );
  const endBinding = profile.bindings.find(
    (binding) => binding.binding_id === record.gate.end_binding_id
  );
  const snapshotTarget = {
    harness: record.target_snapshot.harness,
    session_ref: record.target_snapshot.session_ref,
    ownership: record.target_snapshot.ownership
  };
  if (
    !beginBinding ||
    !endBinding ||
    beginBinding.action.name !== "begin-voice-capture" ||
    endBinding.action.name !== "end-voice-capture" ||
    beginBinding.source.control !== record.gate.control ||
    endBinding.source.control !== record.gate.control ||
    beginBinding.source.gesture !== "press" ||
    endBinding.source.gesture !== "release" ||
    !jsonEqual(beginBinding.target, snapshotTarget) ||
    !jsonEqual(endBinding.target, snapshotTarget)
  ) {
    throw new Error("voice draft PTT binding mismatch");
  }
  const beginIntent = intents.find(
    (intent) =>
      intent.intent_id === record.gate.begin_intent_id &&
      intent.binding.binding_id === beginBinding.binding_id &&
      intent.stream_id === record.gate.stream_id &&
      intent.occurred_at === record.gate.key_down_at
  );
  const endIntent = intents.find(
    (intent) =>
      intent.intent_id === record.gate.end_intent_id &&
      intent.binding.binding_id === endBinding.binding_id &&
      intent.stream_id === record.gate.stream_id &&
      intent.occurred_at === record.gate.key_up_at
  );
  if (!beginIntent || !endIntent) throw new Error("voice draft PTT intent pair does not resolve");
  if (
    beginIntent.action.capture_ref !== record.capture_id ||
    endIntent.action.capture_ref !== record.capture_id
  ) {
    throw new Error("voice draft capture reference does not match its PTT intent pair");
  }
  if (
    beginIntent.action.adapter_instance_ref !== record.target_snapshot.adapter_instance_ref ||
    endIntent.action.adapter_instance_ref !== record.target_snapshot.adapter_instance_ref
  ) {
    throw new Error("voice draft adapter generation does not match its PTT intent pair");
  }
  if (
    beginIntent.action.target_snapshot_ref !== record.target_snapshot.snapshot_ref ||
    endIntent.action.target_snapshot_ref !== record.target_snapshot.snapshot_ref ||
    beginIntent.action.target_snapshot_digest !== record.target_snapshot.snapshot_digest ||
    endIntent.action.target_snapshot_digest !== record.target_snapshot.snapshot_digest
  ) {
    throw new Error("voice draft target snapshot does not match its PTT intent pair");
  }
  if (record.target_snapshot.snapshot_digest !== targetSnapshotDigest(record.target_snapshot)) {
    throw new Error("voice draft target snapshot digest mismatch");
  }

  const expectedSource = {
    device_claim: profile.voice_capture.device_claim,
    transport: profile.voice_capture.transport,
    identity_assurance: profile.voice_capture.identity_assurance,
    capture_source_ref: profile.voice_capture.capture_source_ref,
    coreaudio_uid_ref: profile.voice_capture.coreaudio_uid_ref,
    interface_generation_ref: profile.voice_capture.interface_generation_ref,
    channel_set: profile.voice_capture.channel_set
  };
  if (!jsonEqual(record.source, expectedSource)) throw new Error("voice draft capture source mismatch");
  const captureSource = runtimeContext.capture_sources.find(
    (source) =>
      source.capture_source_ref === record.source.capture_source_ref &&
      source.coreaudio_uid_ref === record.source.coreaudio_uid_ref &&
      source.interface_generation_ref === record.source.interface_generation_ref &&
      source.channel_set === record.source.channel_set &&
      source.available === true
  );
  if (!captureSource) throw new Error("voice draft capture source does not resolve");
  const nativeSession = runtimeContext.native_sessions.find((session) => jsonEqual(session, record.target_snapshot));
  if (!nativeSession) throw new Error("voice draft target snapshot does not resolve");

  if (
    record.transcription.engine_ref !== profile.voice_capture.stt_engine_ref ||
    record.transcription.engine_version !== profile.voice_capture.stt_engine_version ||
    record.transcription.model_ref !== profile.voice_capture.stt_model_ref ||
    record.transcription.model_version !== profile.voice_capture.stt_model_version
  ) {
    throw new Error("voice draft STT pin mismatch");
  }
  if (
    record.transcription.boundary !== profile.voice_capture.transcription_boundary ||
    record.transcription.network_access !== profile.voice_capture.network_access ||
    record.transcription.cloud_transcription !== false ||
    record.content.audio_retained !== false ||
    record.content.storage !== "volatile-local"
  ) {
    throw new Error("voice draft privacy policy mismatch");
  }
  const sttRuntime = runtimeContext.stt_runtimes.find(
    (runtime) =>
      runtime.engine_ref === record.transcription.engine_ref &&
      runtime.engine_version === record.transcription.engine_version &&
      runtime.model_ref === record.transcription.model_ref &&
      runtime.model_version === record.transcription.model_version &&
      runtime.boundary === record.transcription.boundary &&
      runtime.network_access === record.transcription.network_access &&
      runtime.available === true
  );
  if (!sttRuntime) throw new Error("voice draft STT runtime does not resolve");
  const content = runtimeContext.volatile_contents.find(
    (candidate) =>
      candidate.draft_id === record.draft_id &&
      candidate.content_ref === record.content.content_ref &&
      candidate.content_binding === record.content.content_binding &&
      candidate.transcript_version === record.content.transcript_version &&
      candidate.utf8_bytes === record.content.utf8_bytes &&
      candidate.available === true
  );
  if (!content) throw new Error("voice draft volatile content does not resolve");

  if (record.review.state === "pending") {
    if (record.review.reviewed_at !== null || record.review.reviewed_binding !== null) {
      throw new Error("pending voice draft cannot claim review evidence");
    }
    if (record.disposition !== "draft") throw new Error("pending voice draft must remain a draft");
  } else {
    if (
      record.review.reviewed_at === null ||
      record.review.reviewed_binding !== record.content.content_binding
    ) {
      throw new Error("voice draft review must bind the current transcript version");
    }
    const reviewed = Date.parse(record.review.reviewed_at);
    if (reviewed < created || reviewed > updated) throw new Error("voice draft review time is invalid");
  }
  if (record.disposition === "opened" && record.review.state !== "accepted") {
    throw new Error("opened voice draft requires accepted review");
  }
}

function validateVoiceDraftCollection(records, runtimeContext = context) {
  for (const record of records) {
    const errors = schemaErrors(voiceDraftSchema, voiceDraftSchema, record);
    if (errors.length) throw new Error("voice draft schema: " + errors.join("; "));
    validateVoiceDraft(record, runtimeContext.voice_draft_evaluated_at[record.draft_id], runtimeContext);
  }
  const draftIds = new Set();
  const captureIds = new Set();
  for (const record of records) {
    if (draftIds.has(record.draft_id)) throw new Error("duplicate voice draft id");
    if (captureIds.has(record.capture_id)) throw new Error("duplicate voice capture id");
    draftIds.add(record.draft_id);
    captureIds.add(record.capture_id);
    if (voiceCancellations.some((cancellation) => cancellation.capture_ref === record.capture_id)) {
      throw new Error("cancelled voice capture cannot create a draft");
    }
  }
}

function validateVoiceCancellation(record, evaluatedAt, runtimeContext = context) {
  if (!dateTime(evaluatedAt)) throw new Error("trusted cancellation evaluation time is required");
  const occurred = Date.parse(record.occurred_at);
  const evaluated = Date.parse(evaluatedAt);
  if (occurred > evaluated) throw new Error("voice cancellation cannot occur after evaluation");
  if (
    record.gate.profile_id !== profile.profile_id ||
    record.gate.profile_version !== profile.profile_version ||
    record.gate.profile_digest !== profile.profile_digest
  ) {
    throw new Error("inactive voice cancellation profile");
  }
  const beginIntent = intents.find((intent) => intent.intent_id === record.gate.begin_intent_id);
  if (
    !beginIntent ||
    beginIntent.action.name !== "begin-voice-capture" ||
    beginIntent.binding.binding_id !== record.gate.begin_binding_id ||
    beginIntent.action.capture_ref !== record.capture_ref ||
    beginIntent.stream_id !== record.gate.stream_id ||
    beginIntent.source.control !== record.gate.control ||
    beginIntent.action.adapter_instance_ref !== record.gate.adapter_instance_ref ||
    beginIntent.action.target_snapshot_ref !== record.gate.target_snapshot_ref ||
    beginIntent.action.target_snapshot_digest !== record.gate.target_snapshot_digest
  ) {
    throw new Error("voice cancellation begin intent does not resolve exactly");
  }
  const alreadyEnded = intents.some(
    (intent) =>
      intent.action.name === "end-voice-capture" &&
      intent.action.capture_ref === record.capture_ref &&
      Date.parse(intent.occurred_at) <= occurred
  );
  if (alreadyEnded) throw new Error("completed voice capture cannot be cancelled");
  const elapsed = occurred - Date.parse(beginIntent.occurred_at);
  const ceiling = profile.voice_capture.max_capture_seconds * 1000;
  if (record.reason === "watchdog" ? elapsed !== ceiling : elapsed <= 0 || elapsed > ceiling) {
    throw new Error("voice cancellation timing mismatch");
  }
  const snapshot = runtimeContext.native_sessions.find(
    (candidate) =>
      candidate.harness === beginIntent.target.harness &&
      candidate.session_ref === beginIntent.target.session_ref &&
      candidate.ownership === beginIntent.target.ownership &&
      candidate.adapter_instance_ref === record.gate.adapter_instance_ref &&
      candidate.snapshot_ref === record.gate.target_snapshot_ref &&
      candidate.snapshot_digest === record.gate.target_snapshot_digest
  );
  if (!snapshot) throw new Error("voice cancellation target snapshot does not resolve");
}

function validateVoiceCancellationCollection(records, runtimeContext = context) {
  const cancellationIds = new Set();
  const captureRefs = new Set();
  for (const record of records) {
    const errors = schemaErrors(voiceCancellationSchema, voiceCancellationSchema, record);
    if (errors.length) throw new Error("voice cancellation schema: " + errors.join("; "));
    validateVoiceCancellation(
      record,
      runtimeContext.cancellation_evaluated_at[record.cancellation_id],
      runtimeContext
    );
    if (cancellationIds.has(record.cancellation_id)) throw new Error("duplicate voice cancellation id");
    if (captureRefs.has(record.capture_ref)) throw new Error("duplicate voice cancellation capture ref");
    cancellationIds.add(record.cancellation_id);
    captureRefs.add(record.capture_ref);
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

function validateRecord(record, evaluatedAt, history = [], runtimeContext = context) {
  const errors = schemaErrors(schema, schema, record);
  if (errors.length) throw new Error("schema: " + errors.join("; "));
  if (record.kind === "physical-control-intent") validateIntent(record, evaluatedAt, history, runtimeContext);
  else if (record.kind === "physical-control-state") validateState(record, evaluatedAt);
  else throw new Error("unknown record kind");
}

function validateFixtureRecord(record, evaluatedAt, history = [], runtimeContext = context) {
  if (record.kind === "physical-agent-voice-capture-cancellation") {
    const errors = schemaErrors(voiceCancellationSchema, voiceCancellationSchema, record);
    if (errors.length) throw new Error("voice cancellation schema: " + errors.join("; "));
    validateVoiceCancellation(record, evaluatedAt, runtimeContext);
    return;
  }
  if (record.kind === "physical-agent-voice-draft") {
    const errors = schemaErrors(voiceDraftSchema, voiceDraftSchema, record);
    if (errors.length) throw new Error("voice draft schema: " + errors.join("; "));
    validateVoiceDraft(record, evaluatedAt, runtimeContext);
    return;
  }
  validateRecord(record, evaluatedAt, history, runtimeContext);
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
checkSchema(voiceDraftSchema);
checkSchema(voiceCancellationSchema);
validateContext(context);
validateProfile(profile);
validateVoicePolicyResolution(profile, context);
validateVoiceCancellationCollection(voiceCancellations, context);
const streamDeckOnlyProfile = structuredClone(profile);
delete streamDeckOnlyProfile.voice_capture;
streamDeckOnlyProfile.bindings = streamDeckOnlyProfile.bindings.filter(
  (binding) => !["begin-voice-capture", "end-voice-capture", "open-voice-draft", "discard-voice-draft"].includes(
    binding.action.name
  )
);
streamDeckOnlyProfile.profile_digest = profileDigest(streamDeckOnlyProfile);
validateProfile(streamDeckOnlyProfile);

const acceptedHistory = [];
for (const record of intents) {
  validateRecord(record, context.intent_evaluated_at[record.intent_id], acceptedHistory, context);
  assert.equal(
    classifyActivation(acceptedHistory, record).status,
    "accepted",
    record.intent_id + " must activate once"
  );
  acceptedHistory.push({ record, disposition: "accepted" });
}
for (const record of states) validateRecord(record, context.state_evaluated_at);
validateVoiceDraftCollection(voiceDrafts, context);

const bases = new Map(
  [...intents, ...states, ...voiceDrafts, ...voiceCancellations].map((record) => [
    record.kind === "physical-control-intent"
      ? record.intent_id
      : record.kind === "physical-control-state"
        ? record.state_id
        : record.kind === "physical-agent-voice-draft"
          ? record.draft_id
          : record.cancellation_id,
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

  if (testCase.scope === "context") {
    const candidateContext = structuredClone(context);
    for (const mutation of testCase.mutations) {
      let target = candidateContext;
      for (const segment of mutation.path.slice(0, -1)) target = target[segment];
      target[mutation.path.at(-1)] = mutation.value;
    }
    assert.throws(
      () => {
        validateContext(candidateContext);
        validateVoicePolicyResolution(profile, candidateContext);
        validateVoiceCancellationCollection(voiceCancellations, candidateContext);
        validateVoiceDraftCollection(voiceDrafts, candidateContext);
      },
      new RegExp(testCase.expected),
      testCase.name + " must fail closed"
    );
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
      : candidate.kind === "physical-control-state"
        ? context.state_evaluated_at
        : candidate.kind === "physical-agent-voice-draft"
          ? context.voice_draft_evaluated_at[testCase.base]
          : context.cancellation_evaluated_at[testCase.base]
  );
  const priorHistory = candidate.kind === "physical-control-intent"
    ? acceptedHistory.filter(
        (entry) =>
          entry.record.stream_id === candidate.stream_id &&
          entry.record.sequence < candidate.sequence
      )
    : [];

  if (testCase.scope === "voice-collection") {
    const candidateCollection = voiceDrafts.map((record) =>
      record.draft_id === testCase.base ? candidate : structuredClone(record)
    );
    assert.throws(
      () => validateVoiceDraftCollection(candidateCollection, context),
      new RegExp(testCase.expected),
      testCase.name + " must fail closed"
    );
    continue;
  }

  if (testCase.scope === "cancellation-collection") {
    const candidateCollection = voiceCancellations.map((record) =>
      record.cancellation_id === testCase.base ? candidate : structuredClone(record)
    );
    assert.throws(
      () => validateVoiceCancellationCollection(candidateCollection, context),
      new RegExp(testCase.expected),
      testCase.name + " must fail closed"
    );
    continue;
  }

  if (testCase.scope === "collection") {
    validateFixtureRecord(candidate, evaluatedAt, priorHistory);
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
      () => validateFixtureRecord(candidate, evaluatedAt, priorHistory),
      new RegExp(testCase.expected),
      testCase.name + " must fail closed"
    );
  }
}

console.log(
  "PASS: Stream Deck control intents, EP-2350 voice draft/cancellation metadata, canonical profile, replay dispositions, derived states, and adversarial fixtures"
);
