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
const realDateTime = (value) => {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value) || Number.isNaN(Date.parse(value))) return false;
  return new Date(value).toISOString().replace(".000Z", "Z") === value;
};

const schemaKeywords = new Set(["$schema", "$id", "title", "description", "$defs", "$ref", "oneOf", "allOf", "const", "enum", "type", "pattern", "format", "minimum", "maximum", "minItems", "maxItems", "uniqueItems", "items", "required", "properties", "additionalProperties"]);
function schemaChecker(rootSchema) {
  const resolve = (ref) => { if (!ref.startsWith("#/")) fail(`external schema reference is forbidden: ${ref}`); return ref.slice(2).split("/").reduce((value, key) => value?.[key.replaceAll("~1", "/").replaceAll("~0", "~")], rootSchema); };
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
    if (node.oneOf) {
      const candidates = node.oneOf.map((child) => errors(child, value, at));
      return candidates.filter((result) => result.length === 0).length === 1 ? [] : [`${at}: expected exactly one schema branch`];
    }
    if (node.allOf) return node.allOf.flatMap((child) => errors(child, value, at));
    const result = [];
    if (Object.hasOwn(node, "const") && canonical(value) !== canonical(node.const)) result.push(`${at}: const mismatch`);
    if (node.enum && !node.enum.some((candidate) => canonical(value) === canonical(candidate))) result.push(`${at}: enum mismatch`);
    if (node.type && !typeMatches(node.type, value)) return [...result, `${at}: expected ${node.type}`];
    if (typeof value === "string") {
      if (node.pattern && !new RegExp(node.pattern).test(value)) result.push(`${at}: pattern`);
      if (node.format === "date-time" && !realDateTime(value)) result.push(`${at}: date-time`);
    }
    if (typeof value === "number") {
      if (node.minimum !== undefined && value < node.minimum) result.push(`${at}: minimum`);
      if (node.maximum !== undefined && value > node.maximum) result.push(`${at}: maximum`);
    }
    if (Array.isArray(value)) {
      if (node.minItems !== undefined && value.length < node.minItems) result.push(`${at}: minItems`);
      if (node.maxItems !== undefined && value.length > node.maxItems) result.push(`${at}: maxItems`);
      if (node.uniqueItems && new Set(value.map(canonical)).size !== value.length) result.push(`${at}: duplicate items`);
      if (node.items) value.forEach((item, index) => result.push(...errors(node.items, item, `${at}[${index}]`)));
    }
    if (plain(value)) {
      for (const field of node.required ?? []) if (!Object.hasOwn(value, field)) result.push(`${at}.${field}: required`);
      if (node.additionalProperties === false) for (const field of Object.keys(value)) if (!Object.hasOwn(node.properties ?? {}, field)) result.push(`${at}.${field}: additional property`);
      for (const [field, child] of Object.entries(node.properties ?? {})) if (Object.hasOwn(value, field)) result.push(...errors(child, value[field], `${at}.${field}`));
    }
    return result;
  }
  inspect(rootSchema);
  return { valid: (record, label) => assert.deepEqual(errors(rootSchema, record), [], `${label} violates the closed v1 schema`) };
}

