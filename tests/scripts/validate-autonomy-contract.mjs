import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const read = (name) => JSON.parse(fs.readFileSync(path.join(root, name), "utf8"));
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const canonical = (value) => plain(value) ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : JSON.stringify(value);
const digest = (value, omittedField) => { const copy = structuredClone(value); delete copy[omittedField]; return `sha256:${crypto.createHash("sha256").update(canonical(copy), "utf8").digest("hex")}`; };
const clone = (value) => structuredClone(value);
const fail = (message) => { throw new Error(message); };
const typeMatches = (type, value) => ({ object: plain(value), array: Array.isArray(value), string: typeof value === "string", integer: Number.isInteger(value), boolean: typeof value === "boolean", null: value === null })[type];
const realDateTime = (value) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value) && !Number.isNaN(Date.parse(value));

// This intentionally validates the normative JSON-Schema subset instead of merely asserting a
// few handwritten fields. New schema keywords require adding both schema-checker support and tests.
const schemaKeywords = new Set(["$schema", "$id", "title", "description", "$defs", "$ref", "oneOf", "allOf", "const", "enum", "type", "pattern", "format", "minimum", "maximum", "minItems", "maxItems", "uniqueItems", "items", "required", "properties", "additionalProperties"]);
function schemaChecker(rootSchema) {
  const resolve = (ref) => {
    if (!ref.startsWith("#/")) fail(`external schema reference is forbidden: ${ref}`);
    return ref.slice(2).split("/").reduce((value, key) => value?.[key.replaceAll("~1", "/").replaceAll("~0", "~")], rootSchema);
  };
  function inspect(node, at = "$") {
    assert.ok(plain(node), `schema node must be an object at ${at}`);
    for (const key of Object.keys(node)) assert.ok(schemaKeywords.has(key), `unsupported schema keyword ${key} at ${at}`);
    if (node.$ref) assert.ok(resolve(node.$ref), `unresolved schema reference ${node.$ref}`);
    for (const [key, child] of Object.entries(node.$defs ?? {})) inspect(child, `${at}.$defs.${key}`);
    for (const [key, child] of Object.entries(node.properties ?? {})) inspect(child, `${at}.properties.${key}`);
    if (node.items) inspect(node.items, `${at}.items`);
    for (const [index, child] of (node.oneOf ?? []).entries()) inspect(child, `${at}.oneOf[${index}]`);
    for (const [index, child] of (node.allOf ?? []).entries()) inspect(child, `${at}.allOf[${index}]`);
  }
  function errors(node, value, at = "$") {
    if (node.$ref) return errors(resolve(node.$ref), value, at);
    if (node.oneOf) { const candidates = node.oneOf.map((child) => errors(child, value, at)); return candidates.filter((result) => result.length === 0).length === 1 ? [] : [`${at}: expected exactly one schema branch`]; }
    if (node.allOf) return node.allOf.flatMap((child) => errors(child, value, at));
    const result = [];
    if (Object.hasOwn(node, "const") && canonical(value) !== canonical(node.const)) result.push(`${at}: const mismatch`);
    if (node.enum && !node.enum.some((candidate) => canonical(value) === canonical(candidate))) result.push(`${at}: enum mismatch`);
    if (node.type && !typeMatches(node.type, value)) return [...result, `${at}: expected ${node.type}`];
    if (typeof value === "string") { if (node.pattern && !new RegExp(node.pattern).test(value)) result.push(`${at}: pattern`); if (node.format === "date-time" && !realDateTime(value)) result.push(`${at}: date-time`); }
    if (typeof value === "number") { if (node.minimum !== undefined && value < node.minimum) result.push(`${at}: minimum`); if (node.maximum !== undefined && value > node.maximum) result.push(`${at}: maximum`); }
    if (Array.isArray(value)) { if (node.minItems !== undefined && value.length < node.minItems) result.push(`${at}: minItems`); if (node.maxItems !== undefined && value.length > node.maxItems) result.push(`${at}: maxItems`); if (node.uniqueItems && new Set(value.map(canonical)).size !== value.length) result.push(`${at}: duplicate items`); if (node.items) value.forEach((item, index) => result.push(...errors(node.items, item, `${at}[${index}]`))); }
    if (plain(value)) { for (const field of node.required ?? []) if (!Object.hasOwn(value, field)) result.push(`${at}.${field}: required`); if (node.additionalProperties === false) for (const field of Object.keys(value)) if (!Object.hasOwn(node.properties ?? {}, field)) result.push(`${at}.${field}: additional property`); for (const [field, child] of Object.entries(node.properties ?? {})) if (Object.hasOwn(value, field)) result.push(...errors(child, value[field], `${at}.${field}`)); }
    return result;
  }
  inspect(rootSchema);
  return { valid: (record, label) => assert.deepEqual(errors(rootSchema, record), [], `${label} violates the closed v1 schema`), invalid: (record, label) => assert.notDeepEqual(errors(rootSchema, record), [], `${label} must be rejected by the closed v1 schema`) };
}

