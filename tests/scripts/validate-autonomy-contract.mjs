import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const read = (name) => JSON.parse(fs.readFileSync(path.join(root, name), "utf8"));
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const canonical = (value) => plain(value) ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : JSON.stringify(value);
const digest = (value, omittedField) => { const copy = structuredClone(value); if (omittedField) delete copy[omittedField]; return `sha256:${crypto.createHash("sha256").update(canonical(copy), "utf8").digest("hex")}`; };
const clone = (value) => structuredClone(value);
const fail = (message) => { throw new Error(message); };
const typeMatches = (type, value) => ({ object: plain(value), array: Array.isArray(value), string: typeof value === "string", integer: Number.isInteger(value), boolean: typeof value === "boolean", null: value === null })[type];
const realDateTime = (value) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value) && !Number.isNaN(Date.parse(value));

const schemaKeywords = new Set(["$schema", "$id", "title", "description", "$defs", "$ref", "oneOf", "allOf", "const", "enum", "type", "pattern", "format", "minimum", "maximum", "minItems", "maxItems", "uniqueItems", "items", "required", "properties", "additionalProperties"]);
function schemaChecker(rootSchema) {
  const resolve = (ref) => { if (!ref.startsWith("#/")) fail(`external schema reference is forbidden: ${ref}`); return ref.slice(2).split("/").reduce((value, key) => value?.[key.replaceAll("~1", "/").replaceAll("~0", "~")], rootSchema); };
  function inspect(node, at = "$") { assert.ok(plain(node), `schema node must be an object at ${at}`); for (const key of Object.keys(node)) assert.ok(schemaKeywords.has(key), `unsupported schema keyword ${key} at ${at}`); if (node.$ref) assert.ok(resolve(node.$ref), `unresolved schema reference ${node.$ref}`); for (const [key, child] of Object.entries(node.$defs ?? {})) inspect(child, `${at}.$defs.${key}`); for (const [key, child] of Object.entries(node.properties ?? {})) inspect(child, `${at}.properties.${key}`); if (node.items) inspect(node.items, `${at}.items`); for (const [index, child] of (node.oneOf ?? []).entries()) inspect(child, `${at}.oneOf[${index}]`); for (const [index, child] of (node.allOf ?? []).entries()) inspect(child, `${at}.allOf[${index}]`); }
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
  return { valid: (record, label) => assert.deepEqual(errors(rootSchema, record), [], `${label} violates the closed v1 schema`) };
}

const constitutionSchema = read("docs/autonomy-constitution-v1.schema.json");
const journalSchema = read("docs/autonomous-mutation-journal-v1.schema.json");
const coverageSchema = read("docs/autonomy-coverage-registry-v1.schema.json");
const constitutionShape = schemaChecker(constitutionSchema);
const journalShape = schemaChecker(journalSchema);
const coverageShape = schemaChecker(coverageSchema);
const constitution = read("tests/fixtures/autonomy-contract/constitution.json");
const coverage = read("docs/autonomy-coverage-registry-v1.json");
const fixtureJournals = [read("tests/fixtures/autonomy-contract/journal-happy-commit.json"), read("tests/fixtures/autonomy-contract/journal-r-exact-revert.json"), read("tests/fixtures/autonomy-contract/journal-r-forward-recovery.json")];
const protectedDomains = ["credentials-and-auth", "owner-policy", "constitution-and-safety-gates", "deployments-and-code", "privacy-retention-and-erasure", "firmware", "remote-recovery", "model-weight-training", "irreversible-external-actions", "package-downgrade"];
const classes = {
  "micro-routing": ["L5", "gille-inference", "R-exact", "micro-route-readback-matches-candidate"],
  "macro-routing": ["L5", "hugin", "R-exact", "macro-route-readback-matches-candidate"],
  prompt: ["L5", "hugin", "R-exact", "prompt-config-readback-matches-candidate"],
  harness: ["L5", "hugin", "R-exact", "harness-config-readback-matches-candidate"],
  "tool-policy": ["L5", "hugin", "R-exact", "tool-policy-readback-matches-candidate"],
  "served-model-roster": ["L5", "gille-inference", "R-exact", "served-model-roster-readback-matches-candidate"],
  "no-reboot-security-bugfix-maintenance": ["L4", "brokkr", "R-forward", "maintenance-safe-state-readback"]
};
const classNames = Object.keys(classes);