const constitutionSchema = read("docs/autonomy-constitution-v1.schema.json");
const journalSchema = read("docs/autonomous-mutation-journal-v1.schema.json");
const coverageSchema = read("docs/autonomy-coverage-registry-v1.schema.json");
const ownerAttestationSchema = read("docs/autonomy-owner-attestation-registry-v1.schema.json");
const ownerAuthorizationSchema = read("docs/autonomy-owner-authorization-v1.schema.json");
const runtimeNarrowingSchema = read("docs/autonomy-runtime-narrowing-v1.schema.json");
const recoveryWorkerRegistrySchema = read("docs/autonomy-recovery-worker-registry-v1.schema.json");
const constitutionShape = schemaChecker(constitutionSchema);
const journalShape = schemaChecker(journalSchema);
const coverageShape = schemaChecker(coverageSchema);
const ownerAttestationShape = schemaChecker(ownerAttestationSchema);
const ownerAuthorizationShape = schemaChecker(ownerAuthorizationSchema);
const runtimeNarrowingShape = schemaChecker(runtimeNarrowingSchema);
const recoveryWorkerRegistryShape = schemaChecker(recoveryWorkerRegistrySchema);
const constitution = read("docs/autonomy-constitution-v1.json");
const constitutionFixture = read("tests/fixtures/autonomy-contract/constitution.json");
const coverage = read("docs/autonomy-coverage-registry-v1.json");
const armedCoverage = read("tests/fixtures/autonomy-contract/coverage-armed-canary.json");
const ownerAttestations = read("docs/autonomy-owner-attestation-registry-v1.json");
const productionAuthorization = read("docs/autonomy-owner-authorization-v1.json");
const runtimeNarrowing = read("docs/autonomy-runtime-narrowing-v1.json");
const recoveryWorkerRegistry = read("docs/autonomy-recovery-worker-registry-v1.json");
const conformanceText = fs.readFileSync(path.join(root, "docs/autonomy-journal-conformance-v1.md"), "utf8");
const journalPaths = [
  "tests/fixtures/autonomy-contract/journal-happy-commit.json",
  "tests/fixtures/autonomy-contract/journal-r-exact-revert.json",
  "tests/fixtures/autonomy-contract/journal-r-forward-recovery.json",
  "tests/fixtures/autonomy-contract/journal-terminally-blocked.json"
];
const journals = journalPaths.map(read);
const protectedDomains = ["credentials-and-auth", "owner-policy", "constitution-and-safety-gates", "deployments-and-code", "privacy-retention-and-erasure", "firmware", "remote-recovery", "model-weight-training", "irreversible-external-actions", "package-downgrade"];
const roles = ["owner", "controller", "watchdog", "kill-switch", "recovery-worker"];
const commonFaults = ["executor-interruption", "observer-cannot-actuate", "recovery-path-proven", "recovery-failure-disarms", "stale-evidence-rejected", "chain-tamper-rejected", "late-mutation-rejected", "kill-switch-rejected"];
const classes = {
  "micro-routing": { levels: ["L4", "L5"], ownerScope: "fixed-component", owner: "gille-inference", recovery: "R-exact", readback: "micro-route-readback-matches-candidate" },
  "macro-routing": { levels: ["L5"], ownerScope: "fixed-component", owner: "hugin", recovery: "R-exact", readback: "macro-route-readback-matches-candidate" },
  prompt: { levels: ["L5"], ownerScope: "owning-component", owner: "owning-component", recovery: "R-exact", readback: "prompt-config-readback-matches-candidate" },
  harness: { levels: ["L5"], ownerScope: "owning-component", owner: "owning-component", recovery: "R-exact", readback: "harness-config-readback-matches-candidate" },
  "tool-policy": { levels: ["L5"], ownerScope: "owning-component", owner: "owning-component", recovery: "R-exact", readback: "tool-policy-readback-matches-candidate" },
  "served-model-roster": { levels: ["L5"], ownerScope: "fixed-component", owner: "gille-inference", recovery: "R-exact", readback: "served-model-roster-readback-matches-candidate" },
  "no-reboot-security-bugfix-maintenance": { levels: ["L4"], ownerScope: "fixed-component", owner: "brokkr", recovery: "R-forward", readback: "maintenance-safe-state-readback" }
};
const classNames = Object.keys(classes);

function constitutionSemantics(record) {
  constitutionShape.valid(record, "constitution fixture");
  assert.equal(record.constitution_digest, digest(record, "constitution_digest"), "constitution digest binds every constitutional field");
  assert.deepEqual([...record.protected_lanes].sort(), [...protectedDomains].sort(), "protected lanes are an exact permanent set");
  assert.ok(Object.values(record.safety_floors).every((value) => value === true), "all safety floors are mandatory true");
  assert.deepEqual(record.autonomous_classes.map((entry) => entry.class).sort(), [...classNames].sort(), "exactly the seven approved classes exist");
  for (const entry of record.autonomous_classes) {
    const policy = classes[entry.class];
    assert.deepEqual([entry.required_for_levels, entry.owner_scope, entry.owner, entry.recovery_class], [policy.levels, policy.ownerScope, policy.owner, policy.recovery], `${entry.class} has approved levels, owner scope, owner, and recovery class`);
    assert.deepEqual([...entry.required_identity_roles].sort(), [...roles].sort(), `${entry.class} requires separated authority roles`);
    assert.deepEqual([entry.bounds.min_seconds_between_attempts, entry.bounds.max_attempts_per_window, entry.bounds.attempt_window_seconds, entry.bounds.max_silence_seconds, entry.bounds.trusted_watchdog_time_required], [3600, 1, 86400, 900, true], `${entry.class} has a trusted-clock attempt and watchdog floor`);
    assert.deepEqual([...entry.success_postconditions].sort(), ["verifier-passes", "canary-watch-complete", policy.readback].sort(), `${entry.class} success keeps only candidate/readback conditions`);
    const recoveryPostconditions = policy.recovery === "R-exact"
      ? ["baseline-digest-restored", "coverage-demoted-to-shadow", "recovery-worker-disarm-confirmed"]
      : ["safe-state-verified", "quarantine-active", "coverage-demoted-to-shadow", "recovery-worker-disarm-confirmed"];
    assert.deepEqual([...entry.recovery_postconditions].sort(), recoveryPostconditions.sort(), `${entry.class} has class-appropriate recovery-only postconditions`);
    for (const requirement of commonFaults) assert.ok(entry.fault_injection_requirements.includes(requirement), `${entry.class} proves ${requirement}`);
    if (policy.recovery === "R-forward") assert.ok(entry.fault_injection_requirements.includes("canary-breach-quarantines"), "R-forward proves quarantine");
  }
}

