import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const schema = JSON.parse(fs.readFileSync(path.join(root, "docs/learning-task-contract-v1.schema.json"), "utf8"));
const positive = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/positive.json"), "utf8"));
const positiveDerivedDefinitions = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/positive-derived.json"), "utf8"));
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
    if (node.maxItems !== undefined && value.length > node.maxItems) errors.push(`${at}: more than ${node.maxItems} items`);
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

function digest(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

const lanes = ["chat", "mcp-ask", "delegate", "delegate-disagreement", "delegate-shadow", "code-loop"];

function expectedGovernanceSubjects(record) {
  assert.equal(isUnknown(record.task.source.principal), false, "complete governance requires a known authenticated source principal");
  const expected = new Map([
    [`source:${record.task.origin_component}:${record.task.source.id}`, ["source", record.task.source.principal.id]],
    ["fingerprint:raw", ["raw-fingerprint", record.task.source.principal.id]],
  ]);
  if (record.execution) {
    const prompts = record.execution.prompt_identity;
    if (!isUnknown(prompts.hugin_envelope)) expected.set("fingerprint:hugin-envelope", ["hugin-envelope", record.task.source.principal.id]);
    if (!isUnknown(prompts.gateway_canonical_envelope)) expected.set("fingerprint:gateway-canonical-envelope", ["gateway-canonical-envelope", record.task.source.principal.id]);
    if (!isUnknown(prompts.runtime_chat_template_render)) expected.set("fingerprint:runtime-chat-template-render", ["runtime-chat-template-render", record.task.source.principal.id]);
  }
  for (const artifact of record.artifacts.items) expected.set(artifact.ref, ["artifact", artifact.owner]);
  const repository = record.artifacts.repository;
  if (!isUnknown(repository)) {
    if (!isUnknown(repository.diff_hash)) expected.set("repository:diff-hash", ["repository-diff-hash", record.task.source.principal.id]);
    if (!isUnknown(repository.changed_files_ref)) expected.set(repository.changed_files_ref, ["repository-file-list", record.task.source.principal.id]);
  }
  if (record.quality_receipt) {
    expected.set("quality:task-document", ["quality-binding", record.task.source.principal.id]);
    expected.set("quality:structured-result", ["quality-binding", record.task.source.principal.id]);
    expected.set("quality:rating-reason", ["rating-reason", record.task.source.principal.id]);
  }
  if (record.experiment_product_rating) expected.set("experiment:rating-reason", ["rating-reason", record.task.source.principal.id]);
  return expected;
}

function effectiveGovernance(policies) {
  const sensitivityRank = { public: 0, internal: 1, private: 2 };
  const erasureRank = { active: 0, requested: 1, expired: 2, erased: 3 };
  const sensitivity = policies.reduce((current, p) => sensitivityRank[p.sensitivity] > sensitivityRank[current] ? p.sensitivity : current, "public");
  const allowedUses = policies.slice(1).reduce((uses, p) => uses.filter((use) => p.allowed_uses.includes(use)), [...policies[0].allowed_uses]).sort();
  const knownExpiries = policies.map((p) => p.retention.expires_at).filter((value) => typeof value === "string").sort();
  const expiresAt = knownExpiries[0] ?? { value: null, unknown_reason: "not-applicable" };
  const erasureState = policies.reduce((current, p) => erasureRank[p.erasure.state] > erasureRank[current] ? p.erasure.state : current, "active");
  return { sensitivity, allowedUses, expiresAt, erasureState };
}

function governanceEligibleAt(record, evaluatedAt) {
  if (record.governance.capture_state !== "complete" || !record.governance.effective.evaluation_eligible || record.governance.effective.erasure_state !== "active") return false;
  const expiry = record.governance.effective.expires_at;
  return isUnknown(expiry) ? expiry.unknown_reason === "not-applicable" : Date.parse(expiry) > Date.parse(evaluatedAt);
}

function servingProvenanceComplete(serving) {
  if (isUnknown(serving)) return false;
  return [
    serving.runtime_id,
    serving.provider_id,
    serving.model.id,
    serving.model.artifact_manifest_digest,
    serving.model.effective_config_digest,
    serving.sampling_digest,
  ].every((value) => !isUnknown(value));
}

function candidateProvenanceComplete(record) {
  if (!record.execution) return false;
  const execution = record.execution;
  if (record.task.origin_component === "gille-inference") return [
    execution.prompt_identity.gateway_canonical_envelope,
    execution.prompt_identity.runtime_chat_template_render,
    execution.routing.micro,
    execution.origin_config,
    execution.effective_gateway_config,
  ].every((value) => !isUnknown(value))
    && servingProvenanceComplete(execution.serving)
    && record.transport.state === "direct-gateway";
  const required = [
    execution.prompt_identity.hugin_envelope,
    execution.prompt_identity.gateway_canonical_envelope,
    execution.prompt_identity.runtime_chat_template_render,
    execution.routing.macro,
    execution.routing.micro,
    execution.origin_config,
    execution.effective_gateway_config,
  ];
  if (execution.routing.macro?.target !== "m5") {
    return [
      execution.prompt_identity.hugin_envelope,
      execution.prompt_identity.runtime_chat_template_render,
      execution.routing.macro,
      execution.origin_config,
    ].every((value) => !isUnknown(value)) && servingProvenanceComplete(execution.serving);
  }
  return required.every((value) => !isUnknown(value))
    && servingProvenanceComplete(execution.serving)
    && record.transport.state === "m5-admitted";
}

function provenanceAndGovernanceEligibleAt(record, evaluatedAt) {
  return governanceEligibleAt(record, evaluatedAt) && candidateProvenanceComplete(record);
}

function validateGovernance(record, errors) {
  const governance = record.governance;
  if (governance.capture_state === "policy-unavailable") {
    if (Date.parse(governance.unavailable_at) > Date.parse(record.recorded_at)) errors.push("policy unavailable_at exceeds recorded_at");
    return;
  }
  if (isUnknown(record.task.source.principal)) {
    errors.push("complete governance requires a known authenticated source principal");
    return;
  }
  if (governance.policy_manifest.authenticated_principal !== record.task.source.principal.id) errors.push("policy manifest principal is not the authenticated source principal");
  if (Date.parse(governance.policy_manifest.approved_at) > Date.parse(record.task.source.accepted_at)) errors.push("policy manifest was approved after task acceptance");
  const expected = expectedGovernanceSubjects(record);
  const actual = new Map();
  for (const policy of governance.policies) {
    if (actual.has(policy.subject_ref)) errors.push(`duplicate governance subject_ref ${policy.subject_ref}`);
    actual.set(policy.subject_ref, policy);
    const expiry = policy.retention.expires_at;
    if (isUnknown(expiry) && expiry.unknown_reason !== "not-applicable") errors.push(`policy ${policy.subject_ref} has impermissible unknown expiry`);
    if (typeof expiry === "string" && Date.parse(expiry) <= Date.parse(record.recorded_at)) errors.push(`policy ${policy.subject_ref} expiry does not follow record creation`);
    if (["erased", "expired"].includes(policy.erasure.state) && policy.erasure.digest_disposition !== "removed") errors.push(`policy ${policy.subject_ref} retains digest after ${policy.erasure.state}`);
    if (["erased", "expired"].includes(policy.erasure.state) && isUnknown(policy.erasure.effective_at)) errors.push(`policy ${policy.subject_ref} lacks erasure/expiry effective_at`);
  }
  for (const [ref, [kind, owner]] of expected) {
    const policy = actual.get(ref);
    if (!policy) errors.push(`missing governance policy for ${ref}`);
    else {
      if (policy.subject_kind !== kind) errors.push(`governance subject ${ref} must have kind ${kind}`);
      if (policy.content_owner !== owner) errors.push(`governance subject ${ref} must retain content owner ${owner}`);
    }
  }
  for (const ref of actual.keys()) if (!expected.has(ref)) errors.push(`unexpected governance policy for ${ref}`);
  const computed = effectiveGovernance(governance.policies);
  const declared = governance.effective;
  if (declared.sensitivity !== computed.sensitivity) errors.push(`effective sensitivity ${declared.sensitivity} does not equal strictest ${computed.sensitivity}`);
  if (canonical([...declared.allowed_uses].sort()) !== canonical(computed.allowedUses)) errors.push("effective allowed_uses is not the policy intersection");
  if (canonical(declared.expires_at) !== canonical(computed.expiresAt)) errors.push("effective expires_at is not the earliest safe expiry");
  if (declared.erasure_state !== computed.erasureState) errors.push("effective erasure_state is not the strictest policy state");
  if (canonical([...declared.derived_from_subject_refs].sort()) !== canonical([...actual.keys()].sort())) errors.push("effective derived_from_subject_refs does not name every policy");
  const eligible = computed.allowedUses.includes("evaluation") && computed.erasureState === "active";
  if (declared.evaluation_eligible !== eligible) errors.push("effective evaluation_eligible is not derived fail-closed");
  if (["erased", "expired"].includes(declared.erasure_state)) errors.push("erased/expired content MUST use reduced tombstone projection");
}

function validateTransport(record, errors) {
  if (!record.transport) return;
  const state = record.transport.state;
  const request = record.transport.hugin_request_stamp;
  const echo = record.transport.gateway_echo;
  if (record.task.origin_component !== "hugin") {
    if (state !== "direct-gateway") errors.push("direct origin must use direct-gateway transport state");
    if (!isUnknown(record.execution.prompt_identity.hugin_envelope) || record.execution.prompt_identity.hugin_envelope.unknown_reason !== "not-applicable") errors.push("direct origin Hugin envelope must be not-applicable");
    if (!isUnknown(record.execution.routing.macro) || record.execution.routing.macro.unknown_reason !== "not-applicable") errors.push("direct origin macro routing must be not-applicable");
    for (const [name, value] of [
      ["gateway envelope", record.execution.prompt_identity.gateway_canonical_envelope],
      ["runtime render", record.execution.prompt_identity.runtime_chat_template_render],
      ["micro decision", record.execution.routing.micro],
      ["serving", record.execution.serving],
      ["effective gateway config", record.execution.effective_gateway_config],
    ]) if (isUnknown(value)) errors.push(`direct gateway ${name} must be known`);
    return;
  }

  const macro = record.execution.routing.macro;
  if (isUnknown(macro)) {
    errors.push("Hugin-origin execution requires a known macro route target and service");
    return;
  }
  if (macro.target !== "m5") {
    if (macro.service === "gille-inference") errors.push("non-M5 macro target cannot name the M5 gateway service");
    if (state !== "not-m5") errors.push("non-M5 macro route must use not-m5 transport state");
    if (!isUnknown(record.execution.routing.micro) || record.execution.routing.micro.unknown_reason !== "not-applicable") errors.push("non-M5 route gateway micro decision must be not-applicable");
    if (!isUnknown(record.execution.prompt_identity.gateway_canonical_envelope) || record.execution.prompt_identity.gateway_canonical_envelope.unknown_reason !== "not-applicable") errors.push("non-M5 route gateway envelope must be not-applicable");
    if (!isUnknown(record.execution.effective_gateway_config) || record.execution.effective_gateway_config.unknown_reason !== "not-applicable") errors.push("non-M5 route gateway config must be not-applicable");
    return;
  }
  if (!['m5-admitted', 'm5-not-admitted'].includes(state)) {
    errors.push("M5 macro route must use an M5 transport state");
    return;
  }
  if (macro.service !== "gille-inference") errors.push("M5 macro target must name gille-inference service");
  if (isUnknown(request)) {
    errors.push("dispatched M5 request requires a known Hugin request stamp");
    return;
  }
  if (request.task_instance_id !== record.task.instance_id || request.attempt_id !== record.execution.attempt_id) errors.push("transport stamp does not bind task and attempt");
  for (const field of ["source", "task_type", "raw_fingerprint"]) if (canonical(request[field]) !== canonical(record.task[field])) errors.push(`transport stamp does not bind task.${field}`);
  if (canonical(request.hugin_envelope) !== canonical(record.execution.prompt_identity.hugin_envelope)) errors.push("transport stamp does not bind Hugin envelope");
  if (canonical(request.origin_config) !== canonical(record.execution.origin_config)) errors.push("transport stamp does not bind origin config");
  if (canonical(request.macro_decision) !== canonical(record.execution.routing.macro)) errors.push("transport stamp does not bind macro decision");
  if (request.contract_request.contract_version !== record.contract_version || request.contract_request.schema_revision !== record.schema_revision) errors.push("Hugin contract request does not match record version/revision");
  if (state === "m5-not-admitted") {
    for (const [name, value] of [
      ["gateway envelope", record.execution.prompt_identity.gateway_canonical_envelope],
      ["runtime render", record.execution.prompt_identity.runtime_chat_template_render],
      ["micro decision", record.execution.routing.micro],
      ["serving", record.execution.serving],
      ["effective gateway config", record.execution.effective_gateway_config],
    ]) {
      if (!isUnknown(value) || !["not-admitted", "transport-auth-failed", "producer-error"].includes(value.unknown_reason)) errors.push(`M5 non-admission ${name} must carry the missing-echo reason`);
      else if (value.unknown_reason !== echo.unknown_reason) errors.push(`M5 non-admission ${name} reason must match the missing echo`);
    }
    return;
  }
  if (isUnknown(echo)) {
    errors.push("admitted M5 transport requires an authenticated gateway echo");
    return;
  }
  if (canonical(request) !== canonical(echo.echoed_request)) errors.push("gateway echo does not exactly reproduce Hugin request stamp");
  if (canonical(request.contract_request) !== canonical(echo.capabilities)) errors.push("gateway capabilities do not match Hugin contract request");
  if (echo.authenticated_principal_id !== request.expected_transport_principal_id) errors.push("gateway authenticated principal does not match expected transport principal");
  const principalBindingSource = {
    authenticated_principal_id: echo.authenticated_principal_id,
    expected_transport_principal_id: request.expected_transport_principal_id,
    client_id: request.client_id,
    idempotency_key: request.idempotency_key,
    request_id: request.request_id,
    task_instance_id: request.task_instance_id,
    attempt_id: request.attempt_id,
    contract_request: request.contract_request,
  };
  if (echo.principal_binding_digest.digest !== digest(canonical(principalBindingSource))) errors.push("gateway principal binding digest does not bind principal/request identity");
  if (Date.parse(echo.admitted_at) < Date.parse(record.task.source.accepted_at) || Date.parse(echo.admitted_at) > Date.parse(record.execution.started_at)) errors.push("gateway admission clock is outside acceptance/start interval");
}

function validateTombstone(record) {
  const errors = [];
  const protocol = record.tombstone.erasure_protocol;
  if (Date.parse(record.recorded_at) < Date.parse(record.tombstone.effective_at)) errors.push("tombstone recorded_at precedes effective_at");
  if (Date.parse(protocol.requested_at) > Date.parse(record.tombstone.effective_at)) errors.push("erasure request follows effective erasure");
  const expectedStores = ["hugin-task-store", "hugin-workspace-log-result", "munin", "gille-ledger", "gille-owner-log", "gille-exposure", "gille-code-loop"];
  if (canonical(protocol.core_stores.map((entry) => entry.store).sort()) !== canonical([...expectedStores].sort())) errors.push("erasure protocol must cover every core store exactly once");
  if (protocol.artifact_stores.length !== protocol.expected_artifact_store_receipts) errors.push("erasure protocol artifact receipt count does not match pre-erasure inventory");
  if (new Set(protocol.artifact_stores.map((receipt) => receipt.inventory_entry_id)).size !== protocol.artifact_stores.length) errors.push("artifact erasure receipts must bind unique inventory entries");
  for (const receipt of [...protocol.core_stores, ...protocol.artifact_stores]) if (Date.parse(receipt.readback_at) < Date.parse(protocol.requested_at) || Date.parse(receipt.readback_at) > Date.parse(record.tombstone.effective_at)) errors.push(`store ${receipt.store ?? receipt.store_class} readback clock is outside erasure interval`);
  if (!(Date.parse(protocol.requested_at) <= Date.parse(protocol.backup_expiry.deadline)
    && Date.parse(protocol.backup_expiry.deadline) <= Date.parse(protocol.backup_expiry.verified_at)
    && Date.parse(protocol.backup_expiry.verified_at) <= Date.parse(record.tombstone.effective_at))) errors.push("backup expiry clocks must satisfy requested <= deadline <= verified <= effective");
  const counterOwners = { "hugin-capture-denominator": "hugin", "hugin-m5-join-denominator": "hugin", "direct-m5-exposure-denominator": "gille-inference", "evaluation-candidate-denominator": "hugin" };
  const counterPeriods = new Set();
  for (const entry of record.tombstone.counter_audit) {
    if (counterOwners[entry.counter] !== record.producer.component) errors.push(`producer ${record.producer.component} does not own counter ${entry.counter}`);
    if (entry.disposition !== "preserved") errors.push("counter audit is preservation-only");
    const key = `${entry.counter}|${entry.period_utc}`;
    if (counterPeriods.has(key)) errors.push(`duplicate counter audit key ${key}`);
    counterPeriods.add(key);
    const [year, month] = entry.period_utc.split("-").map(Number);
    const periodClose = Date.UTC(year, month, 1);
    if (periodClose > Date.parse(record.tombstone.effective_at)) errors.push(`counter period ${entry.period_utc} is not closed before erasure`);
  }
  return errors;
}

function validateReviewPair(record, errors) {
  const reviewerUnknown = isUnknown(record.review.reviewer_principal_id);
  const reviewedUnknown = isUnknown(record.review.reviewed_at);
  if (reviewerUnknown !== reviewedUnknown) errors.push("review principal and reviewed_at must be known or unknown together");
  if (!reviewedUnknown && Date.parse(record.review.reviewed_at) > Date.parse(record.recorded_at)) errors.push("reviewed_at exceeds recorded_at");
}

function validateSemantics(record) {
  if (record.lifecycle_state === "content-removed-tombstone") return validateTombstone(record);
  const errors = [];
  if (record.task.origin_component !== record.task.source.component) errors.push("task origin_component must equal task.source.component");
  if (Date.parse(record.task.source.accepted_at) < Date.parse(record.task.source.created_at)) errors.push("task source accepted_at precedes created_at");
  if (Date.parse(record.recorded_at) < Date.parse(record.task.source.accepted_at)) errors.push("recorded_at precedes task acceptance");
  if (record.execution) {
    if (Date.parse(record.execution.started_at) < Date.parse(record.task.source.accepted_at)) errors.push("execution started_at precedes task acceptance");
    if (!isUnknown(record.execution.ended_at) && Date.parse(record.execution.ended_at) < Date.parse(record.execution.started_at)) errors.push("execution ended_at precedes started_at");
    if (!isUnknown(record.execution.ended_at) && Date.parse(record.execution.ended_at) > Date.parse(record.recorded_at)) errors.push("execution ended_at exceeds recorded_at");
  }
  validateReviewPair(record, errors);
  validateGovernance(record, errors);
  validateTransport(record, errors);
  for (const namespace of Object.keys(record.extensions)) if (namespace !== record.producer.component) errors.push(`extension namespace ${namespace} is not owned by producer ${record.producer.component}`);
  if (!isUnknown(record.lineage.correction_ref) && !record.artifacts.items.some((item) => item.kind === "correction" && item.ref === record.lineage.correction_ref)) errors.push("correction_ref must bind a correction artifact");
  if (record.exposure?.kind === "observed-event") {
    if (record.exposure.fingerprint_version !== record.task.raw_fingerprint.version) errors.push("observed exposure fingerprint version differs from raw task fingerprint");
    if (Date.parse(record.exposure.first_seen_at) > Date.parse(record.exposure.last_seen_at) || Date.parse(record.exposure.last_seen_at) > Date.parse(record.recorded_at)) errors.push("observed exposure clocks are not ordered");
  }
  if (record.exposure?.kind === "negative-coverage-query") {
    if (canonical(record.exposure.queried_fingerprint) !== canonical(record.task.raw_fingerprint)) errors.push("negative coverage query fingerprint differs from task fingerprint");
    if (canonical([...record.exposure.coverage.lanes].sort()) !== canonical([...lanes].sort())) errors.push("negative coverage query does not cover the exact six lanes");
    const c = record.exposure.coverage;
    if (!(Date.parse(c.from) <= Date.parse(c.relevant_task_at) && Date.parse(c.relevant_task_at) <= Date.parse(c.through) && Date.parse(c.through) <= Date.parse(record.exposure.queried_at) && Date.parse(record.exposure.queried_at) <= Date.parse(record.recorded_at))) errors.push("negative coverage clocks are not ordered");
  }
  if (record.capability) {
    const verifier = record.capability.verifier;
    const calibrated = verifier.kind === "deterministic" || verifier.kind === "human" || (verifier.kind === "calibrated-judge" && !isUnknown(verifier.calibration_evidence_id));
    const qualifiedOutcome = (record.capability.outcome === "pass" && record.capability.admission_basis === "full-pass")
      || (record.capability.outcome === "partial" && record.capability.admission_basis === "policy-qualified-partial");
    if (record.capability.admission_state === "admissible" && (!calibrated || verifier.independence !== "independent" || !qualifiedOutcome)) errors.push("capability admission requires independent calibrated policy-qualified evidence");
    if (record.capability.admission_state === "inadmissible" && record.capability.admission_basis !== "none") errors.push("inadmissible capability evidence must use admission basis none");
    if (record.capability.admission_state === "inadmissible" && record.capability.routing_effect === "admit") errors.push("inadmissible capability evidence cannot admit routing");
    if (verifier.kind === "advisory-judge" && record.capability.routing_effect !== "none-shadow") errors.push("advisory judge cannot affect routing");
    const failure = record.capability.failure_mode;
    if (["pass", "partial"].includes(record.capability.outcome) && failure !== "not-applicable") errors.push("passing or partial capability outcome requires not-applicable failure mode");
    if (["fail", "error", "unverified"].includes(record.capability.outcome) && failure === "not-applicable") errors.push("non-passing capability outcome requires a failure mode");
    if (record.capability.outcome === "unverified" && failure !== "unverified") errors.push("unverified capability outcome requires unverified failure mode");
    if (record.capability.admission_state === "admissible" && record.capability.routing_effect !== "admit") errors.push("admissible capability evidence must use routing effect admit");
  }
  if (record.outcomes) {
    const expectedFailures = {
      completed: ["not-applicable"],
      failed: ["executor-error", "repository-checkout", "publication", "delivery"],
      cancelled: ["cancelled"],
      timeout: ["timeout"],
      "infrastructure-error": ["infrastructure", "gateway-not-admitted", "transport-auth-failed"],
    };
    if (!expectedFailures[record.outcomes.execution].includes(record.outcomes.execution_failure_mode)) errors.push("task execution outcome and failure mode are incoherent");
    if (record.transport?.state === "m5-not-admitted" && !["gateway-not-admitted", "transport-auth-failed", "infrastructure"].includes(record.outcomes.execution_failure_mode)) errors.push("M5 non-admission requires a matching task failure mode");
  }
  if (record.experiment) {
    if (record.experiment.verification_outcome === "pass" && record.experiment.failure_mode !== "not-applicable") errors.push("passing experiment observation requires not-applicable failure mode");
    if (record.experiment.verification_outcome !== "pass" && record.experiment.failure_mode === "not-applicable") errors.push("non-passing experiment observation requires a failure mode");
  }
  if (record.quality_receipt) {
    const receipt = record.quality_receipt;
    if (receipt.task_id !== record.task.instance_id || receipt.reviewer.principal !== record.review.reviewer_principal_id || receipt.rated_at !== record.review.reviewed_at) errors.push("quality receipt native binding/reviewer does not match envelope");
    if (Date.parse(receipt.rated_at) > Date.parse(record.recorded_at)) errors.push("quality receipt rated_at exceeds recorded_at");
  }
  if (record.experiment_product_rating) {
    const rating = record.experiment_product_rating;
    if (rating.reviewer.principal !== record.review.reviewer_principal_id || rating.rated_at !== record.review.reviewed_at) errors.push("experiment rating reviewer does not match envelope");
    if (Date.parse(rating.rated_at) > Date.parse(record.recorded_at)) errors.push("experiment rating rated_at exceeds recorded_at");
  }
  return errors;
}

function joinedIdentityErrors(records) {
  const errors = [];
  const groups = new Map();
  for (const record of records) {
    if (record.lifecycle_state !== "active" || record.task.origin_component !== "hugin" || !record.execution) continue;
    const key = `${record.task.instance_id}|${record.execution.attempt_id}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(record);
  }
  for (const group of groups.values()) {
    for (let index = 1; index < group.length; index += 1) {
      for (const field of ["task", "execution"]) if (canonical(group[0][field]) !== canonical(group[index][field])) errors.push(`joined identity mismatch at ${field}`);
      const sharedTransport = (record) => ({ state: record.transport.state, hugin_request_stamp: record.transport.hugin_request_stamp, gateway_echo: record.transport.gateway_echo });
      if (canonical(sharedTransport(group[0])) !== canonical(sharedTransport(group[index]))) errors.push("joined identity mismatch at transport shared stamp/echo");
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
  const activeIds = new Set(records.filter((record) => record.lifecycle_state === "active").map((record) => `${record.producer.component}|${record.record_id}`));
  const tombstonedIds = new Set();
  for (const record of records) {
    if (record.lifecycle_state === "content-removed-tombstone") {
      const key = `${record.producer.component}|${record.tombstone.superseded_record_id}`;
      if (activeIds.has(key)) errors.push(`tombstone supersedes content-bearing record still present: ${record.tombstone.superseded_record_id}`);
      if (tombstonedIds.has(key)) errors.push(`duplicate producer-scoped tombstone for ${record.tombstone.superseded_record_id}`);
      tombstonedIds.add(key);
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

  const attemptsByIdempotency = new Map();
  for (const record of records) {
    const stamp = record.transport?.hugin_request_stamp;
    if (!stamp || isUnknown(stamp)) continue;
    const key = stamp.idempotency_key;
    const identity = canonical({ task: stamp.task_instance_id, attempt: stamp.attempt_id, request: stamp.request_id, client: stamp.client_id, ordinal: stamp.retry.model_execution_ordinal });
    if (attemptsByIdempotency.has(key) && attemptsByIdempotency.get(key) !== identity) errors.push("idempotency key was reused for a different task/attempt/model execution");
    else attemptsByIdempotency.set(key, identity);
  }
  for (const record of records) {
    if (record.lifecycle_state !== "active" || record.record_kind !== "quality-receipt") continue;
    const receipt = record.quality_receipt;
    const taskExecutions = records.filter((candidate) => candidate.lifecycle_state === "active" && candidate.execution && candidate.task.instance_id === receipt.task_id);
    if (taskExecutions.length > 0 && !taskExecutions.some((candidate) => candidate.execution.attempt_id === receipt.attempt_id && canonical(candidate.task) === canonical(record.task))) errors.push("quality receipt does not bind a known task execution attempt");
  }
  for (const record of records) {
    if (record.lifecycle_state !== "active" || record.record_kind !== "experiment-product-rating") continue;
    const rating = record.experiment_product_rating;
    const observation = records.find((candidate) => candidate.lifecycle_state === "active" && candidate.record_kind === "experiment-observation" && candidate.record_id === rating.observation_record_id);
    if (observation && (rating.experiment_id !== observation.experiment.experiment_id || rating.run_id !== observation.experiment.run_id || canonical(rating.configuration_fingerprint) !== canonical(observation.experiment.configuration_fingerprint) || canonical(record.task) !== canonical(observation.task))) {
      errors.push("experiment product rating does not bind referenced observation");
    }
    const sameRun = records.find((candidate) => candidate.lifecycle_state === "active" && candidate.record_kind === "experiment-observation" && candidate.experiment.experiment_id === rating.experiment_id && candidate.experiment.run_id === rating.run_id);
    if (!observation && sameRun) errors.push("experiment product rating does not bind referenced observation");
  }
  return errors;
}

function summarizeImmutable(records, section, resultFields, bindingFields) {
  const groups = new Map();
  for (const record of records) {
    const value = record[section];
    const key = canonical({ binding: bindingFields.map((field) => value[field]), rubric: value.rubric });
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(value);
  }
  return [...groups.values()].map((values) => {
    const declared = values.map((value) => Object.fromEntries(resultFields.map((field) => [field, value[field]])));
    return {
      result: new Set(declared.map(canonical)).size === 1 ? declared[0] : "conflicted",
      ids: values.map((value) => value.receipt_id ?? value.rating_id).sort(),
    };
  });
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
  "#/$defs/qualityReceiptRecord",
  "#/$defs/experimentProductRatingRecord",
]);
assert.deepEqual(Object.keys(schema["x-grimnir-conflict-keys"]), ["record", "task-outcome", "inference-exposure", "capability-evidence", "experiment-observation", "quality-receipt", "experiment-product-rating"]);
const ownerMap = schema["x-grimnir-field-owners"];
for (const requiredOwnerGroup of ["/tombstone/**", "/transport/hugin_request_stamp", "/transport/gateway_echo/echoed_request", "/transport/gateway_echo/gateway_request_id,/transport/gateway_echo/admission_id,/transport/gateway_echo/admitted_at,/transport/gateway_echo/authenticated_principal_id,/transport/gateway_echo/authentication,/transport/gateway_echo/principal_binding_digest,/transport/gateway_echo/capabilities", "/exposure/**", "/capability/**", "/experiment/**", "/quality_receipt/**", "/experiment_product_rating/**", "/extensions/{producer.component}/**"]) {
  assert.equal(typeof ownerMap[requiredOwnerGroup], "string", `machine ownership map must cover ${requiredOwnerGroup}`);
}

const positiveErrors = validateDataset(positive);
assert.deepEqual(positiveErrors, [], `positive fixtures must validate:\n${positiveErrors.join("\n")}`);
const positiveDerived = positiveDerivedDefinitions.map((definition) => {
  const record = structuredClone(positive[definition.from_positive]);
  for (const mutation of definition.mutations) mutate(record, mutation);
  return { name: definition.name, evaluationClock: definition.evaluation_clock, record };
});
for (const fixture of positiveDerived) assert.deepEqual(validateDataset([fixture.record]), [], `${fixture.name}: derived positive fixture must validate`);
const nonM5Fixture = positiveDerived.find((fixture) => fixture.record.transport.state === "not-m5");
const nonAdmittedFixture = positiveDerived.find((fixture) => fixture.record.transport.state === "m5-not-admitted");
assert.equal(provenanceAndGovernanceEligibleAt(nonM5Fixture.record, nonM5Fixture.evaluationClock.eligible_at), true, "complete non-M5 provenance can pass the provenance and governance candidate gates");
assert.equal(governanceEligibleAt(nonAdmittedFixture.record, nonAdmittedFixture.evaluationClock.eligible_at), true, "governance eligibility is independent of missing execution provenance");
assert.equal(provenanceAndGovernanceEligibleAt(nonAdmittedFixture.record, nonAdmittedFixture.evaluationClock.eligible_at), false, "unknown non-admitted provenance fails the provenance candidate gate");
const nestedServingUnknown = structuredClone(positive[0]);
nestedServingUnknown.execution.serving.model.artifact_manifest_digest = { value: null, unknown_reason: "not-observed" };
assert.equal(provenanceAndGovernanceEligibleAt(nestedServingUnknown, nonM5Fixture.evaluationClock.eligible_at), false, "nested serving provenance must be complete, not merely wrapped in a known object");
assert.equal(governanceEligibleAt(positive[0], nonM5Fixture.evaluationClock.post_expiry_at), false, "read-time expiry is checked against an explicit fixture clock");
const noExpiryPolicy = structuredClone(positive[0]);
for (const policy of noExpiryPolicy.governance.policies) policy.retention.expires_at = { value: null, unknown_reason: "not-applicable" };
noExpiryPolicy.governance.effective.expires_at = { value: null, unknown_reason: "not-applicable" };
assert.deepEqual(validateDataset([noExpiryPolicy]), [], "explicit no-expiry policy remains evaluation eligible");
const legacyUnknownPrincipal = structuredClone(positive[5]);
legacyUnknownPrincipal.task.source.principal = { value: null, unknown_reason: "legacy" };
assert.deepEqual(validateDataset([legacyUnknownPrincipal]), [], "qualified legacy source principal is policy-unavailable and evaluation-ineligible, not fabricated");
assert.deepEqual(new Set(positive.map((record) => record.record_kind)), new Set(["task-outcome", "inference-exposure", "capability-evidence", "experiment-observation", "quality-receipt", "experiment-product-rating"]));
assert.equal(positive.some((record) => record.task.origin_component === "gille-inference"), true, "positive fixtures must cover direct gateway origin");
const joinedOutcome = positive.find((record) => record.record_kind === "task-outcome");
const joinedCapability = positive.find((record) => record.record_kind === "capability-evidence");
const joinedExposure = positive.find((record) => record.record_kind === "inference-exposure" && record.task.origin_component === "hugin");
assert.equal(joinedCapability.task.instance_id, joinedOutcome.task.instance_id, "positive fixtures must contain a joined Hugin task");
assert.equal(joinedCapability.execution.attempt_id, joinedOutcome.execution.attempt_id, "joined fixtures must bind the same attempt");
const policyQualifiedPartial = structuredClone(joinedCapability);
policyQualifiedPartial.record_id = "opaque:16161616-1616-4616-8616-161616161616";
policyQualifiedPartial.capability.evidence_id = "evidence-policy-qualified-partial";
policyQualifiedPartial.capability.outcome = "partial";
policyQualifiedPartial.capability.admission_basis = "policy-qualified-partial";
assert.deepEqual(validateDataset([policyQualifiedPartial]), [], "independent calibrated partial evidence may be admitted only through explicit policy basis");
assert.equal(joinedExposure.task.instance_id, joinedOutcome.task.instance_id, "positive fixtures must contain gateway exposure for the joined Hugin task");
assert.equal(joinedExposure.execution.attempt_id, joinedOutcome.execution.attempt_id, "joined exposure must bind the same attempt");
for (const record of [joinedCapability, joinedExposure]) {
  assert.deepEqual(record.task, joinedOutcome.task, "joined task projection must match exactly");
  assert.deepEqual(record.execution, joinedOutcome.execution, "joined execution projection must match exactly");
  assert.equal(record.transport.state, joinedOutcome.transport.state, "joined transport state must match");
  assert.deepEqual(record.transport.hugin_request_stamp, joinedOutcome.transport.hugin_request_stamp, "joined request stamp must match exactly");
  assert.deepEqual(record.transport.gateway_echo, joinedOutcome.transport.gateway_echo, "joined gateway echo must match exactly");
}
assert.notEqual(joinedExposure.transport.record_delivery_attempt, joinedOutcome.transport.record_delivery_attempt, "producer-owned delivery counters may differ across an otherwise exact join");

const quality = positive.find((record) => record.record_kind === "quality-receipt");
const secondQuality = structuredClone(quality);
secondQuality.record_id = "opaque:12121212-1212-4212-8212-121212121212";
secondQuality.quality_receipt.receipt_id = "qr-121212121212121212121212";
secondQuality.quality_receipt.reviewer.principal = "principal:reviewer-3";
secondQuality.review.reviewer_principal_id = "principal:reviewer-3";
assert.deepEqual(validateDataset([quality, secondQuality]), [], "multiple immutable quality receipts for one task/attempt are permitted");
assert.deepEqual(summarizeImmutable([quality, secondQuality], "quality_receipt", ["rating", "disposition"], ["task_id", "attempt_id", "binding"])[0].result, { rating: "pass", disposition: "accepted_unchanged" }, "unanimous receipts summarize full rating/disposition without newest-wins");
const conflictingQuality = structuredClone(secondQuality);
conflictingQuality.quality_receipt.disposition = "minor_edit";
assert.equal(summarizeImmutable([quality, conflictingQuality], "quality_receipt", ["rating", "disposition"], ["task_id", "attempt_id", "binding"])[0].result, "conflicted", "any rating/disposition disagreement summarizes as conflicted");
const experimentRating = positive.find((record) => record.record_kind === "experiment-product-rating");
const secondRating = structuredClone(experimentRating);
secondRating.record_id = "opaque:13131313-1313-4313-8313-131313131313";
secondRating.experiment_product_rating.rating_id = "epr-131313131313131313131313";
secondRating.experiment_product_rating.reviewer.principal = "principal:reviewer-4";
secondRating.review.reviewer_principal_id = "principal:reviewer-4";
assert.deepEqual(validateDataset([experimentRating, secondRating]), [], "multiple immutable experiment ratings for one observation are permitted");
assert.deepEqual(summarizeImmutable([experimentRating, secondRating], "experiment_product_rating", ["product_outcome"], ["observation_record_id", "experiment_id", "run_id", "configuration_fingerprint"])[0].result, { product_outcome: "accepted-unchanged" }, "unanimous experiment ratings summarize without newest-wins");
const conflictingRating = structuredClone(secondRating);
conflictingRating.experiment_product_rating.product_outcome = "discarded";
assert.equal(summarizeImmutable([experimentRating, conflictingRating], "experiment_product_rating", ["product_outcome"], ["observation_record_id", "experiment_id", "run_id", "configuration_fingerprint"])[0].result, "conflicted", "disagreeing experiment ratings summarize as conflicted");

const fixtureDigests = [
  [positive[0].task.raw_fingerprint.digest, "Summarize quarterly release notes"],
  [positive[1].task.raw_fingerprint.digest, "Hello M5"],
  [positive[5].task.raw_fingerprint.digest, "Fresh task"],
  [positive[0].execution.prompt_identity.hugin_envelope.digest, "hugin-envelope:task-001:v1"],
  [positive[0].execution.prompt_identity.gateway_canonical_envelope.digest, "gateway-envelope:task-001:v1"],
  [positive[0].execution.prompt_identity.runtime_chat_template_render.digest, "runtime-render:task-001:v1"],
  [positive[1].execution.prompt_identity.gateway_canonical_envelope.digest, "gateway-envelope:direct:v1"],
  [positive[1].execution.prompt_identity.runtime_chat_template_render.digest, "runtime-render:direct:v1"],
  [positive[0].execution.serving.model.artifact_manifest_digest.digest, "artifact-manifest:mellum:v1"],
  [positive[0].execution.serving.model.effective_config_digest.digest, "effective-runtime-config:mellum:v1"],
  [positive[0].execution.serving.sampling_digest.digest, "effective-sampling:mellum:v1"],
  [positive[0].execution.origin_config.prompt.config_digest.digest, "hugin-prompt:v4"],
  [positive[0].execution.origin_config.harness.config_digest.digest, "hugin-harness:v3"],
  [positive[0].execution.origin_config.tool_policy.config_digest.digest, "hugin-tools:v2"],
  [positive[0].execution.effective_gateway_config.harness.config_digest.digest, "gateway-harness:v7"],
  [positive[0].execution.effective_gateway_config.tool_policy.config_digest.digest, "gateway-tools:v5"],
  [positive[1].execution.origin_config.prompt.config_digest.digest, "direct-prompt:v1"],
  [positive[1].execution.origin_config.harness.config_digest.digest, "direct-harness:v1"],
  [positive[1].execution.origin_config.tool_policy.config_digest.digest, "direct-tools:v1"],
  [positive[2].capability.policy_epoch.config_digest.digest, "capability-policy:2026-07-19"],
  [positive[3].experiment.configuration_fingerprint.digest, "experiment-config:exp-001:run-001"],
  [positive[6].quality_receipt.binding.task_document_sha256, "quality-task-document"],
  [positive[6].quality_receipt.binding.structured_result_sha256, "quality-structured-result"],
  [positive[6].quality_receipt.rating_reason_sha256, "quality-rating-reason"],
  [positive[6].quality_receipt.rubric.config_digest.digest, "quality-rubric"],
  [positive[7].experiment_product_rating.rating_reason_sha256, "experiment-rating-reason"],
  [positive[7].experiment_product_rating.rubric.config_digest.digest, "experiment-rubric"],
];
for (const [actual, source] of fixtureDigests) assert.equal(actual, digest(source), `fixture digest must be computed from ${source}`);

const erasedErrors = validateDataset([positiveErased]);
assert.deepEqual(erasedErrors, [], `erased tombstone fixture must validate:\n${erasedErrors.join("\n")}`);
assert.deepEqual(Object.keys(positiveErased).sort(), ["contract_version", "lifecycle_state", "producer", "record_id", "record_kind", "recorded_at", "schema_revision", "tombstone"].sort(), "tombstone must expose only its reduced envelope");
const noCounterTombstone = structuredClone(positiveErased);
noCounterTombstone.tombstone.counter_audit = [];
assert.deepEqual(validateDataset([noCounterTombstone]), [], "tombstone may omit counter adjustments rather than fabricate them");

for (const testCase of negative) {
  const firstSource = testCase.from_erased ? positiveErased
    : testCase.from_positive_derived !== undefined ? positiveDerived[testCase.from_positive_derived].record
      : positive[testCase.from_positive];
  const first = structuredClone(firstSource);
  for (const mutation of testCase.mutations ?? []) mutate(first, mutation);
  const records = [first];
  if (testCase.second_record_mutations) {
    const secondSource = testCase.second_from_erased ? positiveErased
      : testCase.second_from_positive_derived !== undefined ? positiveDerived[testCase.second_from_positive_derived].record
        : positive[testCase.second_from_positive ?? testCase.from_positive];
    const second = structuredClone(secondSource);
    for (const mutation of testCase.second_record_mutations) mutate(second, mutation);
    records.push(second);
  }
  const errors = validateDataset(records);
  assert.ok(errors.length > 0, `${testCase.name}: negative fixture unexpectedly passed`);
  assert.ok(errors.join("\n").includes(testCase.expected_error), `${testCase.name}: expected ${JSON.stringify(testCase.expected_error)} in:\n${errors.join("\n")}`);
}

console.log(`LearningTaskContract validation passed: ${positive.length + positiveDerived.length + 1} fixture positives, 2 immutable multi-review cases, and ${negative.length} adversarial cases.`);