const constitutionSchema = read("docs/autonomy-constitution-v1.schema.json");
const journalSchema = read("docs/autonomous-mutation-journal-v1.schema.json");
const coverageSchema = read("docs/autonomy-coverage-registry-v1.schema.json");
const constitutionShape = schemaChecker(constitutionSchema);
const journalShape = schemaChecker(journalSchema);
const coverageShape = schemaChecker(coverageSchema);
const constitution = read("tests/fixtures/autonomy-contract/constitution.json");
const coverage = read("docs/autonomy-coverage-registry-v1.json");
const journals = [read("tests/fixtures/autonomy-contract/journal-r-exact.json"), read("tests/fixtures/autonomy-contract/journal-r-forward.json")];
const protectedDomains = ["credentials-and-auth", "owner-policy", "constitution-and-safety-gates", "deployments-and-code", "privacy-retention-and-erasure", "firmware", "remote-recovery", "model-weight-training", "irreversible-external-actions", "package-downgrade"];
const classNames = ["routing", "no-reboot-security-bugfix-maintenance"];

function constitutionSemantics(record) {
  constitutionShape.valid(record, "constitution fixture");
  assert.equal(record.constitution_digest, digest(record, "constitution_digest"), "constitution digest binds every constitutional field");
  assert.deepEqual([...record.protected_lanes].sort(), [...protectedDomains].sort(), "protected lanes are an exact permanent set");
  assert.ok(Object.values(record.safety_floors).every((value) => value === true), "all safety floors are mandatory true");
  assert.deepEqual(record.autonomous_classes.map((entry) => entry.class).sort(), [...classNames].sort(), "only the two closed L4/L5 classes exist");
  const identities = record.autonomous_classes.flatMap((entry) => [entry.identities.executor, entry.identities.recovery_worker]);
  assert.equal(new Set(identities).size, identities.length, "executor and recovery identities are unique");
  for (const entry of record.autonomous_classes) {
    assert.ok(entry.required_postconditions.includes("disarm-confirmed"), `${entry.class} requires disarm confirmation`);
    assert.ok(entry.fault_injection_requirements.includes("observer-cannot-actuate"), `${entry.class} proves observer separation`);
    assert.ok(entry.fault_injection_requirements.includes("recovery-path-proven"), `${entry.class} proves recovery`);
  }
}

function coverageSemantics(record, c) {
  coverageShape.valid(record, "coverage registry");
  assert.equal(record.registry_digest, digest(record, "registry_digest"), "registry digest binds coverage");
  assert.equal(record.constitution_digest, c.constitution_digest, "coverage is constitution-bound");
  assert.equal(record.global_state, "disarmed", "W0 registry is globally disarmed");
  assert.deepEqual(record.domains.map((entry) => entry.domain).sort(), [...classNames, ...protectedDomains].sort(), "coverage registry has one exact row for every autonomous/protected domain");
  assert.equal(new Set(record.domains.map((entry) => entry.domain)).size, record.domains.length, "coverage domains are unique by domain identifier");
  for (const entry of record.domains) {
    if (protectedDomains.includes(entry.domain)) assert.deepEqual([entry.level, entry.owner, entry.recovery_class, entry.coverage, entry.target_state], ["permanent", "owner", "none", "protected", "never-mechanical"], `${entry.domain} remains protected`);
    if (entry.domain === "routing") assert.deepEqual([entry.level, entry.owner, entry.recovery_class, entry.coverage, entry.target_state], ["L5", "gille-inference", "R-exact", "shadow", "armed-canary"]);
    if (entry.domain === "no-reboot-security-bugfix-maintenance") assert.deepEqual([entry.level, entry.owner, entry.recovery_class, entry.coverage, entry.target_state], ["L4", "brokkr", "R-forward", "shadow", "armed-canary"]);
  }
}