function runtimeNarrowingSemantics(record) {
  runtimeNarrowingShape.valid(record, "runtime narrowing ledger");
  assert.deepEqual(record.entries, [], "W0.1 carries no runtime narrowing records");
  assert.equal(record.owner_authorization_digest, "sha256:0000000000000000000000000000000000000000000000000000000000000000", "unconfigured owner authorization cannot imply runtime authority");
}

function recoveryWorkerRegistrySemantics(record) {
  recoveryWorkerRegistryShape.valid(record, "recovery worker registry");
  assert.equal(record.registry_digest, digest(record, "registry_digest"), "recovery worker registry is digest-bound");
  assert.deepEqual(record.entries, [], "W0.1 provisions no recovery worker key in production");
}

function ownerAttestationSemantics(record) {
  ownerAttestationShape.valid(record, "owner attestation registry");
  assert.equal(record.registry_digest, digest(record, "registry_digest"), "owner attestation registry is digest-bound");
  assert.equal(record.mutation_policy, "owner-controlled-protected-lane", "only the owner may attest target ownership");
  assert.equal(new Set(record.attestations.map((entry) => entry.attestation_id)).size, record.attestations.length, "owner attestation identities are unique");
  assert.equal(new Set(record.attestations.map((entry) => `${entry.domain}:${entry.target_scope_digest}`)).size, record.attestations.length, "one owner attestation exists per domain target");
  for (const entry of record.attestations) assert.equal(entry.attestation_digest, digest(entry, "attestation_digest"), `${entry.attestation_id} is independently digest-bound`);
}

function bindingAttested(binding, domain, registry = ownerAttestations) {
  return registry.attestations.some((entry) => `ref:${entry.attestation_id}` === binding.configuration_owner_authority_ref
    && entry.attestation_digest === binding.configuration_owner_authority_digest
    && entry.domain === domain
    && entry.target_scope_digest === binding.target_scope_digest
    && entry.configuration_owner === binding.configuration_owner);
}