function constitutionSemantics(record) {
  constitutionShape.valid(record, "constitution fixture");
  assert.equal(record.constitution_digest, digest(record, "constitution_digest"), "constitution digest binds every constitutional field");
  assert.deepEqual([...record.protected_lanes].sort(), [...protectedDomains].sort(), "protected lanes are an exact permanent set");
  assert.ok(Object.values(record.safety_floors).every((value) => value === true), "all safety floors are mandatory true");
  assert.deepEqual(record.autonomous_classes.map((entry) => entry.class).sort(), [...classNames].sort(), "exactly the seven approved classes exist");
  const identities = record.autonomous_classes.flatMap((entry) => Object.values(entry.identities));
  assert.equal(new Set(identities).size, identities.length, "class authority identities are unique");
  for (const entry of record.autonomous_classes) {
    const [level, owner, recovery, readback] = classes[entry.class];
    assert.deepEqual([entry.level, entry.owner, entry.recovery_class], [level, owner, recovery], `${entry.class} has its approved L4/L5 owner and recovery class`);
    const recoveryPostcondition = recovery === "R-exact" ? "baseline-digest-restored" : "safe-state-verified";
    assert.deepEqual([...entry.required_postconditions].sort(), ["verifier-passes", "canary-watch-complete", readback, recoveryPostcondition, "controller-disarm-confirmed"].sort(), `${entry.class} has class-appropriate postconditions`);
    for (const requirement of ["executor-interruption", "observer-cannot-actuate", "recovery-path-proven", "stale-evidence-rejected", "chain-tamper-rejected", "late-mutation-rejected", "kill-switch-rejected"]) assert.ok(entry.fault_injection_requirements.includes(requirement), `${entry.class} proves ${requirement}`);
    if (recovery === "R-forward") assert.ok(entry.fault_injection_requirements.includes("canary-breach-quarantines"), "R-forward proves quarantine");
  }
}

function coverageSemantics(record, c) {
  coverageShape.valid(record, "coverage registry");
  assert.equal(record.registry_digest, digest(record, "registry_digest"), "registry digest binds coverage");
  assert.equal(record.constitution_digest, c.constitution_digest, "coverage is constitution-bound");
  assert.equal(record.global_state, "disarmed", "W0 registry is globally disarmed");
  assert.deepEqual(record.domains.map((entry) => entry.domain).sort(), [...classNames, ...protectedDomains].sort(), "coverage has one exact row for every approved or protected domain");
  for (const entry of record.domains) {
    if (protectedDomains.includes(entry.domain)) assert.deepEqual([entry.level, entry.owner, entry.recovery_class, entry.coverage, entry.target_state], ["permanent", "owner", "none", "protected", "never-mechanical"], `${entry.domain} remains protected`);
    if (classes[entry.domain]) { const [level, owner, recovery] = classes[entry.domain]; assert.deepEqual([entry.level, entry.owner, entry.recovery_class, entry.coverage, entry.target_state], [level, owner, recovery, "shadow", "armed-canary"], `${entry.domain} has accurate W0 coverage`); }
  }
}