const allowedTransitions = { prepare: ["apply", "unknown"], apply: ["verify", "unknown"], verify: ["watch", "unknown"], watch: ["commit", "unknown"], commit: ["disarm"], unknown: ["recover"], recover: ["quarantine", "disarm"], quarantine: ["disarm"], disarm: [] };
function journalSemantics(record, c) {
  journalShape.valid(record, `${record.domain} journal`);
  assert.equal(record.constitution_digest, c.constitution_digest, "journal is constitution-bound");
  const policy = c.autonomous_classes.find((entry) => entry.class === record.domain);
  assert.ok(policy, `journal domain is a constitution class: ${record.domain}`);
  const entries = record.entries;
  assert.equal(entries[0].phase, "prepare", "journal starts prepared");
  assert.equal(entries[0].outcome, "prepared", "journal starts with prepared outcome");
  const first = entries[0];
  const ids = new Set();
  let previousDigest = null;
  for (const [index, entry] of entries.entries()) {
    assert.ok(!ids.has(entry.entry_id), "entry identity cannot replay"); ids.add(entry.entry_id);
    assert.equal(entry.sequence, index + 1, "sequence is contiguous");
    assert.equal(entry.mutation_id, first.mutation_id, "one envelope has one mutation");
    assert.equal(entry.attempt_id, first.attempt_id, "attempt identity cannot change");
    assert.equal(entry.idempotency_key, first.idempotency_key, "idempotency identity cannot change");
    assert.equal(entry.risk_scope, record.domain, "risk scope binds domain");
    for (const field of ["baseline_digest", "postconditions_digest", "deadline"]) assert.equal(entry[field], first[field], `${field} cannot change in a journal`);
    assert.deepEqual(entry.canary, first.canary, "canary scope and watch deadline cannot expand");
    assert.equal(entry.recovery.class, policy.recovery_class, "recovery class matches constitution");
    assert.equal(entry.recovery.worker_identity, policy.identities.recovery_worker, "recovery worker matches constitution");
    assert.equal(entry.recovery.disarms_after_action, true, "recovery action always disarms");
    assert.equal(entry.previous_receipt_digest, previousDigest, "receipt chain is contiguous");
    assert.equal(entry.receipt_digest, digest(entry, "receipt_digest"), "receipt digest binds the full content-blind entry");
    assert.ok(Date.parse(entry.recorded_at) <= Date.parse(entry.deadline), "entry cannot be recorded after its deadline");
    assert.ok(Date.parse(entry.canary.watch_deadline) <= Date.parse(entry.deadline), "watch deadline is inside execution deadline");
    if (index) { assert.ok(Date.parse(entry.recorded_at) >= Date.parse(entries[index - 1].recorded_at), "journal clocks cannot move backwards"); assert.ok(allowedTransitions[entries[index - 1].phase].includes(entry.phase), `illegal transition ${entries[index - 1].phase} -> ${entry.phase}`); }
    const recoveryPhase = ["recover", "quarantine", "disarm"].includes(entry.phase);
    assert.equal(entry.executor_identity, recoveryPhase ? policy.identities.recovery_worker : policy.identities.executor, "executor identity follows phase separation");
    assert.ok(entry.content_refs.every((ref) => /^ref:[a-z][a-z0-9-]{2,120}$/.test(ref) && !/[/:.]/.test(ref.slice(4))), "journal references remain opaque and content-blind");
    previousDigest = entry.receipt_digest;
  }
  assert.ok(["disarmed", "terminally-blocked"].includes(entries.at(-1).outcome), "every terminal state fails closed");
  assert.equal(entries.at(-1).phase, "disarm", "terminal terminal state is disarm");
  assert.ok(entries.some((entry) => entry.outcome === "unknown"), "fixtures prove unknown-state recovery");
  assert.ok(entries.some((entry) => entry.phase === "recover" && entry.outcome === "recovered"), "fixtures prove recovery");
  if (policy.recovery_class === "R-forward") { assert.ok(entries.some((entry) => entry.phase === "quarantine" && entry.outcome === "quarantined" && entry.quarantine.state === "active"), "R-forward breach is quarantined before disarm"); }
}

function resignJournal(record) { let previous = null; for (const entry of record.entries) { entry.previous_receipt_digest = previous; entry.receipt_digest = digest(entry, "receipt_digest"); previous = entry.receipt_digest; } return record; }
function mustReject(mutator, message) { const candidate = mutator(); assert.throws(() => journalSemantics(candidate, constitution), message); }

constitutionSemantics(constitution);
coverageSemantics(coverage, constitution);
journals.forEach((journal) => journalSemantics(journal, constitution));

// Adversarial semantic transitions: all begin as schema-valid, re-signed envelopes.
mustReject(() => { const x = resignJournal(clone(journals[0])); x.entries[2].phase = "apply"; x.entries[2].outcome = "applied"; return resignJournal(x); }, "unknown must not retry/re-arm");
mustReject(() => { const x = resignJournal(clone(journals[1])); x.entries[1].canary.target_count = 2; return resignJournal(x); }, "canary cannot expand");
mustReject(() => { const x = resignJournal(clone(journals[1])); x.entries[2].executor_identity = "maintenance-executor"; return resignJournal(x); }, "executor cannot impersonate recovery worker");
mustReject(() => { const x = resignJournal(clone(journals[0])); x.entries[1].content_refs = ["ref:payload-secret"]; x.entries[1].content = "forbidden"; return resignJournal(x); }, "content payload is structurally rejected");
{
  const x = clone(constitution); x.protected_lanes.pop(); x.constitution_digest = digest(x, "constitution_digest"); assert.throws(() => constitutionSemantics(x), "protected-lane substitution is rejected");
}
{
  const x = clone(coverage); x.domains[0].coverage = "armed-canary"; x.registry_digest = digest(x, "registry_digest"); assert.throws(() => coverageSemantics(x, constitution), "disarmed W0 cannot claim armed coverage");
}
console.log("autonomy-contract validation passed");