function addOwnerAttestation(registry, entry) {
  const attestation = { ...entry, attestation_digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000" };
  attestation.attestation_digest = digest(attestation, "attestation_digest");
  registry.attestations.push(attestation);
  registry.registry_digest = digest(registry, "registry_digest");
  return attestation;
}

function coverageSemantics(record, c, mode, attestationRegistry = ownerAttestations) {
  coverageShape.valid(record, "coverage registry");
  assert.equal(record.registry_digest, digest(record, "registry_digest"), "registry digest binds coverage");
  assert.equal(record.constitution_digest, c.constitution_digest, "coverage is constitution-bound");
  assert.equal(record.mutation_policy, "owner-widen-recovery-worker-narrow", "only the owner may widen/re-arm; a bound recovery worker may only narrow/disarm");
  assert.equal(record.global_state, mode === "w0" ? "disarmed" : "armed", `${mode} registry has its declared global state`);
  assert.equal(new Set(record.domains.map((entry) => entry.domain)).size, record.domains.length, "coverage domains are unique");
  assert.deepEqual(record.domains.map((entry) => entry.domain).sort(), [...classNames, ...protectedDomains].sort(), "coverage has one exact row for every approved or protected domain");
  const allIdentities = [];
  for (const entry of record.domains) {
    if (protectedDomains.includes(entry.domain)) {
      assert.deepEqual([entry.required_for_levels, entry.owner_scope, entry.owner, entry.recovery_class, entry.coverage, entry.target_state, entry.bindings], [["permanent"], "owner-only", "owner", "none", "protected", "never-mechanical", []], `${entry.domain} remains protected`);
      continue;
    }
    const policy = classes[entry.domain];
    const expectedCoverage = mode === "armed-fixture" && policy.ownerScope === "fixed-component" ? "armed-canary" : "shadow";
    assert.deepEqual([entry.required_for_levels, entry.owner_scope, entry.owner, entry.recovery_class, entry.coverage, entry.target_state], [policy.levels, policy.ownerScope, policy.owner, policy.recovery, expectedCoverage, "armed-canary"], `${entry.domain} has accurate ${mode} coverage`);
    if (policy.ownerScope === "owning-component") assert.equal(entry.bindings.length, 0, `${entry.domain} has no implicit fleet writer in W0`);
    for (const binding of entry.bindings) {
      if (policy.ownerScope === "fixed-component") assert.deepEqual([binding.writer_owner, binding.configuration_owner], [policy.owner, policy.owner], `${entry.domain} binding stays with its fixed configuration owner`);
      assert.equal(binding.writer_owner, binding.configuration_owner, "mechanical writer must be the attested configuration owner");
      assert.ok(bindingAttested(binding, entry.domain, attestationRegistry), `${entry.domain} target owner resolves through the independent owner attestation registry`);
      assert.notEqual(binding.writer_owner, "owning-component", "writer owner must be a concrete component");
      assert.equal(binding.state, expectedCoverage, `${mode} binding state matches its domain coverage`);
      assert.equal(new Set(Object.values(binding.identities)).size, roles.length, "binding authority identities are separated");
      allIdentities.push(...Object.values(binding.identities));
    }
    assert.equal(new Set(entry.bindings.map((binding) => binding.target_scope_digest)).size, entry.bindings.length, `${entry.domain} target bindings are unique`);
  }
  assert.equal(new Set(allIdentities).size, allIdentities.length, "authority identities cannot alias across W0 bindings");
}

const eligibleAdmission = Object.freeze({ ownerAuthorizationVerified: true, effectiveTargetState: "armed-canary", killSwitchSafe: true, evidenceFreshEligible: true, journalHealthy: true, journalTerminal: false, trustedWatchdogTime: true, silenceBreached: false, attemptIntervalAllowed: true, attemptWindowAllowed: true });
function mayActuate(record, attestationRegistry, domain, writerOwner, controllerIdentity, targetScopeDigest, admission) {
  ownerAttestationSemantics(attestationRegistry);
  const row = record.domains.find((entry) => entry.domain === domain);
  const binding = row?.bindings.find((entry) => entry.target_scope_digest === targetScopeDigest);
  return admission?.ownerAuthorizationVerified === true
    && ["armed-canary", "armed-fleet"].includes(admission.effectiveTargetState)
    && admission.killSwitchSafe === true
    && admission.evidenceFreshEligible === true
    && admission.journalHealthy === true
    && admission.journalTerminal === false
    && admission.trustedWatchdogTime === true
    && admission.silenceBreached === false
    && admission.attemptIntervalAllowed === true
    && admission.attemptWindowAllowed === true
    && record.global_state === "armed"
    && ["armed-canary", "armed-fleet"].includes(row?.coverage)
    && ["armed-canary", "armed-fleet"].includes(binding?.state)
    && binding?.writer_owner === writerOwner
    && binding?.configuration_owner === writerOwner
    && bindingAttested(binding, domain, attestationRegistry)
    && binding?.identities.controller === controllerIdentity;
}

function levelReady(record, c, level, attestationRegistry = ownerAttestations) {
  ownerAttestationSemantics(attestationRegistry);
  if (record.global_state !== "armed") return false;
  const requiredLevels = level === "L5" ? ["L4", "L5"] : ["L4"];
  return c.autonomous_classes
    .filter((policy) => policy.required_for_levels.some((requiredLevel) => requiredLevels.includes(requiredLevel)))
    .every((policy) => {
      const row = record.domains.find((entry) => entry.domain === policy.class);
      if (!["armed-canary", "armed-fleet"].includes(row?.coverage)) return false;
      return row.bindings.some((binding) => {
        if (!["armed-canary", "armed-fleet"].includes(binding.state)) return false;
        if (binding.writer_owner !== binding.configuration_owner) return false;
        if (!bindingAttested(binding, policy.class, attestationRegistry)) return false;
        return policy.owner_scope === "owning-component" || binding.writer_owner === policy.owner;
      });
    });
}

const outcomeFor = { prepare: "prepared", apply: "applied", verify: "verified", watch: "watching", commit: "committed", unknown: "unknown", revert: "reverted", recover: "recovered", quarantine: "quarantined", disarm: "disarmed", "terminally-blocked": "terminally-blocked" };
function journalSemantics(record, c, registry = armedCoverage) {
  journalShape.valid(record, `${record.domain} journal`);
  assert.equal(record.constitution_digest, c.constitution_digest, "journal is constitution-bound");
  const policy = c.autonomous_classes.find((entry) => entry.class === record.domain);
  assert.ok(policy, "journal domain is an approved class");
  const row = registry.domains.find((entry) => entry.domain === record.domain);
  const b = record.binding;
  const ownerBinding = row?.bindings.find((entry) => entry.target_scope_digest === b.target_scope_digest
    && entry.writer_owner === b.writer_owner
    && entry.owner_authority_ref === b.owner_authority_ref
    && entry.owner_authority_digest === b.owner_authority_digest
    && entry.configuration_owner === b.configuration_owner
    && entry.configuration_owner_authority_ref === b.configuration_owner_authority_ref
    && entry.configuration_owner_authority_digest === b.configuration_owner_authority_digest);
  assert.ok(ownerBinding, "journal binds a concrete owner-controlled coverage entry");
  assert.equal(registry.global_state, "armed", "admission snapshot is globally armed");
  assert.ok(["armed-canary", "armed-fleet"].includes(row.coverage), "admission class is armed");
  assert.equal(b.admission_coverage_digest, registry.registry_digest, "journal binds the canonical admitted coverage snapshot");
  assert.equal(b.admission_binding_state, ownerBinding.state, "journal admitted state matches the canonical binding");
  assert.equal(b.writer_owner, b.configuration_owner, "journal writer is the attested configuration owner");
  assert.ok(bindingAttested(b, record.domain), "journal target owner resolves through the independent protected attestation");
  assert.equal(record.binding_digest, digest(b), "immutable candidate/config/evidence/policy and authority binding is digest-bound");
  assert.equal(b.risk_scope, record.domain, "risk scope binds class");
  assert.notEqual(b.attempt_id, b.recovery_disarm_id, "attempt terminal and recovery disarm have distinct identities");
  for (const [field, identity] of [["owner_identity", "owner"], ["controller_identity", "controller"], ["watchdog_identity", "watchdog"], ["kill_switch_identity", "kill_switch"], ["recovery_worker_identity", "recovery_worker"]]) assert.equal(b[field], ownerBinding.identities[identity], `${field} binds coverage authority`);
  assert.equal(b.recovery.class, policy.recovery_class, "recovery class matches constitution");
  assert.equal(b.recovery.worker_identity, b.recovery_worker_identity, "recovery worker is immutable");
  assert.equal(b.canary.scope_digest, b.target_scope_digest, "canary scope matches owner-controlled target binding");
  assert.ok(Date.parse(b.canary.watch_deadline) <= Date.parse(b.deadline), "watch completion bound is within mutation deadline");
  assert.ok(Date.parse(b.deadline) - Date.parse(record.entries[0].recorded_at) <= policy.bounds.deadline_seconds * 1000, "attempt deadline stays within constitutional bound");
  const transitions = policy.recovery_class === "R-exact"
    ? { prepare: ["apply", "unknown"], apply: ["verify", "unknown"], verify: ["watch", "unknown"], watch: ["commit", "unknown"], commit: [], unknown: ["revert", "terminally-blocked"], revert: ["disarm", "terminally-blocked"], disarm: [], "terminally-blocked": [] }
    : { prepare: ["apply", "unknown"], apply: ["verify", "unknown"], verify: ["watch", "unknown"], watch: ["commit", "unknown"], commit: [], unknown: ["recover", "terminally-blocked"], recover: ["quarantine", "terminally-blocked"], quarantine: ["disarm", "terminally-blocked"], disarm: [], "terminally-blocked": [] };
  let previous = null;
  const ids = new Set();
  for (const [index, entry] of record.entries.entries()) {
    assert.ok(!ids.has(entry.entry_id), "entry identity cannot replay");
    ids.add(entry.entry_id);
    assert.equal(entry.sequence, index + 1, "sequence is contiguous");
    assert.equal(entry.binding_digest, record.binding_digest, "every receipt binds immutable identity bundle");
    assert.equal(entry.previous_receipt_digest, previous, "receipt chain is contiguous");
    assert.equal(entry.receipt_digest, digest(entry, "receipt_digest"), "receipt digest binds full content-blind entry");
    assert.equal(entry.outcome, outcomeFor[entry.phase], "phase and outcome pair is exact");
    if (index) {
      assert.ok(Date.parse(entry.recorded_at) >= Date.parse(record.entries[index - 1].recorded_at), "journal clocks cannot move backwards");
      assert.ok(transitions[record.entries[index - 1].phase].includes(entry.phase), `illegal transition ${record.entries[index - 1].phase} -> ${entry.phase}`);
    }
    if (["prepare", "apply", "verify", "watch", "commit"].includes(entry.phase)) assert.ok(Date.parse(entry.recorded_at) <= Date.parse(b.deadline), "no admission or mutation phase may occur after the deadline");
    if (entry.phase === "watch") {
      assert.ok(Date.parse(entry.recorded_at) <= Date.parse(b.canary.watch_deadline), "watch starts by its completion bound");
      assert.ok(Date.parse(b.canary.watch_deadline) - Date.parse(entry.recorded_at) <= policy.bounds.watch_seconds * 1000, "watch duration stays within constitutional bound");
    }
    if (entry.phase === "commit") assert.ok(Date.parse(entry.recorded_at) >= Date.parse(b.canary.watch_deadline), "commit waits for the full watch window");
    const recoveryPhase = ["revert", "recover", "quarantine", "disarm", "terminally-blocked"].includes(entry.phase);
    if (entry.phase === "unknown") assert.ok([b.controller_identity, b.watchdog_identity].includes(entry.executor_identity), "only controller or watchdog may declare uncertainty");
    else assert.equal(entry.executor_identity, recoveryPhase ? b.recovery_worker_identity : b.controller_identity, "controller, watchdog, and recovery worker stay separated");
    if (["unknown", "disarm", "terminally-blocked"].includes(entry.phase)) assert.ok(entry.terminal_reason_digest, `${entry.phase} records a terminal/recovery reason digest`);
    if (entry.phase === "terminally-blocked") assert.equal(entry.quarantine.state, "active", "terminally blocked attempts remain quarantined");
    if (["disarm", "terminally-blocked"].includes(entry.phase)) {
      assert.ok(entry.coverage_transition, `${entry.phase} carries the authoritative coverage demotion receipt`);
      assert.equal(entry.coverage_transition.from_state, b.admission_binding_state, "recovery demotion starts from the immutable admitted state");
      assert.equal(entry.coverage_transition.to_state, "shadow", "recovery may only narrow coverage to shadow");
      assert.equal(entry.coverage_transition.target_scope_digest, b.target_scope_digest, "recovery narrows only its exact bound target");
      assert.equal(entry.coverage_transition.actor_identity, b.recovery_worker_identity, "recovery worker owns the narrowing receipt");
      assert.equal(entry.coverage_transition.actor_identity, entry.executor_identity, "coverage transition actor signs its own journal entry");
    } else {
      assert.equal(entry.coverage_transition, null, `${entry.phase} cannot change coverage`);
    }
    assert.ok(entry.content_refs.every((ref) => /^ref:[a-z][a-z0-9-]{2,120}$/.test(ref) && !/[/:.]/.test(ref.slice(4))), "journal references remain opaque and content-blind");
    previous = entry.receipt_digest;
  }
  assert.equal(record.entries[0].phase, "prepare", "journal starts prepared");
  const terminal = record.entries.at(-1).phase;
  assert.ok(["commit", "disarm", "terminally-blocked"].includes(terminal), "attempt has an explicit terminal state");
  if (terminal === "commit") assert.ok(!record.entries.some((entry) => ["unknown", "revert", "recover", "quarantine", "disarm", "terminally-blocked"].includes(entry.phase)), "successful commit does not disarm or enter recovery");
  if (record.entries.some((entry) => entry.phase === "unknown")) assert.ok(["disarm", "terminally-blocked"].includes(terminal), "uncertainty always ends durably disarmed or blocked");
  if (terminal === "disarm" && policy.recovery_class === "R-exact") assert.ok(record.entries.some((entry) => entry.phase === "revert"), "R-exact disarm follows exact revert");
  if (terminal === "disarm" && policy.recovery_class === "R-forward") {
    assert.ok(record.entries.some((entry) => entry.phase === "recover"), "R-forward disarm follows bounded forward recovery");
    assert.ok(record.entries.some((entry) => entry.phase === "quarantine" && entry.quarantine.state === "active"), "R-forward quarantines before disarm");
  }
}

function resign(record) {
  record.binding_digest = digest(record.binding);
  let previous = null;
  for (const entry of record.entries) {
    entry.binding_digest = record.binding_digest;
    entry.previous_receipt_digest = previous;
    entry.receipt_digest = digest(entry, "receipt_digest");
    previous = entry.receipt_digest;
  }
  return record;
}
function mustReject(mutator, message) {
  assert.throws(() => journalSemantics(mutator(), constitution), message);
}

constitutionSemantics(constitution);
ownerAttestationSemantics(ownerAttestations);
coverageSemantics(coverage, constitution, "w0");
assert.deepEqual(constitution, constitutionFixture, "production constitution is the authority; the fixture is byte-equivalent test data");
ownerAuthorizationShape.valid(productionAuthorization, "unconfigured production owner authorization");
runtimeNarrowingSemantics(runtimeNarrowing);
recoveryWorkerRegistrySemantics(recoveryWorkerRegistry);
assert.match(conformanceText, /verifier-derived\nproofs, never caller-supplied claims/, "admission facts are not caller claims");
coverageSemantics(armedCoverage, constitution, "armed-fixture");
// Positive fixtures are canonical serialized receipts, not templates. Consumers validate the exact
// checked-in bytes without filling, resigning, or otherwise mutating them first.
journals.forEach((journal) => journalSemantics(journal, constitution, armedCoverage));

mustReject(() => { const x = resign(clone(journals[1])); x.entries[2].phase = "apply"; x.entries[2].outcome = "applied"; return resign(x); }, "unknown cannot retry or re-arm");
mustReject(() => { const x = resign(clone(journals[0])); x.binding.canary.target_count = 2; return resign(x); }, "canary cannot expand");
mustReject(() => { const x = resign(clone(journals[2])); x.entries[3].executor_identity = x.binding.controller_identity; return resign(x); }, "controller cannot impersonate recovery worker");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].executor_identity = x.binding.watchdog_identity; return resign(x); }, "observer cannot actuate");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].command = "forbidden"; return resign(x); }, "commands are structurally rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].content_refs = ["ref:private/locator"]; return resign(x); }, "private locators are rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].content_refs = ["ref:"]; return resign(x); }, "empty opaque reference identities are rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].content_refs = ["ref:1private"]; return resign(x); }, "opaque reference identities start with a lowercase letter");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].content_refs = ["ref:Private"]; return resign(x); }, "opaque reference identities remain lowercase");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[0].recorded_at = "2026-07-26T01:01:00Z"; return resign(x); }, "late prepare is rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.entries[1].recorded_at = "2026-07-26T01:01:00Z"; return resign(x); }, "late apply is rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.entries.at(-1).recorded_at = "2026-07-26T00:29:00Z"; return resign(x); }, "commit before watch completion is rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.binding.deadline = "2026-02-31T00:00:00Z"; return resign(x); }, "normalized invalid calendar instants are rejected");
mustReject(() => { const x = clone(journals[0]); x.entries[1].binding_digest = x.binding_digest.replace(/0/, "1"); return x; }, "binding identity drift is rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.binding.writer_owner = "hugin"; return resign(x); }, "cross-owner binding is rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.binding.owner_authority_digest = "sha256:7777777777777777777777777777777777777777777777777777777777777777"; return resign(x); }, "self-asserted owner authority is rejected");
mustReject(() => { const x = resign(clone(journals[0])); x.binding.configuration_owner = "hugin"; return resign(x); }, "writer cannot replace the attested configuration owner");
mustReject(() => { const x = resign(clone(journals[0])); x.binding.admission_coverage_digest = coverage.registry_digest; return resign(x); }, "journal cannot claim a different coverage snapshot");
mustReject(() => { const x = resign(clone(journals[0])); x.binding.admission_binding_state = "armed-fleet"; return resign(x); }, "journal cannot inflate admitted binding state");
mustReject(() => { const x = resign(clone(journals[1])); x.entries.at(-1).coverage_transition.target_scope_digest = "sha256:9999999999999999999999999999999999999999999999999999999999999999"; return resign(x); }, "recovery cannot narrow another target");
mustReject(() => { const x = resign(clone(journals[1])); x.entries.at(-1).coverage_transition.actor_identity = x.binding.controller_identity; return resign(x); }, "controller cannot forge recovery narrowing");
mustReject(() => { const x = resign(clone(journals[1])); x.entries.at(-1).coverage_transition.to_state = "armed-fleet"; return resign(x); }, "recovery cannot widen or re-arm");
mustReject(() => { const x = clone(journals[2]); x.entries = x.entries.filter((entry) => entry.phase !== "quarantine"); return resign(x); }, "R-forward recovery cannot disarm without active quarantine");
{ const x = clone(constitution); x.protected_lanes.pop(); x.constitution_digest = digest(x, "constitution_digest"); assert.throws(() => constitutionSemantics(x), "protected-lane substitution is rejected"); }
{ const x = clone(constitution); x.autonomous_classes.find((entry) => entry.class === "prompt").owner_scope = "fixed-component"; x.constitution_digest = digest(x, "constitution_digest"); assert.throws(() => constitutionSemantics(x), "generic owner scope cannot collapse to Hugin"); }
{ const x = clone(coverage); x.domains[0].coverage = "armed-canary"; x.registry_digest = digest(x, "registry_digest"); assert.throws(() => coverageSemantics(x, constitution, "w0"), "disarmed W0 cannot claim armed coverage"); }
{ const x = clone(coverage); x.domains.push(clone(x.domains[0])); x.registry_digest = digest(x, "registry_digest"); assert.throws(() => coverageSemantics(x, constitution, "w0"), "duplicate coverage domain is rejected"); }
{ const x = clone(coverage); x.domains.find((entry) => entry.domain === "micro-routing").bindings[0].writer_owner = "hugin"; x.registry_digest = digest(x, "registry_digest"); assert.throws(() => coverageSemantics(x, constitution, "w0"), "fixed owner alignment is enforced"); }
{ const x = clone(ownerAttestations); x.attestations[0].configuration_owner = "hugin"; x.attestations[0].attestation_digest = digest(x.attestations[0], "attestation_digest"); x.registry_digest = digest(x, "registry_digest"); assert.throws(() => coverageSemantics(coverage, constitution, "w0", x), "a re-signed false target-owner attestation cannot replace the bound owner"); }
{ const x = clone(ownerAttestations); x.attestations[0].target_scope_digest = "sha256:9999999999999999999999999999999999999999999999999999999999999999"; x.attestations[0].attestation_digest = digest(x.attestations[0], "attestation_digest"); x.registry_digest = digest(x, "registry_digest"); assert.throws(() => coverageSemantics(coverage, constitution, "w0", x), "owner attestation is target-scope bound"); }
{
  const x = clone(coverage);
  const testAttestations = clone(ownerAttestations);
  x.global_state = "armed";
  const prompt = x.domains.find((entry) => entry.domain === "prompt");
  prompt.coverage = "armed-canary";
  const targetScope = "sha256:9999999999999999999999999999999999999999999999999999999999999999";
  const muninAttestation = addOwnerAttestation(testAttestations, { attestation_id: "munin-prompt-config-owner-attestation", domain: "prompt", target_scope_digest: targetScope, configuration_owner: "munin-memory", issued_at: "2026-07-26T00:00:00Z" });
  prompt.bindings.push({ writer_owner: "munin-memory", owner_authority_ref: "ref:munin-memory-owner-authority", owner_authority_digest: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", configuration_owner: "munin-memory", configuration_owner_authority_ref: `ref:${muninAttestation.attestation_id}`, configuration_owner_authority_digest: muninAttestation.attestation_digest, target_scope_digest: targetScope, state: "armed-canary", identities: { owner: "munin-owner", controller: "munin-prompt-controller", watchdog: "munin-prompt-watchdog", kill_switch: "munin-prompt-kill-switch", recovery_worker: "munin-prompt-revert-worker" } });
  assert.equal(mayActuate(x, testAttestations, "prompt", "hugin", "munin-prompt-controller", prompt.bindings[0].target_scope_digest, eligibleAdmission), false, "Hugin cannot actuate another owner's prompt binding");
  assert.equal(mayActuate(x, testAttestations, "prompt", "munin-memory", "munin-prompt-controller", prompt.bindings[0].target_scope_digest, eligibleAdmission), true, "the attested configuration owner can actuate after separate arming");
  prompt.bindings[0].writer_owner = "hugin";
  prompt.bindings[0].configuration_owner = "hugin";
  assert.equal(bindingAttested(prompt.bindings[0], "prompt", testAttestations), false, "self-relabelling fails the independent owner attestation directly");
  assert.equal(mayActuate(x, testAttestations, "prompt", "hugin", "munin-prompt-controller", prompt.bindings[0].target_scope_digest, eligibleAdmission), false, "self-relabelling cannot replace the independent target-owner attestation");
}
{
  const x = clone(coverage);
  const levelAttestations = clone(ownerAttestations);
  assert.equal(levelReady(x, constitution, "L4"), false, "globally disarmed W0 cannot claim L4");
  x.global_state = "armed";
  const micro = x.domains.find((entry) => entry.domain === "micro-routing");
  micro.coverage = "armed-canary";
  micro.bindings[0].state = "armed-canary";
  assert.equal(levelReady(x, constitution, "L4"), false, "micro-routing alone cannot claim L4");
  const maintenance = x.domains.find((entry) => entry.domain === "no-reboot-security-bugfix-maintenance");
  maintenance.coverage = "armed-canary";
  maintenance.bindings[0].state = "armed-canary";
  assert.equal(levelReady(x, constitution, "L4"), true, "L4 requires both micro-routing and no-reboot maintenance");
  assert.equal(levelReady(x, constitution, "L5"), false, "L4 readiness cannot claim L5");
  for (const policy of constitution.autonomous_classes.filter((entry) => entry.required_for_levels.includes("L5"))) {
    const row = x.domains.find((entry) => entry.domain === policy.class);
    row.coverage = "armed-canary";
    if (!row.bindings.length) {
      const prefix = policy.class.replaceAll("-", "");
      const targetScope = `sha256:${String(classNames.indexOf(policy.class) + 1).repeat(64)}`;
      const configOwner = `${prefix}-owner-repo`;
      const ownerAttestation = addOwnerAttestation(levelAttestations, { attestation_id: `${prefix}-config-owner-attestation`, domain: policy.class, target_scope_digest: targetScope, configuration_owner: configOwner, issued_at: "2026-07-26T00:00:00Z" });
      row.bindings.push({ writer_owner: configOwner, owner_authority_ref: `ref:${prefix}-owner-authority`, owner_authority_digest: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", configuration_owner: configOwner, configuration_owner_authority_ref: `ref:${ownerAttestation.attestation_id}`, configuration_owner_authority_digest: ownerAttestation.attestation_digest, target_scope_digest: targetScope, state: "armed-canary", identities: { owner: `${prefix}-owner`, controller: `${prefix}-controller`, watchdog: `${prefix}-watchdog`, kill_switch: `${prefix}-kill-switch`, recovery_worker: `${prefix}-recovery-worker` } });
    } else row.bindings[0].state = "armed-canary";
  }
  assert.equal(levelReady(x, constitution, "L5", levelAttestations), true, "L5 requires every declared and owner-attested L5 axis");
  maintenance.bindings[0].state = "shadow";
  assert.equal(levelReady(x, constitution, "L5", levelAttestations), false, "L5 also retains every L4 prerequisite");
}
{
  const x = clone(armedCoverage);
  const micro = x.domains.find((entry) => entry.domain === "micro-routing");
  const maintenance = x.domains.find((entry) => entry.domain === "no-reboot-security-bugfix-maintenance");
  maintenance.coverage = "shadow";
  maintenance.bindings[0].state = "shadow";
  assert.equal(levelReady(x, constitution, "L4"), false, "partial class coverage does not claim aggregate L4 maturity");
  assert.equal(mayActuate(x, ownerAttestations, "micro-routing", "gille-inference", "micro-route-controller", micro.bindings[0].target_scope_digest, eligibleAdmission), true, "an independently approved class may canary before aggregate maturity is complete");
  for (const [field, value] of [["ownerAuthorizationVerified", false], ["effectiveTargetState", "shadow"], ["killSwitchSafe", false], ["evidenceFreshEligible", false], ["journalHealthy", false], ["journalTerminal", true], ["trustedWatchdogTime", false], ["silenceBreached", true], ["attemptIntervalAllowed", false], ["attemptWindowAllowed", false]]) {
    assert.equal(mayActuate(x, ownerAttestations, "micro-routing", "gille-inference", "micro-route-controller", micro.bindings[0].target_scope_digest, { ...eligibleAdmission, [field]: value }), false, `${field} blocks admission`);
  }
}
console.log("autonomy-contract validation passed");