const outcomeFor = { prepare: "prepared", apply: "applied", verify: "verified", watch: "watching", commit: "committed", unknown: "unknown", revert: "reverted", recover: "recovered", quarantine: "quarantined", "controller-disarm": "controller-disarmed" };
function journalSemantics(record, c) {
  journalShape.valid(record, `${record.domain} journal`);
  assert.equal(record.constitution_digest, c.constitution_digest, "journal is constitution-bound");
  const policy = c.autonomous_classes.find((entry) => entry.class === record.domain);
  assert.ok(policy, "journal domain is an approved class");
  const b = record.binding;
  assert.equal(record.binding_digest, digest(b), "immutable candidate/config/evidence/policy and authority binding is digest-bound");
  assert.equal(b.risk_scope, record.domain, "risk scope binds class");
  assert.notEqual(b.attempt_id, b.controller_disarm_id, "attempt commit and controller disarm are distinct identities");
  for (const [field, identity] of [["owner_identity", "owner"], ["controller_identity", "controller"], ["watchdog_identity", "watchdog"], ["kill_switch_identity", "kill_switch"], ["recovery_worker_identity", "recovery_worker"]]) assert.equal(b[field], policy.identities[identity], `${field} binds class authority`);
  assert.equal(b.recovery.class, policy.recovery_class, "recovery class matches constitution");
  assert.equal(b.recovery.worker_identity, b.recovery_worker_identity, "recovery worker is immutable");
  assert.ok(Date.parse(b.canary.watch_deadline) <= Date.parse(b.deadline), "watch deadline is within mutation deadline");
  const transitions = policy.recovery_class === "R-exact" ? { prepare: ["apply", "unknown"], apply: ["verify", "unknown"], verify: ["watch", "unknown"], watch: ["commit", "unknown"], commit: ["controller-disarm"], unknown: ["revert"], revert: ["controller-disarm"], "controller-disarm": [] } : { prepare: ["apply", "unknown"], apply: ["verify", "unknown"], verify: ["watch", "unknown"], watch: ["commit", "unknown"], commit: ["controller-disarm"], unknown: ["recover"], recover: ["quarantine"], quarantine: ["controller-disarm"], "controller-disarm": [] };
  let previous = null;
  const ids = new Set();
  for (const [index, entry] of record.entries.entries()) {
    assert.ok(!ids.has(entry.entry_id), "entry identity cannot replay"); ids.add(entry.entry_id);
    assert.equal(entry.sequence, index + 1, "sequence is contiguous");
    assert.equal(entry.binding_digest, record.binding_digest, "every receipt binds immutable identity bundle");
    assert.equal(entry.previous_receipt_digest, previous, "receipt chain is contiguous");
    assert.equal(entry.receipt_digest, digest(entry, "receipt_digest"), "receipt digest binds full content-blind entry");
    assert.equal(entry.outcome, outcomeFor[entry.phase], "phase and outcome pair is exact");
    if (index) { assert.ok(Date.parse(entry.recorded_at) >= Date.parse(record.entries[index - 1].recorded_at), "journal clocks cannot move backwards"); assert.ok(transitions[record.entries[index - 1].phase].includes(entry.phase), `illegal transition ${record.entries[index - 1].phase} -> ${entry.phase}`); }
    if (["apply", "verify", "watch", "commit"].includes(entry.phase)) assert.ok(Date.parse(entry.recorded_at) <= Date.parse(b.deadline), "no mutation may occur after the deadline");
    const recoveryPhase = ["revert", "recover", "quarantine"].includes(entry.phase);
    assert.equal(entry.executor_identity, recoveryPhase ? b.recovery_worker_identity : b.controller_identity, "controller and recovery worker stay separated");
    assert.ok(entry.content_refs.every((ref) => /^ref:[a-z][a-z0-9-]{2,120}$/.test(ref) && !/[/:.]/.test(ref.slice(4))), "journal references remain opaque and content-blind");
    previous = entry.receipt_digest;
  }
  assert.equal(record.entries[0].phase, "prepare", "journal starts prepared");
  assert.equal(record.entries.at(-1).phase, "controller-disarm", "controller performs a separate terminal disarm");
  if (policy.recovery_class === "R-exact" && record.entries.some((entry) => entry.phase === "unknown")) assert.ok(record.entries.some((entry) => entry.phase === "revert" && entry.outcome === "reverted"), "R-exact takes explicit revert/reverted path");
  if (policy.recovery_class === "R-forward") { assert.ok(record.entries.some((entry) => entry.phase === "recover" && entry.outcome === "recovered"), "R-forward takes explicit recover/recovered path"); assert.ok(record.entries.some((entry) => entry.phase === "quarantine" && entry.quarantine.state === "active"), "R-forward recovery quarantines before disarm"); }
}

function resign(record) { record.binding_digest = digest(record.binding); let previous = null; for (const entry of record.entries) { entry.binding_digest = record.binding_digest; entry.previous_receipt_digest = previous; entry.receipt_digest = digest(entry, "receipt_digest"); previous = entry.receipt_digest; } return record; }
function mustReject(mutator, message) { assert.throws(() => journalSemantics(mutator(), constitution), message); }

constitutionSemantics(constitution);
coverageSemantics(coverage, constitution);
// Fixtures are declarative templates: the same canonical procedure used by a writer materializes
// their immutable binding and receipt chain before validation. The adversarial cases below then
// prove that a changed template/receipt cannot be accepted without re-materialization.
const journals = fixtureJournals.map((journal) => { journal.constitution_digest = constitution.constitution_digest; return resign(journal); });
journals.forEach((journal) => journalSemantics(journal, constitution));

mustReject(() => { const x = resign(clone(journals[1])); x.entries[2].phase = "apply"; x.entries[2].outcome = "applied"; return resign(x); }, "unknown cannot retry or re-arm");
mustReject(() => { const x = resign(clone(journals[0])); x.binding.canary.target_count = 2; return resign(x); }, "canary cannot expand");
mustReject(() => { const x = resign(clone(journals[2])); x.entries[3].executor_identity = x.binding.controller_identity; return resign(x); }, "controller cannot impersonate recovery worker");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].content = "forbidden"; return resign(x); }, "content payload is structurally rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].recorded_at = "2026-07-26T01:01:00Z"; return resign(x); }, "late mutation is rejected");
mustReject(() => { const x = clone(journals[0]); x.entries[1].binding_digest = x.binding_digest.replace(/0/, "1"); return x; }, "binding identity drift is rejected");
{ const x = clone(constitution); x.protected_lanes.pop(); x.constitution_digest = digest(x, "constitution_digest"); assert.throws(() => constitutionSemantics(x), "protected-lane substitution is rejected"); }
{ const x = clone(coverage); x.domains[0].coverage = "armed-canary"; x.registry_digest = digest(x, "registry_digest"); assert.throws(() => coverageSemantics(x, constitution), "disarmed W0 cannot claim armed coverage"); }
console.log("autonomy-contract validation passed");
