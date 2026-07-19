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
const sourceDocumentList = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/source-documents.json"), "utf8"));
const sourceDocumentNegative = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/source-document-negative.json"), "utf8"));
const jcsConformanceVectors = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/jcs-conformance-vectors.json"), "utf8"));
const rawFingerprintVectors = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/raw-fingerprint-vectors.json"), "utf8"));
const validationContext = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/learning-task-contract/validation-context.json"), "utf8"));
const sourceDocuments = new Map(sourceDocumentList.map((source) => [source.source_ref, source]));
const trustedEvidence = new Map(validationContext.trusted_evidence.map((evidence) => [evidence.evidence_id, evidence]));

function compareUtf16CodeUnits(left, right) {
  return left === right ? 0 : left < right ? -1 : 1;
}

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort(compareUtf16CodeUnits).map((key) => {
      assertValidUnicodeScalarString(key);
      return `${JSON.stringify(key)}:${canonical(value[key])}`;
    }).join(",")}}`;
  }
  if (typeof value === "string") assertValidUnicodeScalarString(value);
  if (typeof value === "number" && !Number.isFinite(value)) throw new Error("JCS rejects non-finite numbers");
  if (!["string", "number", "boolean"].includes(typeof value) && value !== null) throw new Error(`JCS rejects non-JSON value ${typeof value}`);
  return JSON.stringify(value);
}

function assertValidUnicodeScalarString(value) {
  for (let index = 0; index < value.length; index += 1) {
    const unit = value.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) throw new Error("JCS rejects lone high surrogate");
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) throw new Error("JCS rejects lone low surrogate");
  }
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

function isExactUtcDateTime(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?Z$/.exec(value);
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
    if (node.format === "date-time" && !isExactUtcDateTime(value)) {
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
    if (node.items !== undefined) value.forEach((item, index) => errors.push(...validateNode(node.items, item, `${at}[${index}]`)));
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

const supportedSchemaKeywords = new Set([
  "$ref", "allOf", "oneOf", "const", "enum", "type", "minLength", "pattern", "format", "minimum",
  "minItems", "maxItems", "uniqueItems", "items", "required", "properties", "additionalProperties",
  "description", "title", "$schema", "$id", "$defs",
]);
function assertSupportedSchemaKeywords(node, at = "$") {
  if (!node || typeof node !== "object" || Array.isArray(node)) return;
  for (const key of Object.keys(node)) {
    assert.ok(supportedSchemaKeywords.has(key) || key.startsWith("x-"), `unsupported JSON Schema keyword ${key} at ${at}; Draft 2020-12 CI must remain authoritative`);
  }
  const plainMap = (value) => value && typeof value === "object" && !Array.isArray(value);
  const isSchemaNode = (value) => typeof value === "boolean" || plainMap(value);
  for (const key of ["$ref", "$schema", "$id", "title", "description"]) if (node[key] !== undefined) assert.equal(typeof node[key], "string", `${key} must be a string at ${at}`);
  if (node.$ref !== undefined) {
    assert.match(node.$ref, /^#\//, `only local #/ schema refs are supported at ${at}`);
    let target = schema;
    for (const rawToken of node.$ref.slice(2).split("/")) {
      const token = rawToken.replaceAll("~1", "/").replaceAll("~0", "~");
      assert.ok(plainMap(target) && Object.hasOwn(target, token), `unresolved local schema ref ${node.$ref} at ${at}`);
      target = target[token];
    }
    assert.ok(isSchemaNode(target), `local schema ref ${node.$ref} does not resolve to a schema node at ${at}`);
  }
  if (node.type !== undefined) assert.ok(typeof node.type === "string" && ["object", "array", "string", "integer", "boolean", "null"].includes(node.type), `unsupported schema type or type array at ${at}; custom validation must not diverge from Draft 2020-12`);
  if (node.enum !== undefined) assert.ok(Array.isArray(node.enum) && node.enum.length > 0, `enum must be a non-empty array at ${at}`);
  for (const key of ["minLength", "minItems", "maxItems"]) if (node[key] !== undefined) assert.ok(Number.isInteger(node[key]) && node[key] >= 0, `${key} must be a non-negative integer at ${at}`);
  if (node.minimum !== undefined) assert.ok(typeof node.minimum === "number" && Number.isFinite(node.minimum), `minimum must be a finite number at ${at}`);
  if (node.pattern !== undefined) {
    assert.equal(typeof node.pattern, "string", `pattern must be a string at ${at}`);
    assert.doesNotThrow(() => new RegExp(node.pattern), `pattern must compile at ${at}`);
  }
  if (node.uniqueItems !== undefined) assert.equal(typeof node.uniqueItems, "boolean", `uniqueItems must be boolean at ${at}`);
  if (node.required !== undefined) assert.ok(Array.isArray(node.required) && node.required.every((value) => typeof value === "string") && new Set(node.required).size === node.required.length, `required must be an array of unique strings at ${at}`);
  for (const key of ["properties", "$defs"]) if (node[key] !== undefined) assert.ok(plainMap(node[key]) && Object.values(node[key]).every(isSchemaNode), `${key} must be a plain map of supported schema objects/booleans at ${at}`);
  if (node.format !== undefined) assert.equal(node.format, "date-time", `unsupported schema format ${node.format} at ${at}`);
  if (node.additionalProperties !== undefined) assert.equal(typeof node.additionalProperties, "boolean", `schema-valued additionalProperties is unsupported at ${at}`);
  const executableSiblingKeys = (excluded) => Object.keys(node).filter((key) => !excluded.has(key) && !["title", "description", "$schema", "$id", "$defs"].includes(key) && !key.startsWith("x-"));
  if (node.$ref) assert.deepEqual(executableSiblingKeys(new Set(["$ref"])), [], `validation siblings beside $ref are unsupported at ${at}`);
  if (node.oneOf) assert.deepEqual(executableSiblingKeys(new Set(["oneOf"])), [], `validation siblings beside oneOf are unsupported at ${at}`);
  for (const key of ["allOf", "oneOf"]) if (node[key] !== undefined) {
    assert.ok(Array.isArray(node[key]) && node[key].length > 0 && node[key].every(isSchemaNode), `${key} must be a non-empty array of supported schema objects/booleans at ${at}`);
    for (const [index, child] of node[key].entries()) assertSupportedSchemaKeywords(child, `${at}.${key}[${index}]`);
  }
  if (node.items !== undefined) {
    assert.ok(isSchemaNode(node.items), `items must be a supported schema object/boolean at ${at}`);
    assertSupportedSchemaKeywords(node.items, `${at}.items`);
  }
  for (const [key, child] of Object.entries(node.properties ?? {})) assertSupportedSchemaKeywords(child, `${at}.properties.${key}`);
  for (const [key, child] of Object.entries(node.$defs ?? {})) assertSupportedSchemaKeywords(child, `${at}.$defs.${key}`);
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

function digestCanonical(value) {
  return digest(canonical(value));
}

function huginStable(value) {
  if (Array.isArray(value)) return `[${value.map(huginStable).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.entries(value).filter(([, child]) => child !== undefined).sort(([left], [right]) => left.localeCompare(right)).map(([key, child]) => `${JSON.stringify(key)}:${huginStable(child)}`).join(",")}}`;
  return JSON.stringify(value);
}

function huginReceiptId(input) {
  return `qr-${digest(huginStable(input)).slice(0, 24)}`;
}

function normalizedNativeBinding(binding) {
  const repository = binding.repository;
  return {
    taskDocumentSha256: binding.task_document_sha256,
    structuredResultSha256: binding.structured_result_sha256,
    repository: {
      state: repository.state,
      ...(typeof repository.base_branch === "string" ? { baseBranch: repository.base_branch } : {}),
      ...(typeof repository.base_commit === "string" ? { baseCommit: repository.base_commit } : {}),
      ...(typeof repository.head_commit === "string" ? { headCommit: repository.head_commit } : {}),
      ...(repository.diff_sha256?.digest ? { diffSha256: repository.diff_sha256.digest } : {}),
    },
  };
}

function validateTrustedEvidence(ref, expectedKind, errors, expectedPayload, label = expectedKind) {
  if (!ref || isUnknown(ref)) {
    errors.push(`${label} lacks trusted validation evidence`);
    return false;
  }
  if (ref.validation_context_id !== validationContext.context_id) {
    errors.push(`${label} names an untrusted validation context`);
    return false;
  }
  const evidence = trustedEvidence.get(ref.evidence_id);
  if (!evidence || evidence.kind !== expectedKind || evidence.issuer !== ref.issuer || canonical(evidence.payload_digest) !== canonical(ref.payload_digest)) {
    errors.push(`${label} is absent from the trusted validation context`);
    return false;
  }
  if (evidence.payload_digest.version !== "trusted-evidence-payload-jcs-v1" || evidence.payload_digest.digest !== digestCanonical(evidence.payload)) {
    errors.push(`${label} trusted payload digest is invalid`);
    return false;
  }
  if (expectedPayload !== undefined && canonical(evidence.payload) !== canonical(expectedPayload)) {
    errors.push(`${label} trusted payload does not bind the claimed facts`);
    return false;
  }
  return true;
}

function sourceDocumentClaims(value, found = []) {
  if (Array.isArray(value)) for (const item of value) sourceDocumentClaims(item, found);
  else if (value && typeof value === "object") {
    if (typeof value.source_ref === "string" && typeof value.source_type === "string" && typeof value.digest === "string") found.push(value);
    for (const child of Object.values(value)) sourceDocumentClaims(child, found);
  }
  return found;
}

const sourceDocumentRequiredKeys = {
  "raw-input": ["schema_version", "fixture_only", "origin_component", "input_role", "encoding", "text"],
  "prompt-stage": ["schema_version", "stage", "fixture_only", "encoding", "input_source_refs", "text", "byte_length", "sha256", "task_binding"],
  "origin-prompt-config": ["schema_version", "component", "config_kind", "id", "version", "settings"],
  "origin-harness-config": ["schema_version", "component", "config_kind", "id", "version", "settings"],
  "origin-tool-policy-config": ["schema_version", "component", "config_kind", "id", "version", "settings"],
  "gateway-harness-config": ["schema_version", "component", "config_kind", "id", "version", "settings"],
  "gateway-tool-policy-config": ["schema_version", "component", "config_kind", "id", "version", "settings"],
  "capability-policy-config": ["schema_version", "component", "config_kind", "id", "version", "settings"],
  "experiment-config": ["schema_version", "experiment_id", "run_id", "arms", "holdout", "metric"],
  "rubric-config": ["schema_version", "id", "version"],
  "quality-receipt-native-v1": ["schemaVersion", "receiptId", "taskId", "rating", "ratingReason", "verificationOutcome", "ratedAt", "reviewer", "bindingAttestation", "binding"],
  "quality-receipt-native-v2": ["schemaVersion", "receiptId", "taskId", "attemptId", "rating", "ratingReason", "verificationOutcome", "ratedAt", "reviewer", "rubric", "bindingAttestation", "binding", "correctsReceiptId"],
  "artifact-manifest": ["schema_version", "model_id", "files", "quantization"],
  "effective-runtime-config": ["schema_version", "runtime_id", "provider_id", "model_id", "context_tokens", "backend", "chat_template"],
  "effective-sampling-post-default-post-clamp": ["schema_version", "model_id", "requested", "defaults_applied", "clamps_applied", "final"],
  "governance-policy-manifest": ["schema_version", "contract", "manifest", "record_binding", "policies"],
};

function validateSourceDocumentDigest(claim, errors) {
  const source = sourceDocuments.get(claim.source_ref);
  if (!source) {
    errors.push(`missing immutable source document ${claim.source_ref}`);
    return;
  }
  if (source.source_type !== claim.source_type || source.source_version !== claim.source_version) errors.push(`source document identity mismatch for ${claim.source_ref}`);
  if (claim.digest !== digestCanonical(source.document)) errors.push(`source document digest mismatch for ${claim.source_ref}`);
  const requiredKeys = sourceDocumentRequiredKeys[source.source_type];
  if (!requiredKeys || source.document === null || typeof source.document !== "object" || Array.isArray(source.document) || requiredKeys.some((key) => !Object.hasOwn(source.document, key))) errors.push(`source document ${claim.source_ref} does not match typed ${source.source_type} shape`);
  if (source.source_type === "raw-input") {
    if (source.document.encoding !== "utf-8" || source.document.fixture_only !== true) errors.push(`raw input source ${claim.source_ref} is not exact fixture-only UTF-8 text`);
    const expectedRole = source.document.origin_component === "hugin" ? "hugin-logical-prompt" : "direct-user-turn";
    if (source.document.input_role !== expectedRole) errors.push(`raw input source ${claim.source_ref} has the wrong pre-orchestration role`);
  }
  if (source.source_type === "prompt-stage") {
    const bytes = Buffer.from(source.document.text ?? "", "utf8");
    if (source.document.encoding !== "utf-8" || source.document.fixture_only !== true || source.document.byte_length !== bytes.length || source.document.sha256 !== digest(source.document.text ?? "") || !Array.isArray(source.document.input_source_refs) || source.document.input_source_refs.length === 0) errors.push(`prompt source ${claim.source_ref} does not bind exact ordered UTF-8 bytes and immutable inputs`);
  }
  if (source.source_type === "effective-sampling-post-default-post-clamp") {
    const final = source.document.final;
    const exactFields = ["temperature", "top_p", "top_k", "min_p", "max_tokens", "n"];
    if (!final || canonical(Object.keys(final).sort()) !== canonical(exactFields.sort())) errors.push(`sampling source ${claim.source_ref} lacks exact post-default/post-clamp fields`);
    if (source.document.fixture_only !== true) errors.push(`sampling source ${claim.source_ref} must not masquerade as deployed serving truth`);
  }
}

function validateSourceRole(claim, expectedType, errors, label, expectedStage) {
  if (!claim || isUnknown(claim)) return;
  if (claim.source_type !== expectedType) errors.push(`${label} must bind a typed ${expectedType} source document`);
  const source = sourceDocuments.get(claim.source_ref);
  if (expectedStage && source?.document?.stage !== expectedStage) errors.push(`${label} source document must identify stage ${expectedStage}`);
}

function sourceDocument(claim) {
  return claim && !isUnknown(claim) ? sourceDocuments.get(claim.source_ref)?.document : undefined;
}

function validateConfigIdentity(identity, expectedType, expectedComponent, expectedKind, errors, label) {
  validateSourceRole(identity.config_digest, expectedType, errors, label);
  const document = sourceDocument(identity.config_digest);
  if (!document || document.component !== expectedComponent || document.config_kind !== expectedKind || document.id !== identity.id || document.version !== identity.version) errors.push(`${label} source document identity does not match component/kind/id/version wrapper`);
}

function expectedPromptInputs(record, stage) {
  const execution = record.execution;
  const origin = [record.task.raw_input.source_ref, execution.origin_config.prompt.config_digest.source_ref, execution.origin_config.harness.config_digest.source_ref, execution.origin_config.tool_policy.config_digest.source_ref];
  if (stage === "hugin-envelope") return origin;
  if (stage === "gateway-canonical-envelope") {
    const first = record.task.origin_component === "hugin" ? [execution.prompt_identity.hugin_envelope.source_ref] : origin;
    if (isUnknown(execution.effective_gateway_config)) return first;
    return [...first, execution.effective_gateway_config.harness.config_digest.source_ref, execution.effective_gateway_config.tool_policy.config_digest.source_ref];
  }
  const prior = !isUnknown(execution.prompt_identity.gateway_canonical_envelope) ? execution.prompt_identity.gateway_canonical_envelope.source_ref : execution.prompt_identity.hugin_envelope.source_ref;
  if (!execution.serving?.model) return sourceDocument(execution.prompt_identity.runtime_chat_template_render)?.input_source_refs ?? [];
  return [prior, execution.serving.model.artifact_manifest_digest.source_ref, execution.serving.model.effective_config_digest.source_ref, execution.serving.sampling_digest.source_ref];
}

function validatePromptSource(record, claim, stage, errors, label) {
  validateSourceRole(claim, "prompt-stage", errors, label, stage);
  if (!claim || isUnknown(claim)) return;
  const document = sourceDocument(claim);
  const inputs = expectedPromptInputs(record, stage);
  const rawText = sourceDocument(record.task.raw_input)?.text;
  const recomposed = `fixture-only stage:${stage}\ntask:${record.task.instance_id}\ninputs:${inputs.join(",")}\nraw:${rawText}`;
  if (!document || document.task_binding !== record.task.instance_id || canonical(document.input_source_refs) !== canonical(inputs) || document.text !== recomposed) errors.push(`${label} does not mechanically bind and recompose the exact raw/config/stage source identities and bytes`);
}

function validateReproducibilityRoles(record, errors) {
  const execution = record.execution;
  validateSourceRole(record.task?.raw_input, "raw-input", errors, "raw input");
  if (execution) {
    validatePromptSource(record, execution.prompt_identity.hugin_envelope, "hugin-envelope", errors, "Hugin envelope");
    validatePromptSource(record, execution.prompt_identity.gateway_canonical_envelope, "gateway-canonical-envelope", errors, "gateway canonical envelope");
    validatePromptSource(record, execution.prompt_identity.runtime_chat_template_render, "runtime-chat-template-render", errors, "runtime chat-template render");
    validateConfigIdentity(execution.origin_config.prompt, "origin-prompt-config", record.task.origin_component, "prompt", errors, "origin prompt config");
    validateConfigIdentity(execution.origin_config.harness, "origin-harness-config", record.task.origin_component, "harness", errors, "origin harness config");
    validateConfigIdentity(execution.origin_config.tool_policy, "origin-tool-policy-config", record.task.origin_component, "tool-policy", errors, "origin tool-policy config");
    if (!isUnknown(execution.effective_gateway_config)) {
      validateConfigIdentity(execution.effective_gateway_config.harness, "gateway-harness-config", "gille-inference", "gateway-harness", errors, "gateway harness config");
      validateConfigIdentity(execution.effective_gateway_config.tool_policy, "gateway-tool-policy-config", "gille-inference", "gateway-tool-policy", errors, "gateway tool-policy config");
    }
    if (!isUnknown(execution.serving)) {
      validateSourceRole(execution.serving.model.artifact_manifest_digest, "artifact-manifest", errors, "model artifact manifest");
      validateSourceRole(execution.serving.model.effective_config_digest, "effective-runtime-config", errors, "effective runtime config");
      validateSourceRole(execution.serving.sampling_digest, "effective-sampling-post-default-post-clamp", errors, "effective sampling config");
      const artifact = sourceDocument(execution.serving.model.artifact_manifest_digest);
      const runtime = sourceDocument(execution.serving.model.effective_config_digest);
      const sampling = sourceDocument(execution.serving.sampling_digest);
      if (!artifact || !runtime || !sampling || artifact.model_id !== execution.serving.model.id || runtime.model_id !== execution.serving.model.id || sampling.model_id !== execution.serving.model.id || runtime.runtime_id !== execution.serving.runtime_id || runtime.provider_id !== execution.serving.provider_id) errors.push("serving wrappers do not match artifact/runtime/sampling source document identities");
    }
  }
  if (record.capability) validateConfigIdentity(record.capability.policy_epoch, "capability-policy-config", "gille-inference", "capability-policy", errors, "capability policy epoch");
  validateSourceRole(record.experiment?.configuration_fingerprint, "experiment-config", errors, "experiment configuration");
  validateSourceRole(record.quality_receipt?.rubric.config_digest, "rubric-config", errors, "quality rubric");
  validateSourceRole(record.experiment_product_rating?.configuration_fingerprint, "experiment-config", errors, "experiment rating configuration");
  validateSourceRole(record.experiment_product_rating?.rubric.config_digest, "rubric-config", errors, "experiment rating rubric");
  if (record.governance?.capture_state === "complete") validateSourceRole(record.governance.policy_manifest.digest, "governance-policy-manifest", errors, "governance policy manifest");
  if (record.experiment) {
    const document = sourceDocument(record.experiment.configuration_fingerprint);
    if (!document || document.experiment_id !== record.experiment.experiment_id || document.run_id !== record.experiment.run_id) errors.push("experiment source document does not match experiment/run wrapper");
  }
  for (const [rubric, label] of [[record.quality_receipt?.rubric, "quality"], [record.experiment_product_rating?.rubric, "experiment rating"]]) {
    if (!rubric) continue;
    const document = sourceDocument(rubric.config_digest);
    if (!document || document.id !== rubric.id || document.version !== rubric.version) errors.push(`${label} rubric source document does not match id/version wrapper`);
  }
}

const lanes = ["chat", "mcp-ask", "delegate", "delegate-disagreement", "delegate-shadow", "code-loop"];

function expectedGovernanceSubjects(record) {
  assert.equal(isUnknown(record.task.source.principal), false, "complete governance requires a known authenticated source principal");
  const sourceOwner = record.task.source.content_owner.id;
  const expected = new Map([
    [`source:${record.task.origin_component}:${record.task.source.id}`, ["source", sourceOwner]],
    ["fingerprint:raw", ["raw-fingerprint", sourceOwner]],
  ]);
  for (const sourceRef of new Set(sourceDocumentClaims(record).map((claim) => claim.source_ref))) expected.set(sourceRef, ["source-document", sourceOwner]);
  for (const artifact of record.artifacts.items) expected.set(artifact.ref, ["artifact", artifact.owner]);
  const repository = record.artifacts.repository;
  if (!isUnknown(repository)) {
    if (!isUnknown(repository.diff_hash)) expected.set("repository:diff-hash", ["repository-diff-hash", sourceOwner]);
    if (!isUnknown(repository.changed_files_ref)) expected.set(repository.changed_files_ref, ["repository-file-list", sourceOwner]);
  }
  if (record.quality_receipt) {
    expected.set("quality:task-document", ["quality-binding", sourceOwner]);
    expected.set("quality:structured-result", ["quality-binding", sourceOwner]);
    expected.set("quality:rating-reason", ["rating-reason", sourceOwner]);
  }
  if (record.experiment_product_rating) expected.set("experiment:rating-reason", ["rating-reason", sourceOwner]);
  return expected;
}

function effectiveGovernance(policies) {
  const sensitivityRank = { public: 0, internal: 1, private: 2 };
  const erasureRank = { active: 0, requested: 1, expired: 2, erased: 3 };
  const sensitivity = policies.reduce((current, p) => sensitivityRank[p.sensitivity] > sensitivityRank[current] ? p.sensitivity : current, "public");
  const allowedUses = policies.slice(1).reduce((uses, p) => uses.filter((use) => p.allowed_uses.includes(use)), [...policies[0].allowed_uses]).sort();
  const knownExpiries = policies.map((p) => p.retention.expires_at).filter((value) => typeof value === "string");
  const expiresAt = knownExpiries.reduce((earliest, value) => earliest === null || Date.parse(value) < Date.parse(earliest) ? value : earliest, null) ?? { value: null, unknown_reason: "not-applicable" };
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
  const distinctOwners = [...new Set(governance.policies.map((policy) => policy.content_owner))].sort();
  const attestationOwners = governance.policy_manifest.owner_attestations.map((attestation) => attestation.content_owner).sort();
  if (canonical(attestationOwners) !== canonical(distinctOwners) || new Set(attestationOwners).size !== attestationOwners.length) errors.push("policy manifest must carry exactly one owner attestation per distinct content owner");
  for (const attestation of governance.policy_manifest.owner_attestations) {
    if (attestation.authentication === "authenticated-owner") {
      if (attestation.authenticated_principal !== attestation.content_owner || !isUnknown(attestation.delegation) || attestation.delegation.unknown_reason !== "not-applicable") errors.push(`authenticated owner attestation is invalid for ${attestation.content_owner}`);
    } else {
      if (isUnknown(attestation.delegation)
        || attestation.delegation.delegated_by !== attestation.content_owner
        || attestation.delegation.delegated_to !== attestation.authenticated_principal
        || Date.parse(attestation.delegation.issued_at) > Date.parse(governance.policy_manifest.approved_at)
        || Date.parse(attestation.delegation.expires_at) < Date.parse(governance.policy_manifest.approved_at)) errors.push(`delegation attestation is invalid for ${attestation.content_owner}`);
    }
    const authorityIdentity = {
      content_owner: attestation.content_owner,
      authenticated_principal: attestation.authenticated_principal,
      authentication: attestation.authentication,
      delegation: attestation.delegation,
    };
    const approvedPolicies = governance.policies.filter((policy) => policy.content_owner === attestation.content_owner).sort((a, b) => compareUtf16CodeUnits(a.subject_ref, b.subject_ref));
    const requiredApproval = {
      manifest: { manifest_id: governance.policy_manifest.manifest_id, version: governance.policy_manifest.version, approved_at: governance.policy_manifest.approved_at },
      record_binding: { producer: record.producer.component, record_kind: record.record_kind, task: record.task },
      policy_subset_digest: { algorithm: "sha256", version: "owner-policy-subset-jcs-v1", digest: digestCanonical(approvedPolicies) },
    };
    const expectedIssuer = attestation.authentication === "authenticated-owner" ? attestation.authenticated_principal : attestation.delegation.delegated_by;
    if (attestation.authority_evidence.issuer !== expectedIssuer) errors.push(`owner attestation issuer is not authoritative for ${attestation.content_owner}`);
    const authorityValid = validateTrustedEvidence(attestation.authority_evidence, "owner-authority", errors, undefined, `owner attestation for ${attestation.content_owner}`);
    const authorityPayload = trustedEvidence.get(attestation.authority_evidence.evidence_id)?.payload;
    if (authorityValid && (canonical({ content_owner: authorityPayload?.content_owner, authenticated_principal: authorityPayload?.authenticated_principal, authentication: authorityPayload?.authentication, delegation: authorityPayload?.delegation }) !== canonical(authorityIdentity)
      || !authorityPayload?.approvals?.some((approval) => canonical(approval) === canonical(requiredApproval)))) errors.push(`owner attestation does not bind the exact approved policy subset and manifest/record identity for ${attestation.content_owner}`);
  }
  const sourceOwnerAttestation = governance.policy_manifest.owner_attestations.find((attestation) => attestation.content_owner === record.task.source.content_owner.id);
  const expectedAttestationMode = record.task.source.content_owner.authority === "authenticated-owner" ? "authenticated-owner" : "delegation-attestation";
  if (!sourceOwnerAttestation || sourceOwnerAttestation.authentication !== expectedAttestationMode) errors.push("source content-owner authority must match its verified owner-attestation mode");
  const manifestSource = sourceDocuments.get(governance.policy_manifest.digest.source_ref);
  const expectedManifest = {
    schema_version: "governance-policy-manifest/v1",
    contract: { contract_version: record.contract_version, schema_revision: record.schema_revision },
    manifest: {
      manifest_id: governance.policy_manifest.manifest_id,
      version: governance.policy_manifest.version,
      approved_at: governance.policy_manifest.approved_at,
      owner_attestations: [...governance.policy_manifest.owner_attestations].sort((a, b) => compareUtf16CodeUnits(a.content_owner, b.content_owner)),
    },
    record_binding: { record_kind: record.record_kind, producer: record.producer.component, task: record.task },
    policies: [...governance.policies].sort((a, b) => compareUtf16CodeUnits(a.subject_ref, b.subject_ref)),
  };
  if (!manifestSource || canonical(manifestSource.document) !== canonical(expectedManifest)) errors.push("policy manifest source does not exactly bind contract, task, source, content owner, and sorted policies");
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
    if (isUnknown(record.execution.model_started_at) || isUnknown(record.execution.model_ended_at)) errors.push("direct gateway model clocks must be known");
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
  for (const field of ["source", "task_type", "raw_input", "raw_fingerprint"]) if (canonical(request[field]) !== canonical(record.task[field])) errors.push(`transport stamp does not bind task.${field}`);
  if (canonical(request.hugin_envelope) !== canonical(record.execution.prompt_identity.hugin_envelope)) errors.push("transport stamp does not bind Hugin envelope");
  if (canonical(request.origin_config) !== canonical(record.execution.origin_config)) errors.push("transport stamp does not bind origin config");
  if (canonical(request.macro_decision) !== canonical(record.execution.routing.macro)) errors.push("transport stamp does not bind macro decision");
  if (request.contract_request.contract_version !== record.contract_version || request.contract_request.schema_revision !== record.schema_revision) errors.push("Hugin contract request does not match record version/revision");
  if (Date.parse(request.stamped_at) < Date.parse(record.execution.started_at)) errors.push("Hugin request stamp precedes attempt start");
  if (Date.parse(request.stamped_at) > Date.parse(record.recorded_at)
    || (!isUnknown(record.execution.ended_at) && Date.parse(request.stamped_at) > Date.parse(record.execution.ended_at))) errors.push("Hugin request stamp follows attempt end or record creation");
  const preflight = request.preflight;
  if (canonical(preflight.request.requested_capabilities) !== canonical(request.contract_request)
    || canonical(preflight.response.capabilities) !== canonical(request.contract_request)) errors.push("preflight advertisement/request does not bind exact requested revision and features");
  if (preflight.response.authenticated_principal_id !== "service:gille-inference") errors.push("preflight response is not authenticated as gille-inference");
  if (!(Date.parse(preflight.request.requested_at) <= Date.parse(preflight.response.advertised_at)
    && Date.parse(preflight.response.advertised_at) <= Date.parse(request.stamped_at)
    && Date.parse(request.stamped_at) < Date.parse(preflight.response.expires_at))) errors.push("preflight freshness window does not cover request stamp");
  if (Date.parse(preflight.response.expires_at) - Date.parse(preflight.response.advertised_at) > 15 * 60 * 1000) errors.push("preflight advertisement cache TTL exceeds 15 minutes");
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
    for (const [name, value] of [["model start", record.execution.model_started_at], ["model end", record.execution.model_ended_at]]) {
      if (!isUnknown(value) || value.unknown_reason !== echo.unknown_reason) errors.push(`M5 non-admission ${name} reason must match the missing echo`);
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
  const principalBindingSource = { authenticated_principal_id: echo.authenticated_principal_id, request_stamp: request };
  if (echo.principal_binding_digest.digest !== digestCanonical(principalBindingSource)) errors.push("gateway principal binding digest does not bind principal/request identity");
  if (Date.parse(echo.admitted_at) < Date.parse(request.stamped_at)
    || isUnknown(record.execution.model_started_at)
    || Date.parse(echo.admitted_at) > Date.parse(record.execution.model_started_at)) errors.push("gateway admission clock is outside stamp/model-start interval");
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
  const allReceipts = [...protocol.core_stores, ...protocol.artifact_stores];
  if (new Set(allReceipts.map((receipt) => receipt.receipt_id)).size !== allReceipts.length) errors.push("erasure store receipt ids must be unique");
  if (allReceipts.some((receipt) => !["deleted", "absent-confirmed"].includes(receipt.status))) errors.push("every inventoried store must read back deleted or absent-confirmed");
  for (const receipt of [...protocol.core_stores, ...protocol.artifact_stores]) if (Date.parse(receipt.readback_at) < Date.parse(protocol.requested_at) || Date.parse(receipt.readback_at) > Date.parse(record.tombstone.effective_at)) errors.push(`store ${receipt.store ?? receipt.store_class} readback clock is outside erasure interval`);
  if (!(Date.parse(protocol.requested_at) <= Date.parse(protocol.backup_expiry.deadline)
    && Date.parse(protocol.backup_expiry.deadline) <= Date.parse(protocol.backup_expiry.verified_at)
    && Date.parse(protocol.backup_expiry.verified_at) <= Date.parse(record.tombstone.effective_at))) errors.push("backup expiry clocks must satisfy requested <= deadline <= verified <= effective");
  const basisCounters = {
    "hugin-task-non-m5": ["hugin-capture-denominator"],
    "hugin-task-m5": ["hugin-capture-denominator", "hugin-m5-join-denominator"],
    "joined-exposure": ["hugin-m5-join-denominator"],
    "direct-exposure": ["direct-m5-exposure-denominator"],
    "pipeline-hugin-capture-denominator": ["hugin-capture-denominator"],
    "pipeline-hugin-m5-join-denominator": ["hugin-m5-join-denominator"],
    "pipeline-direct-m5-exposure-denominator": ["direct-m5-exposure-denominator"],
    "pipeline-evaluation-candidate-denominator": ["evaluation-candidate-denominator"],
    "not-denominator-bearing": [],
  };
  const basis = record.tombstone.denominator_basis;
  if (record.record_kind === "task-outcome" && !["hugin-task-non-m5", "hugin-task-m5"].includes(basis)) errors.push("task-outcome tombstone must declare its exact capture/join denominator basis");
  if (record.record_kind === "inference-exposure" && !["joined-exposure", "direct-exposure"].includes(basis)) errors.push("inference-exposure tombstone must declare its exact join/direct denominator basis");
  if (record.record_kind === "pipeline-accounting" && !basis.startsWith("pipeline-") && basis !== "not-denominator-bearing") errors.push("pipeline accounting tombstone has an invalid denominator basis");
  if (!["task-outcome", "inference-exposure", "pipeline-accounting"].includes(record.record_kind) && basis !== "not-denominator-bearing") errors.push(`${record.record_kind} tombstone cannot declare a denominator basis`);
  const expectedCounters = basisCounters[basis] ?? [];
  const basisIssuer = basis.startsWith("hugin-task-") || basis === "joined-exposure" ? "hugin"
    : basis === "direct-exposure" ? "gille-inference"
      : record.producer.component;
  const basisEvidence = trustedEvidence.get(record.tombstone.denominator_basis_evidence.evidence_id);
  const basisIssuedAt = basisEvidence?.payload?.issued_at;
  const basisPayload = { producer: record.producer.component, record_kind: record.record_kind, superseded_record_id: record.tombstone.superseded_record_id, denominator_basis: basis, counters: [...expectedCounters].sort(compareUtf16CodeUnits), issued_at: basisIssuedAt };
  if (record.tombstone.denominator_basis_evidence.issuer !== basisIssuer
    || !validateTrustedEvidence(record.tombstone.denominator_basis_evidence, "denominator-basis", errors, basisPayload, "tombstone denominator basis")
    || !isExactUtcDateTime(basisIssuedAt)
    || Date.parse(basisIssuedAt) > Date.parse(protocol.requested_at)) errors.push("tombstone denominator basis is not authenticated by its authoritative owner with a valid pre-erasure issue clock");
  const basisRequiresMembership = record.tombstone.denominator_basis !== "not-denominator-bearing";
  if (basisRequiresMembership && (record.tombstone.denominator_impact !== "denominator-membership-preserved" || record.tombstone.counter_audit.length === 0)) errors.push("denominator-bearing tombstone requires an idempotent membership receipt");
  if (record.tombstone.denominator_impact === "not-denominator-bearing" && record.tombstone.counter_audit.length !== 0) errors.push("non-denominator tombstone cannot fabricate counter receipts");
  if (!basisRequiresMembership && record.tombstone.denominator_impact !== "not-denominator-bearing") errors.push("non-denominator basis cannot claim preserved denominator membership");
  if (canonical(record.tombstone.counter_audit.map((entry) => entry.counter).sort(compareUtf16CodeUnits)) !== canonical([...expectedCounters].sort(compareUtf16CodeUnits))) errors.push("tombstone counter receipts do not exactly match the declared denominator basis");
  const counterPeriods = new Set();
  for (const entry of record.tombstone.counter_audit) {
    const receipt = entry.membership_receipt;
    if (counterOwners[entry.counter] !== receipt.owner_component) errors.push(`membership receipt owner ${receipt.owner_component} does not own counter ${entry.counter}`);
    if (record.tombstone.denominator_basis.startsWith("pipeline-") && receipt.owner_component !== record.producer.component) errors.push("pipeline denominator tombstone membership remains owned by its accounting producer");
    if (entry.disposition !== "idempotent-membership-preserved") errors.push("counter audit requires idempotent membership preservation");
    const key = `${receipt.owner_component}|${entry.counter}|${entry.period_utc}|${receipt.membership_key_digest.digest}`;
    if (counterPeriods.has(key)) errors.push(`duplicate counter audit key ${key}`);
    counterPeriods.add(key);
    const evidence = trustedEvidence.get(receipt.membership_token.evidence_id);
    const membershipPayload = evidence?.payload;
    if (!validateTrustedEvidence(receipt.membership_token, "denominator-membership", errors, undefined, `counter ${entry.counter} membership token`)
      || receipt.membership_token.issuer !== receipt.owner_component
      || membershipPayload?.owner_component !== receipt.owner_component
      || membershipPayload?.counter !== entry.counter
      || membershipPayload?.period_utc !== entry.period_utc
      || membershipPayload?.superseded_record_id !== record.tombstone.superseded_record_id
      || canonical(membershipPayload?.denominator_natural_key_digest) !== canonical(receipt.membership_key_digest)
      || !isExactUtcDateTime(membershipPayload?.issued_at)
      || Date.parse(membershipPayload?.issued_at) > Date.parse(protocol.requested_at)
      || Date.parse(membershipPayload?.issued_at) > Date.parse(receipt.confirmed_at)) errors.push(`counter ${entry.counter} membership token does not bind owner, natural key, occurrence month, superseded record, and valid issue time`);
    if (receipt.membership_key_digest.version !== "denominator-natural-key-jcs-v1") errors.push(`counter ${entry.counter} does not retain the exact denominator natural-key digest`);
    if ((receipt.outcome === "inserted" && receipt.delta !== 1) || (receipt.outcome === "already-present" && receipt.delta !== 0)) errors.push(`counter ${entry.counter} membership outcome and delta are incoherent`);
    if (Date.parse(receipt.confirmed_at) < Date.parse(protocol.requested_at)
      || Date.parse(receipt.confirmed_at) > Date.parse(record.tombstone.effective_at)) errors.push(`counter ${entry.counter} membership was not confirmed before effective removal`);
  }
  return errors;
}

const counterOwners = { "hugin-capture-denominator": "hugin", "hugin-m5-join-denominator": "hugin", "direct-m5-exposure-denominator": "gille-inference", "evaluation-candidate-denominator": "hugin" };
const counterStages = { "hugin-capture-denominator": "capture", "hugin-m5-join-denominator": "join", "direct-m5-exposure-denominator": "direct-exposure", "evaluation-candidate-denominator": "evaluation" };
const candidateExclusionCodes = new Set(["candidate-governance-denied", "candidate-erased-or-expired", "candidate-exposure-incomplete", "candidate-provenance-incomplete", "candidate-product-quality-conflicted", "candidate-verifier-inadmissible", "candidate-duplicate-lineage"]);
const operationalFailureCodes = new Set(["producer-error", "consumer-error", "schema-rejected", "join-mismatch", "late-over-24h", "policy-unavailable", "transport-auth-failed", "gateway-not-admitted", "transport-error"]);

function utcMonth(timestamp) {
  return new Date(Date.parse(timestamp)).toISOString().slice(0, 7);
}

function validatePipelineAccounting(record) {
  const errors = [];
  const event = record.pipeline_accounting;
  if (record.producer.component !== event.owner_component) errors.push("pipeline accounting producer must equal counter/event owner");
  if (Date.parse(event.observed_at) > Date.parse(record.recorded_at)) errors.push("pipeline accounting event follows record creation");
  if (Date.parse(record.accounting_governance.expires_at) <= Date.parse(record.recorded_at)) errors.push("pipeline accounting retention is already expired");
  for (const namespace of Object.keys(record.extensions)) if (namespace !== record.producer.component) errors.push(`extension namespace ${namespace} is not owned by producer ${record.producer.component}`);
  for (const target of record.lineage.correction_targets) if (target.producer !== record.producer.component || target.record_kind !== "pipeline-accounting" || target.fact_domain !== "pipeline-accounting") errors.push("correction target must retain the same producer, record kind, and fact domain");
  if (record.lineage.correction_targets.length > 0 && isUnknown(record.lineage.correction_ref)) errors.push("pipeline correction targets require an immutable correction reference");
  const retryKnown = !isUnknown(event.retry);
  const denominatorKnown = !isUnknown(event.denominator);
  const aggregateKnown = !isUnknown(event.aggregate_close);
  const evaluationBundleKnown = !isUnknown(event.evaluation_bundle);
  const relatedKnown = !isUnknown(event.related_record);
  const deliveryOrdinalKnown = !isUnknown(event.delivery_ordinal);
  if (event.event_type === "denominator-decision") {
    if (!denominatorKnown || retryKnown || aggregateKnown || deliveryOrdinalKnown || !["capture", "join", "direct-exposure", "evaluation"].includes(event.stage) || !["admitted", "failed", "excluded"].includes(event.disposition)) errors.push("denominator decision has incoherent immutable accounting fields");
    else {
      if (counterOwners[event.denominator.counter] !== event.owner_component || counterStages[event.denominator.counter] !== event.stage || event.denominator.decision !== event.disposition) errors.push("denominator decision does not match its owner, stage, and disposition");
      if (["capture", "join"].includes(event.stage) && (event.owner_component !== "hugin" || event.task_link.origin_component !== "hugin")) errors.push(`${event.stage} accounting requires Hugin owner and Hugin-origin task linkage`);
      if (event.stage === "direct-exposure" && (event.owner_component !== "gille-inference" || event.task_link.origin_component !== "gille-inference")) errors.push("direct-exposure accounting requires gille-inference owner and direct-origin task linkage");
      if (utcMonth(event.denominator.occurrence_at) !== event.denominator.occurrence_month_utc) errors.push("denominator occurrence month must derive from occurrence_at in UTC");
      if (Date.parse(event.denominator.occurrence_at) > Date.parse(event.observed_at)) errors.push("denominator occurrence_at must not follow observed_at");
      if (event.disposition === "admitted" && event.failure_code !== "not-applicable") errors.push("admitted denominator event cannot carry a failure code");
      const expectedAdmittedRecord = event.stage === "capture" ? ["hugin", "task-outcome"]
        : ["join", "direct-exposure"].includes(event.stage) ? ["gille-inference", "inference-exposure"]
          : null;
      if (event.disposition === "admitted" && (!relatedKnown || (expectedAdmittedRecord && (event.related_record.producer !== expectedAdmittedRecord[0] || event.related_record.record_kind !== expectedAdmittedRecord[1])))) errors.push(`${event.stage} admission must bind its expected immutable learning record`);
      if (["capture", "join", "direct-exposure"].includes(event.stage) && ["failed", "excluded"].includes(event.disposition) && relatedKnown) errors.push(`${event.stage} failure or boundary exclusion cannot claim a valid learning record`);
      if (event.stage === "evaluation" && ["admitted", "excluded"].includes(event.disposition) && !relatedKnown) errors.push("evaluation admission or exclusion must bind the evaluated candidate record");
      if (event.stage === "evaluation" && event.disposition === "failed" && relatedKnown) errors.push("failed evaluation pipeline event cannot claim a completed candidate record");
      if (event.disposition === "excluded") {
        const allowed = event.stage === "evaluation" ? candidateExclusionCodes
          : ["capture", "direct-exposure"].includes(event.stage) ? new Set(["synthetic-test", "pre-v1-migration"])
            : new Set(["not-m5-routed", "pre-v1-migration"]);
        if (!allowed.has(event.failure_code)) errors.push(`${event.stage} exclusion requires its closed boundary code`);
      }
      if (event.disposition === "failed" && !operationalFailureCodes.has(event.failure_code)) errors.push("failed denominator event requires an operational omission/failure code");
      if (event.stage === "evaluation" && event.disposition === "admitted" && !evaluationBundleKnown) errors.push("evaluation admission requires a complete joined evidence bundle");
      if (!(event.stage === "evaluation" && event.disposition === "admitted") && evaluationBundleKnown) errors.push("only admitted evaluation decisions may carry an evaluation bundle");
      const boundaryKnown = !isUnknown(event.denominator.boundary_evidence);
      if (["synthetic-test", "pre-v1-migration"].includes(event.failure_code)) {
        if (!boundaryKnown) errors.push(`${event.failure_code} exclusion requires trusted pre-occurrence boundary evidence`);
        else {
          const boundary = event.denominator.boundary_evidence;
          const expectedKind = event.failure_code === "synthetic-test" ? "synthetic-declaration" : "compatibility-window";
          const payload = { owner_component: event.owner_component, task_link: event.task_link, failure_code: event.failure_code, kind: boundary.kind, declared_at: boundary.declared_at, valid_from: boundary.valid_from, valid_through: boundary.valid_through };
          if (boundary.kind !== expectedKind || boundary.proof.issuer !== event.owner_component || !validateTrustedEvidence(boundary.proof, "accounting-boundary", errors, payload, `${event.failure_code} boundary`)
            || Date.parse(boundary.declared_at) > Date.parse(event.denominator.occurrence_at)
            || Date.parse(boundary.valid_from) > Date.parse(event.denominator.occurrence_at)
            || Date.parse(event.denominator.occurrence_at) > Date.parse(boundary.valid_through)) errors.push(`${event.failure_code} evidence was not declared by the owner before occurrence inside its trusted window`);
        }
      } else if (boundaryKnown) errors.push("ordinary denominator decisions cannot carry exclusion boundary evidence");
    }
  } else if (["request-retry", "record-delivery-retry"].includes(event.event_type)) {
    const expectedKind = event.event_type === "request-retry" ? "request-transport" : "record-delivery";
    if (!retryKnown || event.retry.kind !== expectedKind || event.stage !== expectedKind || event.disposition !== "retry" || denominatorKnown || aggregateKnown || evaluationBundleKnown) errors.push("retry accounting event has incoherent immutable retry fields");
    if (event.retry.ordinal < 2) errors.push("retry ordinal must start at two");
    if (event.event_type === "request-retry" && (event.owner_component !== "hugin" || event.task_link.origin_component !== "hugin" || relatedKnown || event.related_record.unknown_reason !== "not-applicable" || deliveryOrdinalKnown || event.failure_code !== "transport-error")) errors.push("request retry requires Hugin request linkage, transport-error, and no related record or delivery ordinal");
    if (event.event_type === "record-delivery-retry" && (!relatedKnown || !deliveryOrdinalKnown || event.delivery_ordinal !== event.retry.ordinal || event.failure_code !== "record-delivery-failed")) errors.push("delivery retry requires a known record, matching delivery ordinal, and record-delivery-failed");
  } else if (event.event_type === "record-emission") {
    if (retryKnown || denominatorKnown || aggregateKnown || evaluationBundleKnown || !deliveryOrdinalKnown || event.stage !== "record-delivery" || !["succeeded", "failed"].includes(event.disposition)) errors.push("record emission accounting event has incoherent fields");
    if (!relatedKnown) errors.push("successful emission must bind its immutable record identity");
    if (relatedKnown && event.owner_component !== event.related_record.producer) errors.push("record delivery accounting must be owned by the related record producer");
    if (event.disposition === "succeeded" && event.failure_code !== "not-applicable") errors.push("successful emission must bind its immutable record identity without a failure code");
    if (event.disposition === "failed" && !["record-delivery-failed", "schema-rejected", "consumer-error"].includes(event.failure_code)) errors.push("failed emission requires a delivery/schema/consumer failure code");
  } else if (event.event_type === "aggregate-close") {
    if (!aggregateKnown || retryKnown || denominatorKnown || evaluationBundleKnown || deliveryOrdinalKnown || event.stage !== "aggregate" || event.disposition !== "succeeded" || event.failure_code !== "not-applicable") errors.push("aggregate close has incoherent immutable fields");
    else {
      const close = event.aggregate_close;
      if (counterOwners[close.counter] !== event.owner_component) errors.push("aggregate close owner does not own counter");
      if (!(Date.parse(close.included_through) <= Date.parse(close.closed_at) && Date.parse(close.closed_at) <= Date.parse(record.recorded_at))) errors.push("aggregate close clocks are not ordered");
      const [year, month] = close.period_utc.split("-").map(Number);
      const nextMonthBoundary = Date.UTC(year, month, 1);
      if (Date.parse(close.included_through) < nextMonthBoundary) errors.push("aggregate close included_through must reach the next UTC month boundary");
      if (nextMonthBoundary > Date.parse(close.closed_at)) errors.push("aggregate close cannot close an open occurrence month");
      if (record.lineage.correction_targets.length === 0 && Date.parse(close.closed_at) > nextMonthBoundary + 24 * 60 * 60 * 1000) errors.push("initial aggregate close exceeds the 24-hour close grace");
      const proofKnown = !isUnknown(close.partition_proof);
      if (close.verification_scope === "full-period-partition" && !proofKnown) errors.push("full-period aggregate close requires an authoritative partition proof");
      if (close.verification_scope === "partial-dataset-deferred" && proofKnown) errors.push("partial aggregate close cannot claim an authoritative partition proof");
    }
  }
  if (event.event_type !== "aggregate-close" && (isUnknown(event.task_link.origin_component) || isUnknown(event.task_link.task_instance_id) || isUnknown(event.task_link.attempt_id))) errors.push("pipeline accounting event must retain origin, task, and attempt linkage even when no learning record exists");
  const notM5Boundary = event.event_type === "denominator-decision" && event.stage === "join" && event.disposition === "excluded" && event.failure_code === "not-m5-routed";
  if (notM5Boundary) {
    if (!isUnknown(event.task_link.request_id) || event.task_link.request_id.unknown_reason !== "not-applicable" || !isUnknown(event.task_link.idempotency_key) || event.task_link.idempotency_key.unknown_reason !== "not-applicable") errors.push("not-m5-routed join exclusion requires not-applicable request and idempotency linkage");
  } else if ((event.event_type === "request-retry" || event.stage === "join") && (isUnknown(event.task_link.request_id) || isUnknown(event.task_link.idempotency_key))) errors.push("dispatched join and request-retry accounting require request and idempotency linkage");
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
  if (record.record_kind === "pipeline-accounting") return validatePipelineAccounting(record);
  const errors = [];
  if (record.task.origin_component !== record.task.source.component) errors.push("task origin_component must equal task.source.component");
  if (Date.parse(record.task.source.accepted_at) < Date.parse(record.task.source.created_at)) errors.push("task source accepted_at precedes created_at");
  if (Date.parse(record.recorded_at) < Date.parse(record.task.source.accepted_at)) errors.push("recorded_at precedes task acceptance");
  if (record.execution) {
    if (Date.parse(record.execution.started_at) < Date.parse(record.task.source.accepted_at)) errors.push("execution started_at precedes task acceptance");
    if (Date.parse(record.execution.started_at) > Date.parse(record.recorded_at)) errors.push("execution started_at exceeds recorded_at");
    if (!isUnknown(record.execution.ended_at) && Date.parse(record.execution.ended_at) < Date.parse(record.execution.started_at)) errors.push("execution ended_at precedes started_at");
    if (!isUnknown(record.execution.ended_at) && Date.parse(record.execution.ended_at) > Date.parse(record.recorded_at)) errors.push("execution ended_at exceeds recorded_at");
    const modelStartUnknown = isUnknown(record.execution.model_started_at);
    const modelEndUnknown = isUnknown(record.execution.model_ended_at);
    if (modelStartUnknown !== modelEndUnknown || (modelStartUnknown && record.execution.model_started_at.unknown_reason !== record.execution.model_ended_at.unknown_reason)) errors.push("model clocks must be known together or share one qualified missing reason");
    if (!modelStartUnknown && (Date.parse(record.execution.model_started_at) < Date.parse(record.execution.started_at)
      || Date.parse(record.execution.model_ended_at) < Date.parse(record.execution.model_started_at)
      || isUnknown(record.execution.ended_at)
      || Date.parse(record.execution.model_ended_at) > Date.parse(record.execution.ended_at))) errors.push("model clocks are outside the task attempt interval");
    if (servingProvenanceComplete(record.execution.serving) && modelStartUnknown) errors.push("known serving execution requires known model clocks");
  }
  const sourceClaims = sourceDocumentClaims(record);
  for (const claim of sourceClaims) validateSourceDocumentDigest(claim, errors);
  const sourceIdentities = new Map();
  for (const claim of sourceClaims) {
    const identity = canonical({ source_type: claim.source_type, source_version: claim.source_version, digest: claim.digest });
    if (sourceIdentities.has(claim.source_ref) && sourceIdentities.get(claim.source_ref) !== identity) errors.push(`inconsistent immutable source document claim for ${claim.source_ref}`);
    else sourceIdentities.set(claim.source_ref, identity);
  }
  validateReproducibilityRoles(record, errors);
  const rawSource = sourceDocument(record.task.raw_input);
  if (!rawSource || rawSource.origin_component !== record.task.origin_component || record.task.raw_fingerprint.digest !== digest(rawSource.text.trim())) errors.push("raw fingerprint does not equal trim-utf8-sha256-v1 over the exact pre-orchestration raw input source");
  validateReviewPair(record, errors);
  if (!isUnknown(record.review.reviewed_at) && Date.parse(record.review.reviewed_at) < Date.parse(record.task.source.accepted_at)) errors.push("review predates source acceptance");
  validateGovernance(record, errors);
  validateTransport(record, errors);
  for (const namespace of Object.keys(record.extensions)) if (namespace !== record.producer.component) errors.push(`extension namespace ${namespace} is not owned by producer ${record.producer.component}`);
  if (record.producer.component === "gille-inference" && !isUnknown(record.artifacts.repository)) errors.push("gille-inference records cannot assert repository bindings");
  if (!isUnknown(record.lineage.correction_ref) && !record.artifacts.items.some((item) => item.kind === "correction" && item.ref === record.lineage.correction_ref)) errors.push("correction_ref must bind a correction artifact");
  if (record.lineage.correction_targets.length > 0 && isUnknown(record.lineage.correction_ref)) errors.push("correction targets require a same-owner correction artifact");
  const factDomains = { "task-outcome": "outcome", "inference-exposure": "exposure", "capability-evidence": "capability", "experiment-observation": "experiment", "quality-receipt": "quality", "experiment-product-rating": "experiment-product", "pipeline-accounting": "pipeline-accounting" };
  for (const target of record.lineage.correction_targets) {
    if (target.producer !== record.producer.component || target.record_kind !== record.record_kind || target.fact_domain !== factDomains[record.record_kind]) errors.push("correction target must retain the same producer, record kind, and fact domain");
  }
  if (record.exposure?.kind === "observed-event") {
    if (record.exposure.fingerprint_version !== record.task.raw_fingerprint.version) errors.push("observed exposure fingerprint version differs from raw task fingerprint");
    if (canonical(record.exposure.raw_fingerprint) !== canonical(record.task.raw_fingerprint)) errors.push("observed exposure raw fingerprint differs from authoritative task fingerprint");
    if (record.transport?.hugin_request_stamp && !isUnknown(record.transport.hugin_request_stamp) && canonical(record.exposure.raw_fingerprint) !== canonical(record.transport.hugin_request_stamp.raw_fingerprint)) errors.push("observed exposure raw fingerprint differs from stamped fingerprint");
    if (Date.parse(record.exposure.first_seen_at) < Date.parse(record.task.source.accepted_at)
      || Date.parse(record.exposure.first_seen_at) > Date.parse(record.exposure.last_seen_at)
      || (record.execution && !isUnknown(record.execution.ended_at) && Date.parse(record.exposure.last_seen_at) > Date.parse(record.execution.ended_at))
      || Date.parse(record.exposure.last_seen_at) > Date.parse(record.recorded_at)) errors.push("observed exposure clocks are not ordered within accepted task attempt");
  }
  if (record.exposure?.kind === "negative-coverage-query") {
    if (canonical(record.exposure.queried_fingerprint) !== canonical(record.task.raw_fingerprint)) errors.push("negative coverage query fingerprint differs from task fingerprint");
    if (canonical([...record.exposure.coverage.lanes].sort()) !== canonical([...lanes].sort())) errors.push("negative coverage query does not cover the exact six lanes");
    const c = record.exposure.coverage;
    if (!(Date.parse(c.from) <= Date.parse(record.task.source.accepted_at)
      && Date.parse(record.task.source.accepted_at) <= Date.parse(c.relevant_task_at)
      && Date.parse(c.relevant_task_at) <= Date.parse(c.through)
      && Date.parse(c.through) <= Date.parse(record.exposure.queried_at)
      && Date.parse(record.exposure.queried_at) <= Date.parse(record.recorded_at))) errors.push("negative coverage clocks are not ordered around source acceptance");
    const evidence = trustedEvidence.get(record.exposure.attempt_proof.evidence_id);
    const attemptPayload = evidence?.payload;
    if (!validateTrustedEvidence(record.exposure.attempt_proof, "hugin-task-attempt", errors, undefined, "negative exposure attempt proof")
      || record.exposure.attempt_proof.issuer !== "hugin"
      || attemptPayload?.outcome_ref?.producer !== "hugin"
      || attemptPayload?.outcome_ref?.record_kind !== "task-outcome"
      || attemptPayload?.task_instance_id !== record.task.instance_id
      || attemptPayload?.attempt_id !== record.exposure.task_attempt_id
      || attemptPayload?.relevant_task_at !== c.relevant_task_at
      || canonical(attemptPayload?.raw_fingerprint) !== canonical(record.task.raw_fingerprint)) errors.push("negative exposure is not bound to the immutable Hugin outcome/stamp/attempt");
  }
  if (record.capability) {
    const verifier = record.capability.verifier;
    const calibrated = verifier.kind === "deterministic" || verifier.kind === "human" || (verifier.kind === "calibrated-judge" && !isUnknown(verifier.calibration_evidence_id));
    const qualifiedOutcome = (record.capability.outcome === "pass" && record.capability.admission_basis === "full-pass")
      || (record.capability.outcome === "partial" && record.capability.admission_basis === "policy-qualified-partial");
    if (record.capability.admission_state === "admissible" && (!calibrated || verifier.independence !== "independent" || !qualifiedOutcome)) errors.push("capability admission requires independent calibrated policy-qualified evidence");
    if (record.capability.admission_state === "admissible" && (!candidateProvenanceComplete(record) || !["m5-admitted", "direct-gateway"].includes(record.transport.state))) errors.push("capability admission requires complete nested serving provenance from a model-running transport");
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
    if (Date.parse(receipt.rated_at) < Date.parse(record.task.source.accepted_at) || Date.parse(receipt.rated_at) > Date.parse(record.recorded_at)) errors.push("quality receipt clock is outside source acceptance/record interval");
    const nativeSource = sourceDocuments.get(receipt.native_receipt.artifact_digest.source_ref);
    const expectedType = `quality-receipt-native-v${receipt.native_receipt.schema_version}`;
    if (!nativeSource || nativeSource.source_type !== expectedType || receipt.native_receipt.artifact_digest.source_type !== expectedType) errors.push("quality projection does not bind a native receipt artifact matching its schema version");
    else {
      const native = nativeSource.document;
      if (native.receiptId !== receipt.native_receipt.receipt_id || native.taskId !== receipt.task_id || native.rating !== receipt.rating || native.verificationOutcome !== receipt.disposition || digest(native.ratingReason) !== receipt.rating_reason_sha256 || native.ratedAt !== receipt.rated_at || canonical(native.reviewer) !== canonical(receipt.reviewer) || native.bindingAttestation !== receipt.binding_attestation || canonical(native.binding) !== canonical(normalizedNativeBinding(receipt.binding))) errors.push("normalized quality fields do not exactly project the immutable native receipt artifact");
      if (receipt.native_receipt.schema_version === 1) {
        if (Object.hasOwn(native, "attemptId") || Object.hasOwn(native, "rubric")) errors.push("native Hugin v1 receipt cannot claim attempt or rubric fields");
        const semantic = { taskId: native.taskId, reviewerPrincipal: native.reviewer.principal, reviewerIndependence: native.reviewer.independence, rating: native.rating, ratingReason: native.ratingReason, verificationOutcome: native.verificationOutcome, retriesCount: native.retriesCount, bindingAttestation: native.bindingAttestation, binding: native.binding };
        if (native.receiptId !== huginReceiptId(semantic)) errors.push("native Hugin v1 receipt id is not content-derived from its exact verdict");
        if ((native.retriesCount ?? null) !== (Number.isInteger(receipt.retries_count) ? receipt.retries_count : null)) errors.push("normalized retry count fabricates an optional native v1 field");
      } else if (native.attemptId !== receipt.attempt_id || canonical(native.rubric) !== canonical(receipt.rubric) || typeof native.correctsReceiptId !== "string" || native.correctsReceiptId === native.receiptId) errors.push("future native v2 correction does not bind attempt/rubric and a distinct predecessor receipt id");
    }
    const expectedGroup = { task_id: receipt.task_id, attempt_id: receipt.attempt_id, reviewer: receipt.reviewer, rubric: receipt.rubric, binding: receipt.binding };
    if (receipt.correction_group_key.version !== "quality-correction-group-jcs-v1" || receipt.correction_group_key.digest !== digestCanonical(expectedGroup)) errors.push("quality correction group does not bind task/attempt/reviewer/rubric/result");
  }
  if (record.experiment_product_rating) {
    const rating = record.experiment_product_rating;
    if (rating.reviewer.principal !== record.review.reviewer_principal_id || rating.rated_at !== record.review.reviewed_at) errors.push("experiment rating reviewer does not match envelope");
    if (Date.parse(rating.rated_at) < Date.parse(record.task.source.accepted_at) || Date.parse(rating.rated_at) > Date.parse(record.recorded_at)) errors.push("experiment rating clock is outside source acceptance/record interval");
  }
  return errors;
}

function joinedIdentityErrors(records) {
  const errors = [];
  const groups = new Map();
  for (const record of records) {
    if (record.lifecycle_state !== "active" || record.task?.origin_component !== "hugin" || !record.execution) continue;
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
  return fields.map((field) => {
    const value = pointer(record, field);
    return value === undefined ? "<absent>" : canonical(value);
  }).join("|");
}

function supersessionErrors(group, label) {
  const errors = [];
  const unique = [...new Map(group.map((record) => [`${record.producer.component}|${record.record_id}`, record])).values()];
  if (unique.length <= 1) return errors;
  const byId = new Map(unique.map((record) => [record.record_id, record]));
  const childCount = new Map(unique.map((record) => [record.record_id, 0]));
  const parentById = new Map();
  for (const record of unique) {
    const targets = record.lineage.correction_targets ?? [];
    if (targets.length === 0) continue;
    if (targets.length !== 1) {
      errors.push(`${label} correction must target exactly one predecessor`);
      continue;
    }
    const targetId = targets[0].record_id;
    if (targetId === record.record_id) errors.push(`${label} correction cannot target itself`);
    if (!byId.has(targetId)) {
      errors.push(`${label} correction target is missing or belongs to another natural key`);
      continue;
    }
    if (byId.has(targetId) && Date.parse(record.recorded_at) <= Date.parse(byId.get(targetId).recorded_at)) errors.push(`${label} correcting record must be strictly later than its predecessor`);
    parentById.set(record.record_id, targetId);
    childCount.set(targetId, childCount.get(targetId) + 1);
  }
  if ([...childCount.values()].some((count) => count > 1)) errors.push(`${label} correction supersession cannot fork`);
  const roots = unique.filter((record) => !parentById.has(record.record_id));
  const leaves = unique.filter((record) => childCount.get(record.record_id) === 0);
  if (roots.length !== 1) errors.push(`${label} correction supersession must have one root and no cycle`);
  if (leaves.length !== 1) errors.push(`${label} correction supersession must have one effective leaf`);
  for (const record of unique) {
    const visited = new Set();
    let cursor = record.record_id;
    while (parentById.has(cursor)) {
      if (visited.has(cursor)) {
        errors.push(`${label} correction supersession contains a cycle`);
        break;
      }
      visited.add(cursor);
      cursor = parentById.get(cursor);
    }
  }
  return [...new Set(errors)];
}

function effectiveSupersessionLeaf(group) {
  const unique = [...new Map(group.map((record) => [`${record.producer.component}|${record.record_id}`, record])).values()];
  if (unique.length === 1) return unique[0];
  const targeted = new Set(unique.flatMap((record) => (record.lineage.correction_targets ?? []).map((target) => target.record_id)));
  return unique.find((record) => !targeted.has(record.record_id));
}

function accountingTaskLinkKey(event) {
  return canonical(event.task_link);
}

function denominatorNaturalKey(event) {
  return canonical({
    owner_component: event.owner_component,
    counter: event.denominator.counter,
    occurrence_month_utc: event.denominator.occurrence_month_utc,
    task_link: {
      origin_component: event.task_link.origin_component,
      task_instance_id: event.task_link.task_instance_id,
      attempt_id: event.task_link.attempt_id,
    },
  });
}

function aggregateNaturalKey(event) {
  return canonical({ owner_component: event.owner_component, counter: event.aggregate_close.counter, period_utc: event.aggregate_close.period_utc });
}

function correctionNaturalKey(record) {
  if (record.record_kind === "quality-receipt") return `quality-correction|${canonical(record.quality_receipt.correction_group_key)}`;
  if (record.record_kind !== "pipeline-accounting") return conflictKey(record, schema["x-grimnir-conflict-keys"][record.record_kind]);
  const event = record.pipeline_accounting;
  if (event.event_type === "denominator-decision") return `denominator|${denominatorNaturalKey(event)}`;
  if (event.event_type === "request-retry") return `request-retry|${canonical({ owner_component: event.owner_component, task_link: event.task_link, ordinal: event.retry.ordinal })}`;
  if (event.event_type === "record-delivery-retry") return `record-delivery-retry|${canonical({ owner_component: event.owner_component, related_record: event.related_record, ordinal: event.retry.ordinal })}`;
  if (event.event_type === "record-emission") return `record-emission|${canonical({ owner_component: event.owner_component, related_record: event.related_record, delivery_ordinal: event.delivery_ordinal })}`;
  return `aggregate-close|${aggregateNaturalKey(event)}`;
}

function aggregateDigestPayload(closeRecord, decisions) {
  const event = closeRecord.pipeline_accounting;
  const close = event.aggregate_close;
  const entries = decisions.map((record) => ({
    natural_key: denominatorNaturalKey(record.pipeline_accounting),
    event_id: record.pipeline_accounting.event_id,
  })).sort((left, right) => compareUtf16CodeUnits(left.natural_key, right.natural_key) || compareUtf16CodeUnits(left.event_id, right.event_id));
  return {
    schema_version: "pipeline-aggregate-close/v1",
    owner_component: event.owner_component,
    counter: close.counter,
    period_utc: close.period_utc,
    included_through: close.included_through,
    event_count: entries.length,
    decisions: entries,
  };
}

function evidenceRef(record) {
  return { producer: record.producer.component, record_kind: record.record_kind, record_id: record.record_id };
}

function evaluationBundlePayloads(outcome, exposure, capability, qualities, decisionAt) {
  const qualitySummary = summarizeImmutable(qualities, "quality_receipt", ["rating", "disposition"], ["task_id", "attempt_id", "binding"])[0];
  const sortedQualityIds = qualities.map((record) => record.quality_receipt.native_receipt.receipt_id).sort(compareUtf16CodeUnits);
  return {
    governance: { task_outcome: outcome.record_id, decision_at: decisionAt, policy_manifest: outcome.governance.policy_manifest, effective: outcome.governance.effective },
    provenance: { task: outcome.task, execution: outcome.execution, transport: outcome.transport },
    exposure: { record_id: exposure.record_id, exposure: exposure.exposure },
    quality: { native_receipt_ids: sortedQualityIds, result: qualitySummary?.result ?? "unrated" },
    lineage: { task_instance_id: outcome.task.instance_id, attempt_id: outcome.execution.attempt_id, task_outcome: outcome.record_id, exposure: exposure.record_id, capability_evidence: capability.record_id, quality_receipts: sortedQualityIds },
  };
}

function validateEvaluationBundle(accountingRecord, records, errors) {
  const event = accountingRecord.pipeline_accounting;
  if (event.event_type !== "denominator-decision" || event.stage !== "evaluation" || event.disposition !== "admitted" || isUnknown(event.evaluation_bundle)) return;
  const bundle = event.evaluation_bundle;
  const byRef = (ref) => records.find((record) => record.lifecycle_state === "active" && record.producer.component === ref.producer && record.record_kind === ref.record_kind && record.record_id === ref.record_id);
  const outcome = byRef(bundle.task_outcome);
  const exposure = byRef(bundle.exposure);
  const capability = byRef(bundle.capability_evidence);
  const qualities = bundle.quality_receipts.map(byRef).filter(Boolean);
  if (canonical(bundle.task_outcome) !== canonical(event.related_record) || bundle.task_outcome.record_kind !== "task-outcome" || bundle.exposure.record_kind !== "inference-exposure" || bundle.capability_evidence.record_kind !== "capability-evidence" || bundle.quality_receipts.some((ref) => ref.record_kind !== "quality-receipt")) errors.push("evaluation bundle references the wrong evidence kinds or candidate");
  if (!outcome || !exposure || !capability || qualities.length !== bundle.quality_receipts.length) {
    errors.push("evaluation bundle is not fully loaded and trusted");
    return;
  }
  const availableRecords = records.filter((record) => record.lifecycle_state === "active" && Date.parse(record.recorded_at) <= Date.parse(bundle.decision_at));
  const effectiveLeaves = (candidates) => {
    const groups = new Map();
    for (const candidate of candidates) {
      const key = correctionNaturalKey(candidate);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(candidate);
    }
    return [...groups.values()].map(effectiveSupersessionLeaf);
  };
  for (const referenced of [outcome, exposure, capability, ...qualities]) {
    const group = availableRecords.filter((candidate) => candidate.producer.component === referenced.producer.component && candidate.record_kind === referenced.record_kind && correctionNaturalKey(candidate) === correctionNaturalKey(referenced));
    if (effectiveSupersessionLeaf(group)?.record_id !== referenced.record_id) errors.push("evaluation bundle does not reference the effective correction leaf at decision time");
  }
  if (bundle.decision_at !== event.denominator.occurrence_at || Date.parse(bundle.decision_at) > Date.parse(event.observed_at)) errors.push("evaluation denominator occurrence must equal decision time and not follow accounting observation");
  if ([outcome, exposure, capability, ...qualities].some((record) => Date.parse(record.recorded_at) > Date.parse(bundle.decision_at))) errors.push("evaluation bundle includes evidence that was not available at decision time");
  if (!governanceEligibleAt(outcome, bundle.decision_at) || !candidateProvenanceComplete(outcome)) errors.push("evaluation candidate lacks complete provenance/governance at decision time");
  if (canonical(outcome.task) !== canonical(exposure.task) || canonical(outcome.execution) !== canonical(exposure.execution) || canonical(outcome.task) !== canonical(capability.task) || canonical(outcome.execution) !== canonical(capability.execution) || qualities.some((record) => record.quality_receipt.task_id !== outcome.task.instance_id || record.quality_receipt.attempt_id !== outcome.execution.attempt_id)) errors.push("evaluation bundle evidence does not join one exact task attempt");
  if (capability.capability.admission_state !== "admissible" || capability.capability.verifier.independence !== "independent") errors.push("evaluation bundle verifier evidence is not independently admissible");
  const summaries = summarizeImmutable(qualities, "quality_receipt", ["rating", "disposition"], ["task_id", "attempt_id", "binding"]);
  const summary = summaries[0];
  if (summaries.length > 1 || (summary && summary.result === "conflicted") || qualities.some((record) => record.quality_receipt.reviewer.independence !== "independent")) errors.push("evaluation bundle quality evidence must be one independent non-conflicted binding/rubric cohort");
  const availableQualityLeaves = effectiveLeaves(availableRecords.filter((record) => record.record_kind === "quality-receipt" && record.quality_receipt.task_id === outcome.task.instance_id && record.quality_receipt.attempt_id === outcome.execution.attempt_id));
  const qualityCohortKey = (record) => canonical({ binding: record.quality_receipt.binding, rubric: record.quality_receipt.rubric });
  const availableCohorts = new Set(availableQualityLeaves.map(qualityCohortKey));
  if (qualities.length === 0) {
    if (availableQualityLeaves.length !== 0) errors.push("evaluation bundle cannot claim unrated while an effective quality receipt exists at decision time");
  } else {
    const selectedCohort = qualityCohortKey(qualities[0]);
    const availableCohortRefs = availableQualityLeaves.map((record) => canonical(evidenceRef(record))).sort(compareUtf16CodeUnits);
    const bundledCohortRefs = qualities.map((record) => canonical(evidenceRef(record))).sort(compareUtf16CodeUnits);
    if (availableCohorts.size !== 1) errors.push("evaluation bundle cannot choose among multiple available quality binding/rubric cohorts without an explicit governed selector");
    if (qualities.some((record) => qualityCohortKey(record) !== selectedCohort) || canonical(bundledCohortRefs) !== canonical(availableCohortRefs)) errors.push("evaluation bundle must include every effective quality leaf in the sole available binding/rubric cohort at decision time");
  }
  const sameLineageLeaves = effectiveLeaves(availableRecords.filter((record) => record.record_kind === "task-outcome" && record.task.instance_id === outcome.task.instance_id && record.execution.attempt_id === outcome.execution.attempt_id));
  if (sameLineageLeaves.length !== 1 || sameLineageLeaves[0]?.record_id !== outcome.record_id) errors.push("evaluation bundle does not prove one effective task-outcome lineage leaf at decision time");
  const payloads = evaluationBundlePayloads(outcome, exposure, capability, qualities, bundle.decision_at);
  for (const [field, payload, version] of [
    ["governance_snapshot_digest", payloads.governance, "evaluation-governance-jcs-v1"],
    ["complete_provenance_digest", payloads.provenance, "evaluation-provenance-jcs-v1"],
    ["exposure_coverage_digest", payloads.exposure, "evaluation-exposure-jcs-v1"],
    ["quality_consensus_digest", payloads.quality, "evaluation-quality-jcs-v1"],
    ["unique_lineage_digest", payloads.lineage, "evaluation-lineage-jcs-v1"],
  ]) if (bundle[field].version !== version || bundle[field].digest !== digestCanonical(payload)) errors.push(`evaluation bundle ${field} does not bind its exact joined evidence`);
}

function validateDataset(records) {
  const errors = [];
  for (const [index, record] of records.entries()) {
    const schemaErrors = validateNode(schema, record);
    errors.push(...schemaErrors.map((error) => `record ${index}: ${error}`));
    if (schemaErrors.length === 0) errors.push(...validateSemantics(record).map((error) => `record ${index}: ${error}`));
  }
  if (errors.length > 0) return errors;

  for (const record of records.filter((candidate) => candidate.lifecycle_state === "active" && candidate.record_kind === "pipeline-accounting")) validateEvaluationBundle(record, records, errors);
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

  const byProducerAndId = new Map(records.map((record) => [`${record.producer.component}|${record.record_id}`, record]));
  const factDomains = { "task-outcome": "outcome", "inference-exposure": "exposure", "capability-evidence": "capability", "experiment-observation": "experiment", "quality-receipt": "quality", "experiment-product-rating": "experiment-product", "pipeline-accounting": "pipeline-accounting" };
  for (const record of records) {
    if (record.lifecycle_state !== "active") continue;
    for (const target of record.lineage.correction_targets ?? []) {
      if (target.record_id === record.record_id) errors.push("correction cannot target itself");
      const targetRecord = byProducerAndId.get(`${target.producer}|${target.record_id}`);
      if (!targetRecord) errors.push("correction target is missing from the validated dataset");
      else if (targetRecord.lifecycle_state !== "active" || targetRecord.record_kind !== target.record_kind || factDomains[targetRecord.record_kind] !== target.fact_domain) errors.push("present correction target does not bind same-producer same-kind fact domain");
      else if (correctionNaturalKey(record) !== correctionNaturalKey(targetRecord)) errors.push("correction target belongs to another natural conflict key");
    }
  }
  if (errors.length > 0) return errors;

  const keyDefinitions = schema["x-grimnir-conflict-keys"];
  for (const [name, fields] of Object.entries(keyDefinitions)) {
    const groups = new Map();
    for (const record of records) {
      if (name !== "record" && (record.record_kind !== name || record.lifecycle_state !== "active")) continue;
      const key = conflictKey(record, fields);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(record);
    }
    for (const [key, group] of groups) {
      const bodies = new Set(group.map(canonical));
      if (bodies.size <= 1) continue;
      if (name === "record") errors.push(`conflicting ${name} key ${key}`);
      else errors.push(...supersessionErrors(group, `${name} key ${key}`));
    }
  }

  const qualityCorrectionGroups = new Map();
  for (const record of records.filter((candidate) => candidate.lifecycle_state === "active" && candidate.record_kind === "quality-receipt")) {
    const key = canonical(record.quality_receipt.correction_group_key);
    if (!qualityCorrectionGroups.has(key)) qualityCorrectionGroups.set(key, []);
    qualityCorrectionGroups.get(key).push(record);
  }
  for (const [key, group] of qualityCorrectionGroups) if (group.length > 1) errors.push(...supersessionErrors(group, `quality correction group ${key}`));

  const accountingRecords = records.filter((record) => record.lifecycle_state === "active" && record.record_kind === "pipeline-accounting");
  const accountingNaturalGroups = new Map();
  for (const [eventType, keyOf] of [
    ["denominator-decision", (event) => denominatorNaturalKey(event)],
    ["request-retry", (event) => canonical({ owner_component: event.owner_component, stage: event.stage, task_link: event.task_link, ordinal: event.retry.ordinal })],
    ["record-delivery-retry", (event) => canonical({ owner_component: event.owner_component, related_record: event.related_record, ordinal: event.retry.ordinal })],
    ["record-emission", (event) => canonical({ owner_component: event.owner_component, related_record: event.related_record, delivery_ordinal: event.delivery_ordinal })],
  ]) {
    for (const record of accountingRecords.filter((candidate) => candidate.pipeline_accounting.event_type === eventType)) {
      const key = keyOf(record.pipeline_accounting);
      const groupedKey = `${eventType}|${key}`;
      if (!accountingNaturalGroups.has(groupedKey)) accountingNaturalGroups.set(groupedKey, []);
      accountingNaturalGroups.get(groupedKey).push(record);
    }
  }
  for (const [key, group] of accountingNaturalGroups) errors.push(...supersessionErrors(group, `${key} natural key`));
  const aggregateGroups = new Map();
  for (const record of accountingRecords.filter((candidate) => candidate.pipeline_accounting.event_type === "aggregate-close")) {
    const key = aggregateNaturalKey(record.pipeline_accounting);
    if (!aggregateGroups.has(key)) aggregateGroups.set(key, []);
    aggregateGroups.get(key).push(record);
  }
  for (const [key, group] of aggregateGroups) errors.push(...supersessionErrors(group, `aggregate-close key ${key}`));
  if (errors.length > 0) return errors;

  for (const record of accountingRecords.filter((candidate) => candidate.pipeline_accounting.event_type === "denominator-decision")) {
    const event = record.pipeline_accounting;
    const matching = records.find((candidate) => candidate.lifecycle_state === "active" && candidate.task && candidate.execution
      && candidate.task.origin_component === event.task_link.origin_component
      && candidate.task.instance_id === event.task_link.task_instance_id
      && candidate.execution.attempt_id === event.task_link.attempt_id);
    if (matching && ["capture", "join"].includes(event.stage) && event.denominator.occurrence_at !== matching.execution.started_at) errors.push(`${event.stage} denominator occurrence_at does not match authoritative execution.started_at`);
    if (matching && event.stage === "direct-exposure" && event.denominator.occurrence_at !== matching.task.source.accepted_at) errors.push("direct-exposure denominator occurrence_at does not match authoritative source.accepted_at");
    if (matching && event.stage === "join") {
      const macro = matching.execution.routing.macro;
      if (event.failure_code === "not-m5-routed" && (!macro || isUnknown(macro) || macro.target === "m5")) errors.push("not-m5-routed join exclusion does not match the authoritative macro route");
      if (event.failure_code !== "not-m5-routed" && (!macro || isUnknown(macro) || macro.target !== "m5")) errors.push("dispatched join accounting does not match an authoritative M5 macro route");
    }
    if (!isUnknown(event.related_record)) {
      const related = records.find((candidate) => candidate.lifecycle_state === "active" && candidate.producer.component === event.related_record.producer && candidate.record_kind === event.related_record.record_kind && candidate.record_id === event.related_record.record_id);
      if (related && related.task && related.execution && (related.task.origin_component !== event.task_link.origin_component || related.task.instance_id !== event.task_link.task_instance_id || related.execution.attempt_id !== event.task_link.attempt_id)) errors.push("denominator related record does not match authoritative task/attempt linkage");
    }
  }
  for (const closeRecord of accountingRecords.filter((candidate) => candidate.pipeline_accounting.event_type === "aggregate-close")) {
    const event = closeRecord.pipeline_accounting;
    const close = event.aggregate_close;
    const decisionGroups = new Map();
    for (const candidate of accountingRecords.filter((item) => item.pipeline_accounting.event_type === "denominator-decision"
      && Date.parse(item.recorded_at) <= Date.parse(close.closed_at)
      && Date.parse(item.pipeline_accounting.denominator.occurrence_at) < Date.parse(close.included_through))) {
      const key = denominatorNaturalKey(candidate.pipeline_accounting);
      if (!decisionGroups.has(key)) decisionGroups.set(key, []);
      decisionGroups.get(key).push(candidate);
    }
    const constituents = [...decisionGroups.values()].map(effectiveSupersessionLeaf).filter((candidate) => {
      const candidateEvent = candidate.pipeline_accounting;
      return candidateEvent.owner_component === event.owner_component
        && candidateEvent.denominator.counter === close.counter
        && candidateEvent.denominator.occurrence_month_utc === close.period_utc;
    });
    if (close.verification_scope === "partial-dataset-deferred") {
      continue;
    }
    const proofEvidence = trustedEvidence.get(close.partition_proof.evidence_id);
    const proof = proofEvidence?.payload;
    const entries = constituents.map((candidate) => ({ natural_key: denominatorNaturalKey(candidate.pipeline_accounting), event_id: candidate.pipeline_accounting.event_id })).sort((left, right) => compareUtf16CodeUnits(left.natural_key, right.natural_key) || compareUtf16CodeUnits(left.event_id, right.event_id));
    if (close.partition_proof.issuer !== event.owner_component
      || !validateTrustedEvidence(close.partition_proof, "ledger-partition", errors, undefined, "aggregate partition proof")
      || proof?.owner_component !== event.owner_component
      || proof?.counter !== close.counter
      || proof?.period_utc !== close.period_utc
      || proof?.included_through !== close.included_through
      || typeof proof?.high_water_event_id !== "string"
      || canonical(proof?.decisions) !== canonical(entries)) errors.push("full-period aggregate is not certified by an authoritative ledger partition/high-water proof");
    const payload = aggregateDigestPayload(closeRecord, constituents);
    if (close.event_count !== constituents.length) errors.push("aggregate close event_count does not match the loaded full period partition");
    if (close.immutable_event_set_digest.version !== "pipeline-event-set-jcs-v1" || close.immutable_event_set_digest.digest !== digestCanonical(payload)) errors.push("aggregate close digest does not bind its loaded full period partition");
  }
  if (errors.length > 0) return errors;

  const attemptsByIdempotency = new Map();
  for (const record of records) {
    const stamp = record.transport?.hugin_request_stamp;
    if (!stamp || isUnknown(stamp)) continue;
    const key = stamp.idempotency_key;
    const identity = canonical({ task: stamp.task_instance_id, attempt: stamp.attempt_id, request: stamp.request_id, client: stamp.client_id });
    if (attemptsByIdempotency.has(key) && attemptsByIdempotency.get(key) !== identity) errors.push("idempotency key was reused for a different task/attempt/model execution");
    else attemptsByIdempotency.set(key, identity);
  }
  for (const record of records) {
    if (record.lifecycle_state !== "active" || record.record_kind !== "quality-receipt") continue;
    const receipt = record.quality_receipt;
    const taskExecutions = records.filter((candidate) => candidate.lifecycle_state === "active" && candidate.execution && candidate.task.instance_id === receipt.task_id);
    if (taskExecutions.length > 0 && !taskExecutions.some((candidate) => candidate.execution.attempt_id === receipt.attempt_id && canonical(candidate.task) === canonical(record.task))) errors.push("quality receipt does not bind a known task execution attempt");
    const matchingOutcome = taskExecutions.find((candidate) => candidate.record_kind === "task-outcome" && candidate.execution.attempt_id === receipt.attempt_id && canonical(candidate.task) === canonical(record.task));
    if (matchingOutcome && !isUnknown(matchingOutcome.execution.ended_at) && Date.parse(receipt.rated_at) < Date.parse(matchingOutcome.execution.ended_at)) errors.push("quality receipt predates the relevant task outcome");
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
    if (observation && Date.parse(rating.rated_at) < Date.parse(observation.recorded_at)) errors.push("experiment product rating predates referenced observation");
  }
  for (const record of records) {
    if (record.lifecycle_state !== "active" || record.record_kind !== "pipeline-accounting") continue;
    const event = record.pipeline_accounting;
    if (!["request-retry", "record-delivery-retry"].includes(event.event_type) || isUnknown(event.retry)) continue;
    if (event.event_type === "request-retry") {
      if (event.retry.replayed_identity_digest.version !== "request-stamp-jcs-v1") errors.push("request retry digest version must be request-stamp-jcs-v1");
      const source = records.find((candidate) => candidate.lifecycle_state === "active" && candidate.transport && !isUnknown(candidate.transport.hugin_request_stamp)
        && candidate.transport.hugin_request_stamp.task_instance_id === event.task_link.task_instance_id
        && candidate.transport.hugin_request_stamp.attempt_id === event.task_link.attempt_id
        && candidate.transport.hugin_request_stamp.request_id === event.task_link.request_id
        && candidate.transport.hugin_request_stamp.idempotency_key === event.task_link.idempotency_key);
      if (source && event.retry.replayed_identity_digest.digest !== digestCanonical(source.transport.hugin_request_stamp)) errors.push("request retry does not replay the identical immutable request stamp");
    } else {
      if (event.retry.replayed_identity_digest.version !== "record-ref-jcs-v1") errors.push("record-delivery retry digest version must be record-ref-jcs-v1");
      if (!isUnknown(event.related_record) && event.retry.replayed_identity_digest.digest !== digestCanonical(event.related_record)) errors.push("record-delivery retry does not replay the identical immutable record identity");
    }
  }
  return errors;
}

function summarizeImmutable(records, section, resultFields, bindingFields) {
  const correctionGroups = new Map();
  for (const record of records) {
    const key = section === "quality_receipt" ? canonical(record.quality_receipt.correction_group_key) : record[section].rating_id;
    if (!correctionGroups.has(key)) correctionGroups.set(key, []);
    correctionGroups.get(key).push(record);
  }
  const effectiveRecords = [...correctionGroups.values()].map(effectiveSupersessionLeaf);
  const groups = new Map();
  for (const record of effectiveRecords) {
    const value = record[section];
    const key = canonical({ binding: bindingFields.map((field) => value[field]), rubric: value.rubric });
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(value);
  }
  return [...groups.values()].map((values) => {
    const declared = values.map((value) => Object.fromEntries(resultFields.map((field) => [field, value[field]])));
    return {
      result: new Set(declared.map(canonical)).size === 1 ? declared[0] : "conflicted",
      ids: values.map((value) => value.native_receipt?.receipt_id ?? value.rating_id).sort(),
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
assertSupportedSchemaKeywords(schema);
assert.throws(() => assertSupportedSchemaKeywords({ type: ["string", "null"] }), /unsupported schema type/, "unsupported type arrays cannot silently diverge from Draft validation");
assert.throws(() => assertSupportedSchemaKeywords({ type: "number" }), /unsupported schema type/, "types the engine cannot execute fail meta-validation");
assert.throws(() => assertSupportedSchemaKeywords({ type: "string", format: "email" }), /unsupported schema format/, "unsupported formats cannot silently become no-ops");
assert.throws(() => assertSupportedSchemaKeywords({ type: "object", additionalProperties: { type: "string" } }), /schema-valued additionalProperties is unsupported/, "schema-valued additionalProperties cannot be ignored");
assert.throws(() => assertSupportedSchemaKeywords({ type: "array", items: [] }), /items must be a supported schema object\/boolean/, "invalid array-shaped items cannot silently bypass item validation");
assert.ok(validateNode({ type: "array", items: false }, ["forbidden"]).some((error) => error.includes("field is forbidden")), "boolean false item schemas execute rather than being skipped");
assert.throws(() => assertSupportedSchemaKeywords({ type: "object", properties: [] }), /properties must be a plain map/, "array-shaped properties cannot silently bypass property validation");
assert.throws(() => assertSupportedSchemaKeywords({ type: "object", required: "name" }), /required must be an array of unique strings/, "scalar required declarations fail meta-validation");
assert.throws(() => assertSupportedSchemaKeywords({ enum: { value: "x" } }), /enum must be a non-empty array/, "non-array enums fail meta-validation");
assert.throws(() => assertSupportedSchemaKeywords({ type: "string", pattern: 42 }), /pattern must be a string/, "non-string regex constraints fail meta-validation");
assert.throws(() => assertSupportedSchemaKeywords({ $ref: "https://example.invalid/schema.json" }), /only local #\/ schema refs are supported/, "external refs fail meta-validation because the dependency-free resolver cannot execute them");
assert.throws(() => assertSupportedSchemaKeywords({ $ref: "#/$defs/missingSchema" }), /unresolved local schema ref/, "missing local refs fail meta-validation before record validation");
assert.throws(() => assertSupportedSchemaKeywords({ $ref: "#/$defs/nonEmptyString", minLength: 2 }), /validation siblings beside \$ref are unsupported/, "$ref validation siblings cannot be skipped by the early-return engine");
assert.throws(() => assertSupportedSchemaKeywords({ oneOf: [{ type: "string" }], minLength: 2 }), /validation siblings beside oneOf are unsupported/, "oneOf validation siblings cannot be skipped by the early-return engine");
assert.ok(validateNode(schema.$defs.timestamp, "2026-02-30T00:00:00Z").some((error) => error.includes("invalid RFC 3339 UTC date-time")), "calendar-normalized impossible dates fail exact timestamp validation");
for (const vector of jcsConformanceVectors) assert.equal(canonical(vector.input), vector.expected, `${vector.name} must match RFC 8785 canonical bytes`);
for (const vector of rawFingerprintVectors) {
  assert.equal(vector.trimmed_utf8, vector.input_text.trim(), `${vector.name} records the exact ECMAScript String.trim result`);
  assert.equal(digest(vector.input_text.trim()), vector.expected_sha256, `${vector.name} must reproduce trim-utf8-sha256-v1`);
}
assert.deepEqual(["ä-policy", "z-policy", "Å-policy"].sort(compareUtf16CodeUnits), ["z-policy", "Å-policy", "ä-policy"], "policy ordering uses deterministic UTF-16 code units rather than locale collation");
assert.throws(() => canonical({ bad: "\ud800" }), /lone high surrogate/, "JCS source documents fail closed on non-I-JSON Unicode");
assert.deepEqual(schema.oneOf.map((entry) => entry.$ref), [
  "#/$defs/taskOutcomeRecord",
  "#/$defs/inferenceExposureRecord",
  "#/$defs/capabilityEvidenceRecord",
  "#/$defs/experimentObservationRecord",
  "#/$defs/qualityReceiptRecord",
  "#/$defs/experimentProductRatingRecord",
  "#/$defs/pipelineAccountingRecord",
]);
assert.deepEqual(Object.keys(schema["x-grimnir-conflict-keys"]), ["record", "task-outcome", "inference-exposure", "capability-evidence", "experiment-observation", "quality-receipt", "experiment-product-rating", "pipeline-accounting"]);
const ownerMap = schema["x-grimnir-field-owners"];
for (const requiredOwnerGroup of ["/tombstone/**", "/transport/hugin_request_stamp", "/transport/gateway_echo/echoed_request", "/transport/gateway_echo/gateway_request_id,/transport/gateway_echo/admission_id,/transport/gateway_echo/admitted_at,/transport/gateway_echo/authenticated_principal_id,/transport/gateway_echo/authentication,/transport/gateway_echo/principal_binding_digest,/transport/gateway_echo/capabilities", "/exposure/**", "/capability/**", "/experiment/**", "/quality_receipt/**", "/experiment_product_rating/**", "/pipeline_accounting/**", "/extensions/{producer.component}/**"]) {
  assert.equal(typeof ownerMap[requiredOwnerGroup], "string", `machine ownership map must cover ${requiredOwnerGroup}`);
}
assert.equal(sourceDocuments.size, sourceDocumentList.length, "source document refs must be unique");
assert.equal(validationContext.schema_version, "learning-task-validation-context/v1");
assert.equal(validationContext.fixture_only, true, "checked-in trust anchors are fixture-only, never production authority");
assert.equal(trustedEvidence.size, validationContext.trusted_evidence.length, "trusted validation evidence ids must be unique");
for (const evidence of validationContext.trusted_evidence) {
  assert.ok(["owner-authority", "hugin-task-attempt", "denominator-membership", "denominator-basis", "accounting-boundary", "ledger-partition"].includes(evidence.kind), `unknown trusted evidence kind ${evidence.kind}`);
  assert.equal(evidence.payload_digest.digest, digestCanonical(evidence.payload), `trusted evidence ${evidence.evidence_id} payload digest must verify`);
}
for (const source of sourceDocumentList) {
  assert.match(source.source_ref, /^source-doc:[a-z0-9][a-z0-9._/-]*$/);
  assert.equal(typeof source.source_version, "string");
  assert.ok(sourceDocumentRequiredKeys[source.source_type], `source document ${source.source_ref} has an unknown type`);
}
assert.equal(sourceDocumentList.some((source) => canonical(source).toLowerCase().includes("mellum")), false, "fixture positives must not masquerade as current Mellum serving truth");
assert.equal(sourceDocumentList.filter((source) => ["artifact-manifest", "effective-runtime-config", "effective-sampling-post-default-post-clamp"].includes(source.source_type)).every((source) => source.document.fixture_only === true && source.document.model_id === "fixture-model-v1"), true, "all admissible serving fixtures are explicitly synthetic");

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
const wrongConfigRole = structuredClone(positive[0]);
wrongConfigRole.execution.origin_config.prompt.config_digest = structuredClone(positive[0].execution.origin_config.harness.config_digest);
assert.ok(validateDataset([wrongConfigRole]).some((error) => error.includes("origin prompt config must bind a typed origin-prompt-config source document")), "a valid source document cannot be substituted into the wrong reproducibility role");
const wrongPromptStage = structuredClone(positive[0]);
wrongPromptStage.execution.prompt_identity.hugin_envelope = structuredClone(positive[0].execution.prompt_identity.gateway_canonical_envelope);
assert.ok(validateDataset([wrongPromptStage]).some((error) => error.includes("Hugin envelope source document must identify stage hugin-envelope")), "prompt-stage source documents cannot move between adjacent prompt stages");
const lifecycleFixture = positive[0];
assert.ok(Date.parse(lifecycleFixture.execution.started_at) <= Date.parse(lifecycleFixture.transport.hugin_request_stamp.stamped_at)
  && Date.parse(lifecycleFixture.transport.hugin_request_stamp.stamped_at) <= Date.parse(lifecycleFixture.transport.gateway_echo.admitted_at)
  && Date.parse(lifecycleFixture.transport.gateway_echo.admitted_at) <= Date.parse(lifecycleFixture.execution.model_started_at), "joined lifecycle is attempt-start <= request-stamp <= gateway-admission <= model-start");
assert.ok(Date.parse(lifecycleFixture.transport.hugin_request_stamp.preflight.response.advertised_at) < Date.parse(lifecycleFixture.execution.started_at), "a cached authenticated preflight may truthfully predate the attempt");
const preAttemptStamp = structuredClone(lifecycleFixture);
preAttemptStamp.transport.hugin_request_stamp.stamped_at = "2026-07-19T10:00:00.999Z";
preAttemptStamp.transport.gateway_echo.echoed_request = structuredClone(preAttemptStamp.transport.hugin_request_stamp);
preAttemptStamp.transport.gateway_echo.principal_binding_digest.digest = digestCanonical({ authenticated_principal_id: preAttemptStamp.transport.gateway_echo.authenticated_principal_id, request_stamp: preAttemptStamp.transport.hugin_request_stamp });
assert.ok(validateDataset([preAttemptStamp]).some((error) => error.includes("request stamp precedes attempt start")), "a request stamp cannot be backdated before its Hugin execution attempt");
const postRecordNonAdmissionStamp = structuredClone(nonAdmittedFixture.record);
postRecordNonAdmissionStamp.transport.hugin_request_stamp.stamped_at = "2026-07-19T10:01:01Z";
assert.ok(validateDataset([postRecordNonAdmissionStamp]).some((error) => error.includes("request stamp follows attempt end or record creation")), "an M5 non-admission stamp cannot be fabricated after attempt completion or record creation");
const subMillisecondReversal = structuredClone(lifecycleFixture);
subMillisecondReversal.execution.started_at = "2026-07-19T10:00:01.0002Z";
subMillisecondReversal.transport.hugin_request_stamp.stamped_at = "2026-07-19T10:00:01.0001Z";
assert.ok(validateDataset([subMillisecondReversal]).some((error) => error.includes("does not match") || error.includes("invalid RFC 3339")), "sub-millisecond reversed clocks fail closed because v1 permits only 0-3 fractional digits");
const wrongRawBytes = structuredClone(lifecycleFixture);
wrongRawBytes.task.raw_fingerprint.digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
wrongRawBytes.transport.hugin_request_stamp.raw_fingerprint = structuredClone(wrongRawBytes.task.raw_fingerprint);
wrongRawBytes.transport.gateway_echo.echoed_request = structuredClone(wrongRawBytes.transport.hugin_request_stamp);
wrongRawBytes.transport.gateway_echo.principal_binding_digest.digest = digestCanonical({ authenticated_principal_id: wrongRawBytes.transport.gateway_echo.authenticated_principal_id, request_stamp: wrongRawBytes.transport.hugin_request_stamp });
assert.ok(validateDataset([wrongRawBytes]).some((error) => error.includes("exact pre-orchestration raw input source")), "raw fingerprint is recomputed from the typed exact user/logical input, not trusted as a label");
const promptClaimOnly = structuredClone(lifecycleFixture);
const promptRef = promptClaimOnly.execution.prompt_identity.hugin_envelope.source_ref;
const savedPromptSource = sourceDocuments.get(promptRef);
const labelOnlySource = { ...structuredClone(savedPromptSource), document: { schema_version: "prompt-stage/v2", stage: "hugin-envelope", fixture_only: true, encoding: "utf-8", input_source_refs: savedPromptSource.document.input_source_refs, task_binding: lifecycleFixture.task.instance_id } };
sourceDocuments.set(promptRef, labelOnlySource);
const labelOnlyDigest = digestCanonical(labelOnlySource.document);
for (const claimValue of sourceDocumentClaims(promptClaimOnly)) if (claimValue.source_ref === promptRef) claimValue.digest = labelOnlyDigest;
promptClaimOnly.transport.gateway_echo.echoed_request = structuredClone(promptClaimOnly.transport.hugin_request_stamp);
promptClaimOnly.transport.gateway_echo.principal_binding_digest.digest = digestCanonical({ authenticated_principal_id: promptClaimOnly.transport.gateway_echo.authenticated_principal_id, request_stamp: promptClaimOnly.transport.hugin_request_stamp });
assert.ok(validateDataset([promptClaimOnly]).some((error) => error.includes("typed prompt-stage shape") || error.includes("exact ordered UTF-8 bytes")), "prompt aliases and stage labels alone cannot establish prompt provenance");
sourceDocuments.set(promptRef, savedPromptSource);
const mismatchedConfigWrapper = structuredClone(lifecycleFixture);
mismatchedConfigWrapper.execution.origin_config.prompt.id = "unbound-alias";
mismatchedConfigWrapper.transport.hugin_request_stamp.origin_config = structuredClone(mismatchedConfigWrapper.execution.origin_config);
mismatchedConfigWrapper.transport.gateway_echo.echoed_request = structuredClone(mismatchedConfigWrapper.transport.hugin_request_stamp);
mismatchedConfigWrapper.transport.gateway_echo.principal_binding_digest.digest = digestCanonical({ authenticated_principal_id: mismatchedConfigWrapper.transport.gateway_echo.authenticated_principal_id, request_stamp: mismatchedConfigWrapper.transport.hugin_request_stamp });
assert.ok(validateDataset([mismatchedConfigWrapper]).some((error) => error.includes("component/kind/id/version wrapper")), "config labels cannot drift from their typed source-document component/kind/id/version");
assert.equal(governanceEligibleAt(positive[0], nonM5Fixture.evaluationClock.post_expiry_at), false, "read-time expiry is checked against an explicit fixture clock");
let dynamicEvidenceOrdinal = 0;
function addTrustedFixtureEvidence(kind, issuer, payload) {
  dynamicEvidenceOrdinal += 1;
  const evidence = { evidence_id: `dynamic-fixture-evidence-${dynamicEvidenceOrdinal}`, kind, issuer, payload_digest: { algorithm: "sha256", version: "trusted-evidence-payload-jcs-v1", digest: digestCanonical(payload) }, payload };
  trustedEvidence.set(evidence.evidence_id, evidence);
  return { validation_context_id: validationContext.context_id, evidence_id: evidence.evidence_id, issuer, payload_digest: structuredClone(evidence.payload_digest) };
}
function installOwnerApproval(record) {
  for (const attestation of record.governance.policy_manifest.owner_attestations) {
    const policies = record.governance.policies.filter((policy) => policy.content_owner === attestation.content_owner).sort((a, b) => compareUtf16CodeUnits(a.subject_ref, b.subject_ref));
    const approval = { manifest: { manifest_id: record.governance.policy_manifest.manifest_id, version: record.governance.policy_manifest.version, approved_at: record.governance.policy_manifest.approved_at }, record_binding: { producer: record.producer.component, record_kind: record.record_kind, task: record.task }, policy_subset_digest: { algorithm: "sha256", version: "owner-policy-subset-jcs-v1", digest: digestCanonical(policies) } };
    const payload = { content_owner: attestation.content_owner, authenticated_principal: attestation.authenticated_principal, authentication: attestation.authentication, delegation: attestation.delegation, approvals: [approval] };
    attestation.authority_evidence = addTrustedFixtureEvidence("owner-authority", attestation.content_owner, payload);
  }
}
const noExpiryPolicy = structuredClone(positive[0]);
for (const policy of noExpiryPolicy.governance.policies) policy.retention.expires_at = { value: null, unknown_reason: "not-applicable" };
noExpiryPolicy.governance.effective.expires_at = { value: null, unknown_reason: "not-applicable" };
installOwnerApproval(noExpiryPolicy);
const noExpiryManifestRef = noExpiryPolicy.governance.policy_manifest.digest.source_ref;
const savedNoExpiryManifest = sourceDocuments.get(noExpiryManifestRef);
const noExpiryManifestDocument = {
  ...structuredClone(savedNoExpiryManifest.document),
  manifest: {
    manifest_id: noExpiryPolicy.governance.policy_manifest.manifest_id,
    version: noExpiryPolicy.governance.policy_manifest.version,
    approved_at: noExpiryPolicy.governance.policy_manifest.approved_at,
    owner_attestations: [...noExpiryPolicy.governance.policy_manifest.owner_attestations].sort((a, b) => compareUtf16CodeUnits(a.content_owner, b.content_owner)),
  },
  policies: [...noExpiryPolicy.governance.policies].sort((a, b) => compareUtf16CodeUnits(a.subject_ref, b.subject_ref)),
};
sourceDocuments.set(noExpiryManifestRef, { ...savedNoExpiryManifest, document: noExpiryManifestDocument });
noExpiryPolicy.governance.policy_manifest.digest.digest = digestCanonical(noExpiryManifestDocument);
assert.deepEqual(validateDataset([noExpiryPolicy]), [], "explicit no-expiry policy remains evaluation eligible");
sourceDocuments.set(noExpiryManifestRef, savedNoExpiryManifest);
const producerRewrittenPolicy = structuredClone(positive[0]);
producerRewrittenPolicy.governance.policies[0].allowed_uses = ["operations"];
const rewrittenManifestRef = producerRewrittenPolicy.governance.policy_manifest.digest.source_ref;
const savedRewrittenManifest = sourceDocuments.get(rewrittenManifestRef);
const rewrittenManifestDocument = { ...structuredClone(savedRewrittenManifest.document), policies: [...producerRewrittenPolicy.governance.policies].sort((a, b) => compareUtf16CodeUnits(a.subject_ref, b.subject_ref)) };
sourceDocuments.set(rewrittenManifestRef, { ...savedRewrittenManifest, document: rewrittenManifestDocument });
producerRewrittenPolicy.governance.policy_manifest.digest.digest = digestCanonical(rewrittenManifestDocument);
assert.ok(validateDataset([producerRewrittenPolicy]).some((error) => error.includes("does not bind the exact approved policy subset")), "a producer cannot rewrite owner policy and manifest content while reusing identity-only authority proof");
sourceDocuments.set(rewrittenManifestRef, savedRewrittenManifest);
const mixedExpiry = structuredClone(positive[0]);
for (const policy of mixedExpiry.governance.policies) policy.retention.expires_at = "2028-01-01T00:00:00Z";
mixedExpiry.governance.policies[0].retention.expires_at = "2027-01-01T00:00:00.900Z";
mixedExpiry.governance.policies[1].retention.expires_at = "2027-01-01T00:00:00Z";
mixedExpiry.governance.effective.expires_at = "2027-01-01T00:00:00Z";
installOwnerApproval(mixedExpiry);
const mixedExpiryManifestRef = mixedExpiry.governance.policy_manifest.digest.source_ref;
const savedMixedExpiryManifest = sourceDocuments.get(mixedExpiryManifestRef);
const mixedExpiryManifestDocument = { ...structuredClone(savedMixedExpiryManifest.document), manifest: { ...structuredClone(savedMixedExpiryManifest.document.manifest), owner_attestations: [...mixedExpiry.governance.policy_manifest.owner_attestations].sort((a, b) => compareUtf16CodeUnits(a.content_owner, b.content_owner)) }, policies: [...mixedExpiry.governance.policies].sort((a, b) => compareUtf16CodeUnits(a.subject_ref, b.subject_ref)) };
sourceDocuments.set(mixedExpiryManifestRef, { ...savedMixedExpiryManifest, document: mixedExpiryManifestDocument });
mixedExpiry.governance.policy_manifest.digest.digest = digestCanonical(mixedExpiryManifestDocument);
assert.deepEqual(validateDataset([mixedExpiry]), [], "earliest governance expiry is selected by instant, not lexicographic timestamp text");
const lexicographicExpiryBug = structuredClone(mixedExpiry);
lexicographicExpiryBug.governance.effective.expires_at = "2027-01-01T00:00:00.900Z";
assert.ok(validateDataset([lexicographicExpiryBug]).some((error) => error.includes("effective expires_at is not the earliest safe expiry")), "fractional RFC3339 timestamp cannot move the effective expiry later");
sourceDocuments.set(mixedExpiryManifestRef, savedMixedExpiryManifest);
const legacyUnknownPrincipal = structuredClone(positive[5]);
legacyUnknownPrincipal.task.source.principal = { value: null, unknown_reason: "legacy" };
assert.deepEqual(validateDataset([legacyUnknownPrincipal]), [], "qualified legacy source principal is policy-unavailable and evaluation-ineligible, not fabricated");
const crossAttemptNegativeExposure = structuredClone(positive[5]);
crossAttemptNegativeExposure.exposure.task_attempt_id = "candidate-attempt-other";
assert.ok(validateDataset([crossAttemptNegativeExposure]).some((error) => error.includes("immutable Hugin outcome/stamp/attempt")), "negative M5 coverage cannot be attached to another Hugin attempt");
const shiftedRelevantTask = structuredClone(positive[5]);
shiftedRelevantTask.exposure.coverage.relevant_task_at = "2026-07-19T12:00:02Z";
assert.ok(validateDataset([shiftedRelevantTask]).some((error) => error.includes("immutable Hugin outcome/stamp/attempt")), "negative coverage relevant_task_at is fixed by the trusted attempt proof");
assert.deepEqual(new Set(positive.map((record) => record.record_kind)), new Set(["task-outcome", "inference-exposure", "capability-evidence", "experiment-observation", "quality-receipt", "experiment-product-rating", "pipeline-accounting"]));
assert.equal(positive.some((record) => record.task?.origin_component === "gille-inference"), true, "positive fixtures must cover direct gateway origin");
const serviceSource = positive.find((record) => record.task?.source.principal?.scope === "service");
assert.ok(serviceSource, "positive fixtures must cover service-auth transport with separate content-owner authority");
assert.equal(serviceSource.task.source.content_owner.id, "principal:owner");
assert.equal(serviceSource.governance.policy_manifest.owner_attestations.some((attestation) => attestation.content_owner === "principal:owner" && attestation.authenticated_principal === "principal:owner"), true, "service source must carry real owner authorization");
const mismatchedOwnerAuthority = structuredClone(serviceSource);
mismatchedOwnerAuthority.task.source.content_owner.authority = "delegated-owner";
assert.ok(validateDataset([mismatchedOwnerAuthority]).some((error) => error.includes("source content-owner authority must match its verified owner-attestation mode")), "declared content-owner authority must match the verified attestation mode");
function replaceString(value, from, to) {
  if (Array.isArray(value)) return value.map((item) => replaceString(item, from, to));
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, replaceString(child, from, to)]));
  return value === from ? to : value;
}
const forgedOwner = replaceString(structuredClone(positive[0]), "principal:owner", "principal:forged");
const forgedAttestation = forgedOwner.governance.policy_manifest.owner_attestations[0];
const forgedPayload = { content_owner: forgedAttestation.content_owner, authenticated_principal: forgedAttestation.authenticated_principal, authentication: forgedAttestation.authentication, delegation: forgedAttestation.delegation };
forgedAttestation.authority_evidence.payload_digest.digest = digestCanonical(forgedPayload);
const forgedManifestRef = "source-doc:governance/forged-owner";
const oldForgedManifestRef = forgedOwner.governance.policy_manifest.digest.source_ref;
forgedOwner.governance.policy_manifest.digest.source_ref = forgedManifestRef;
forgedOwner.governance.policies.find((policy) => policy.subject_ref === oldForgedManifestRef).subject_ref = forgedManifestRef;
forgedOwner.governance.effective.derived_from_subject_refs = forgedOwner.governance.effective.derived_from_subject_refs.map((ref) => ref === oldForgedManifestRef ? forgedManifestRef : ref).sort(compareUtf16CodeUnits);
const forgedManifestDocument = { schema_version: "governance-policy-manifest/v1", contract: { contract_version: forgedOwner.contract_version, schema_revision: forgedOwner.schema_revision }, manifest: { manifest_id: forgedOwner.governance.policy_manifest.manifest_id, version: forgedOwner.governance.policy_manifest.version, approved_at: forgedOwner.governance.policy_manifest.approved_at, owner_attestations: forgedOwner.governance.policy_manifest.owner_attestations }, record_binding: { record_kind: forgedOwner.record_kind, producer: forgedOwner.producer.component, task: forgedOwner.task }, policies: [...forgedOwner.governance.policies].sort((a, b) => compareUtf16CodeUnits(a.subject_ref, b.subject_ref)) };
sourceDocuments.set(forgedManifestRef, { source_ref: forgedManifestRef, source_type: "governance-policy-manifest", source_version: "governance-policy-manifest-v1", document: forgedManifestDocument });
forgedOwner.governance.policy_manifest.digest.digest = digestCanonical(forgedManifestDocument);
assert.ok(validateDataset([forgedOwner]).some((error) => error.includes("absent from the trusted validation context")), "forged owner strings and a recomputed producer manifest digest do not authenticate authority");
sourceDocuments.delete(forgedManifestRef);
const inconsistentSourceClaim = structuredClone(positive[0]);
inconsistentSourceClaim.transport.hugin_request_stamp.hugin_envelope.digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
assert.ok(validateDataset([inconsistentSourceClaim]).some((error) => error.includes("inconsistent immutable source document claim")), "repeated source refs cannot overwrite inconsistent digest claims");
const notApplicable = () => ({ value: null, unknown_reason: "not-applicable" });
function boundaryEvidence(event, failureCode) {
  const kind = failureCode === "synthetic-test" ? "synthetic-declaration" : "compatibility-window";
  const boundary = { kind, declared_at: "2026-06-30T00:00:00Z", valid_from: "2026-07-01T00:00:00Z", valid_through: "2026-07-31T23:59:59.999Z" };
  const payload = { owner_component: event.owner_component, task_link: event.task_link, failure_code: failureCode, kind, declared_at: boundary.declared_at, valid_from: boundary.valid_from, valid_through: boundary.valid_through };
  return { ...boundary, proof: addTrustedFixtureEvidence("accounting-boundary", event.owner_component, payload) };
}
const accountingSeed = positive.find((record) => record.record_kind === "pipeline-accounting" && record.pipeline_accounting.event_type === "denominator-decision");
const accountingPositiveCases = [];
for (const failureCode of ["producer-error", "consumer-error", "schema-rejected", "join-mismatch", "late-over-24h", "policy-unavailable", "transport-auth-failed", "gateway-not-admitted", "transport-error"]) {
  const record = structuredClone(accountingSeed);
  record.pipeline_accounting.failure_code = failureCode;
  accountingPositiveCases.push(record);
}
for (const failureCode of ["candidate-governance-denied", "candidate-erased-or-expired", "candidate-exposure-incomplete", "candidate-provenance-incomplete", "candidate-product-quality-conflicted", "candidate-verifier-inadmissible", "candidate-duplicate-lineage"]) {
  const record = structuredClone(accountingSeed);
  record.pipeline_accounting.stage = "evaluation";
  record.pipeline_accounting.disposition = "excluded";
  record.pipeline_accounting.failure_code = failureCode;
  record.pipeline_accounting.related_record = { producer: "hugin", record_kind: "task-outcome", record_id: positive[0].record_id };
  record.pipeline_accounting.denominator = { counter: "evaluation-candidate-denominator", occurrence_at: "2026-07-19T10:00:04Z", occurrence_month_utc: "2026-07", decision: "excluded", boundary_evidence: notApplicable() };
  accountingPositiveCases.push(record);
}
const captureAdmitted = structuredClone(accountingSeed);
captureAdmitted.pipeline_accounting.stage = "capture";
captureAdmitted.pipeline_accounting.disposition = "admitted";
captureAdmitted.pipeline_accounting.failure_code = "not-applicable";
captureAdmitted.pipeline_accounting.related_record = { producer: "hugin", record_kind: "task-outcome", record_id: positive[0].record_id };
captureAdmitted.pipeline_accounting.denominator = { counter: "hugin-capture-denominator", occurrence_at: "2026-07-19T10:00:01Z", occurrence_month_utc: "2026-07", decision: "admitted", boundary_evidence: notApplicable() };
accountingPositiveCases.push(captureAdmitted);
const directFailure = structuredClone(accountingSeed);
directFailure.producer.component = "gille-inference";
directFailure.pipeline_accounting.owner_component = "gille-inference";
directFailure.pipeline_accounting.stage = "direct-exposure";
directFailure.pipeline_accounting.failure_code = "transport-error";
directFailure.pipeline_accounting.task_link.origin_component = "gille-inference";
directFailure.pipeline_accounting.denominator = { counter: "direct-m5-exposure-denominator", occurrence_at: "2026-07-19T10:00:01Z", occurrence_month_utc: "2026-07", decision: "failed", boundary_evidence: notApplicable() };
directFailure.extensions = { "gille-inference": {} };
accountingPositiveCases.push(directFailure);
for (const [stage, failureCode, counter, owner, origin] of [
  ["capture", "synthetic-test", "hugin-capture-denominator", "hugin", "hugin"],
  ["capture", "pre-v1-migration", "hugin-capture-denominator", "hugin", "hugin"],
  ["direct-exposure", "synthetic-test", "direct-m5-exposure-denominator", "gille-inference", "gille-inference"],
  ["direct-exposure", "pre-v1-migration", "direct-m5-exposure-denominator", "gille-inference", "gille-inference"],
  ["join", "not-m5-routed", "hugin-m5-join-denominator", "hugin", "hugin"],
  ["join", "pre-v1-migration", "hugin-m5-join-denominator", "hugin", "hugin"],
]) {
  const record = structuredClone(accountingSeed);
  record.producer.component = owner;
  record.pipeline_accounting.owner_component = owner;
  record.pipeline_accounting.stage = stage;
  record.pipeline_accounting.disposition = "excluded";
  record.pipeline_accounting.failure_code = failureCode;
  record.pipeline_accounting.task_link.origin_component = origin;
  record.pipeline_accounting.related_record = { value: null, unknown_reason: "not-applicable" };
  if (failureCode === "not-m5-routed") {
    record.pipeline_accounting.task_link.request_id = { value: null, unknown_reason: "not-applicable" };
    record.pipeline_accounting.task_link.idempotency_key = { value: null, unknown_reason: "not-applicable" };
  }
  record.pipeline_accounting.denominator = { counter, occurrence_at: "2026-07-19T10:00:01Z", occurrence_month_utc: "2026-07", decision: "excluded", boundary_evidence: notApplicable() };
  if (["synthetic-test", "pre-v1-migration"].includes(failureCode)) record.pipeline_accounting.denominator.boundary_evidence = boundaryEvidence(record.pipeline_accounting, failureCode);
  record.extensions = { [owner]: {} };
  accountingPositiveCases.push(record);
}
for (const record of accountingPositiveCases) assert.deepEqual(validateDataset([record]), [], `pipeline accounting must represent ${record.pipeline_accounting.failure_code}`);
const lateSyntheticDeclaration = structuredClone(accountingPositiveCases.find((record) => record.pipeline_accounting.failure_code === "synthetic-test"));
lateSyntheticDeclaration.pipeline_accounting.denominator.boundary_evidence.declared_at = "2026-07-19T10:00:02Z";
assert.ok(validateDataset([lateSyntheticDeclaration]).some((error) => error.includes("not declared by the owner before occurrence")), "synthetic-test exclusion cannot be declared after occurrence/dispatch");
const wrongIssuerBoundary = structuredClone(accountingPositiveCases.find((record) => record.pipeline_accounting.failure_code === "synthetic-test"));
const wrongBoundary = wrongIssuerBoundary.pipeline_accounting.denominator.boundary_evidence;
const wrongBoundaryPayload = { owner_component: wrongIssuerBoundary.pipeline_accounting.owner_component, task_link: wrongIssuerBoundary.pipeline_accounting.task_link, failure_code: wrongIssuerBoundary.pipeline_accounting.failure_code, kind: wrongBoundary.kind, declared_at: wrongBoundary.declared_at, valid_from: wrongBoundary.valid_from, valid_through: wrongBoundary.valid_through };
wrongBoundary.proof = addTrustedFixtureEvidence("accounting-boundary", "service:attacker", wrongBoundaryPayload);
assert.ok(validateDataset([wrongIssuerBoundary]).some((error) => error.includes("not declared by the owner before occurrence")), "boundary payload owner text cannot substitute for proof issued by the accounting owner");
const outsideCompatibilityWindow = structuredClone(accountingPositiveCases.find((record) => record.pipeline_accounting.failure_code === "pre-v1-migration"));
outsideCompatibilityWindow.pipeline_accounting.denominator.occurrence_at = "2026-08-01T00:00:00Z";
outsideCompatibilityWindow.pipeline_accounting.denominator.occurrence_month_utc = "2026-08";
outsideCompatibilityWindow.pipeline_accounting.observed_at = "2026-08-01T00:00:01Z";
outsideCompatibilityWindow.recorded_at = "2026-08-01T00:00:02Z";
assert.ok(validateDataset([outsideCompatibilityWindow]).some((error) => error.includes("inside its trusted window")), "pre-v1-migration exclusion requires occurrence inside the predeclared compatibility window");
const notM5BoundaryDecision = accountingPositiveCases.find((record) => record.pipeline_accounting.failure_code === "not-m5-routed");
assert.deepEqual(validateDataset([nonM5Fixture.record, notM5BoundaryDecision]), [], "not-m5-routed is a truthful join exclusion with no dispatched request identity");
assert.ok(validateDataset([positive[0], notM5BoundaryDecision]).includes("not-m5-routed join exclusion does not match the authoritative macro route"), "not-m5-routed cannot contradict an M5 macro route");
assert.deepEqual(validateDataset([positive[0], captureAdmitted]), [], "capture admission binds the exact Hugin task-outcome record");
const admittedJoin = structuredClone(accountingSeed);
admittedJoin.pipeline_accounting.disposition = "admitted";
admittedJoin.pipeline_accounting.failure_code = "not-applicable";
admittedJoin.pipeline_accounting.related_record = { producer: "gille-inference", record_kind: "inference-exposure", record_id: positive[4].record_id };
admittedJoin.pipeline_accounting.denominator.decision = "admitted";
assert.deepEqual(validateDataset([positive[0], positive[4], admittedJoin]), [], "join admission binds the exact gille inference-exposure record");
const admittedWithoutRecord = structuredClone(admittedJoin);
admittedWithoutRecord.pipeline_accounting.related_record = { value: null, unknown_reason: "producer-error" };
assert.ok(validateDataset([admittedWithoutRecord]).some((error) => error.includes("join admission must bind its expected immutable learning record")), "admitted join coverage cannot exist without a learning record identity");
const incoherentEvaluationBoundary = structuredClone(accountingPositiveCases.find((record) => record.pipeline_accounting.stage === "evaluation"));
incoherentEvaluationBoundary.pipeline_accounting.failure_code = "synthetic-test";
assert.ok(validateDataset([incoherentEvaluationBoundary]).some((error) => error.includes("evaluation exclusion requires its closed boundary code")), "evaluation exclusions cannot use capture boundary codes");
const wrongOccurrenceMonth = structuredClone(accountingSeed);
wrongOccurrenceMonth.pipeline_accounting.denominator.occurrence_month_utc = "2026-08";
assert.ok(validateDataset([wrongOccurrenceMonth]).some((error) => error.includes("occurrence month must derive from occurrence_at")), "denominator membership month is derived from occurrence_at");
const wrongAuthoritativeOccurrence = structuredClone(accountingSeed);
wrongAuthoritativeOccurrence.pipeline_accounting.denominator.occurrence_at = "2026-07-19T10:00:02Z";
assert.ok(validateDataset([positive[0], wrongAuthoritativeOccurrence]).includes("join denominator occurrence_at does not match authoritative execution.started_at"), "joined accounting binds the authoritative attempt start");
const secondCounterDecision = structuredClone(captureAdmitted);
secondCounterDecision.record_id = "opaque:40404040-4040-4040-8040-404040404040";
secondCounterDecision.pipeline_accounting.event_id = "opaque:41414141-4141-4141-8141-414141414141";
assert.deepEqual(validateDataset([accountingSeed, secondCounterDecision]), [], "different counters may admit one linked task without a natural-key collision");

const requestRetry = structuredClone(accountingSeed);
requestRetry.record_id = "opaque:20202020-2020-4020-8020-202020202020";
requestRetry.pipeline_accounting.event_id = "opaque:21212121-2121-4121-8121-212121212121";
requestRetry.pipeline_accounting.event_type = "request-retry";
requestRetry.pipeline_accounting.stage = "request-transport";
requestRetry.pipeline_accounting.disposition = "retry";
requestRetry.pipeline_accounting.failure_code = "transport-error";
requestRetry.pipeline_accounting.related_record = { value: null, unknown_reason: "not-applicable" };
requestRetry.pipeline_accounting.retry = { kind: "request-transport", ordinal: 2, replayed_identity_digest: { algorithm: "sha256", version: "request-stamp-jcs-v1", digest: digestCanonical(positive[0].transport.hugin_request_stamp) } };
requestRetry.pipeline_accounting.denominator = { value: null, unknown_reason: "not-applicable" };
assert.deepEqual(validateDataset([positive[0], requestRetry]), [], "request retry is a separate immutable accounting event replaying the exact stamp");
const badRequestRetry = structuredClone(requestRetry);
badRequestRetry.pipeline_accounting.retry.replayed_identity_digest.digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
assert.ok(validateDataset([positive[0], badRequestRetry]).includes("request retry does not replay the identical immutable request stamp"), "request retry identity drift fails closed");
const badRequestRetryVersion = structuredClone(requestRetry);
badRequestRetryVersion.pipeline_accounting.retry.replayed_identity_digest.version = "record-ref-jcs-v1";
assert.ok(validateDataset([badRequestRetryVersion]).includes("request retry digest version must be request-stamp-jcs-v1"), "request retry digest semantics are version-pinned");

const deliveryRetry = structuredClone(positive.find((record) => record.record_kind === "pipeline-accounting" && record.pipeline_accounting.event_type === "record-emission"));
deliveryRetry.record_id = "opaque:22222222-2020-4020-8020-202020202020";
deliveryRetry.pipeline_accounting.event_id = "opaque:23232323-2323-4323-8323-232323232323";
deliveryRetry.pipeline_accounting.event_type = "record-delivery-retry";
deliveryRetry.pipeline_accounting.disposition = "retry";
deliveryRetry.pipeline_accounting.failure_code = "record-delivery-failed";
deliveryRetry.pipeline_accounting.delivery_ordinal = 2;
deliveryRetry.pipeline_accounting.retry = { kind: "record-delivery", ordinal: 2, replayed_identity_digest: { algorithm: "sha256", version: "record-ref-jcs-v1", digest: digestCanonical(deliveryRetry.pipeline_accounting.related_record) } };
assert.deepEqual(validateDataset([deliveryRetry]), [], "record-delivery retry is separate accounting and does not imply another model run");
const secondRecordRetry = structuredClone(deliveryRetry);
secondRecordRetry.record_id = "opaque:29292929-2929-4929-8929-292929292929";
secondRecordRetry.pipeline_accounting.event_id = "opaque:30303030-3030-4030-8030-303030303030";
secondRecordRetry.pipeline_accounting.related_record.record_id = "opaque:31313131-3131-4131-8131-313131313131";
secondRecordRetry.pipeline_accounting.retry.replayed_identity_digest.digest = digestCanonical(secondRecordRetry.pipeline_accounting.related_record);
assert.deepEqual(validateDataset([deliveryRetry, secondRecordRetry]), [], "two records from one task may each have delivery retry ordinal two");
const duplicateRecordRetry = structuredClone(deliveryRetry);
duplicateRecordRetry.record_id = "opaque:32323232-3232-4232-8232-323232323232";
duplicateRecordRetry.pipeline_accounting.event_id = "opaque:33333333-3333-4333-8333-333333333333";
assert.ok(validateDataset([deliveryRetry, duplicateRecordRetry]).some((error) => error.includes("record-delivery-retry") && error.includes("one effective leaf")), "one record delivery attempt cannot fork into duplicate retry events");
const badDeliveryRetryVersion = structuredClone(deliveryRetry);
badDeliveryRetryVersion.pipeline_accounting.retry.replayed_identity_digest.version = "request-stamp-jcs-v1";
assert.ok(validateDataset([badDeliveryRetryVersion]).includes("record-delivery retry digest version must be record-ref-jcs-v1"), "delivery retry digest semantics are version-pinned");

const initialDeliveryFailure = structuredClone(positive.find((record) => record.record_kind === "pipeline-accounting" && record.pipeline_accounting.event_type === "record-emission"));
initialDeliveryFailure.record_id = "opaque:34343434-3434-4434-8434-343434343434";
initialDeliveryFailure.pipeline_accounting.event_id = "opaque:35353535-3535-4535-8535-353535353535";
initialDeliveryFailure.pipeline_accounting.disposition = "failed";
initialDeliveryFailure.pipeline_accounting.failure_code = "record-delivery-failed";
const retriedDeliverySuccess = structuredClone(initialDeliveryFailure);
retriedDeliverySuccess.record_id = "opaque:36363636-3636-4636-8636-363636363636";
retriedDeliverySuccess.pipeline_accounting.event_id = "opaque:37373737-3737-4737-8737-373737373737";
retriedDeliverySuccess.pipeline_accounting.delivery_ordinal = 2;
retriedDeliverySuccess.pipeline_accounting.disposition = "succeeded";
retriedDeliverySuccess.pipeline_accounting.failure_code = "not-applicable";
assert.deepEqual(validateDataset([initialDeliveryFailure, deliveryRetry, retriedDeliverySuccess]), [], "a retry outcome appends at a new delivery ordinal without mutating the initial failure");
const duplicateDeliveryOutcome = structuredClone(retriedDeliverySuccess);
duplicateDeliveryOutcome.record_id = "opaque:38383838-3838-4838-8838-383838383838";
duplicateDeliveryOutcome.pipeline_accounting.event_id = "opaque:39393939-3939-4939-8939-393939393939";
assert.ok(validateDataset([retriedDeliverySuccess, duplicateDeliveryOutcome]).some((error) => error.includes("record-emission") && error.includes("one effective leaf")), "one delivery attempt cannot fork into duplicate outcomes");

const aggregateClose = structuredClone(accountingSeed);
aggregateClose.record_id = "opaque:24242424-2424-4424-8424-242424242424";
aggregateClose.recorded_at = "2026-07-01T00:00:02Z";
aggregateClose.pipeline_accounting = {
  event_id: "opaque:25252525-2525-4525-8525-252525252525",
  owner_component: "hugin",
  event_type: "aggregate-close",
  stage: "aggregate",
  disposition: "succeeded",
  failure_code: "not-applicable",
  observed_at: "2026-07-01T00:00:01Z",
  task_link: { origin_component: { value: null, unknown_reason: "not-applicable" }, task_instance_id: { value: null, unknown_reason: "not-applicable" }, attempt_id: { value: null, unknown_reason: "not-applicable" }, request_id: { value: null, unknown_reason: "not-applicable" }, idempotency_key: { value: null, unknown_reason: "not-applicable" } },
  related_record: { value: null, unknown_reason: "not-applicable" },
  delivery_ordinal: { value: null, unknown_reason: "not-applicable" },
  retry: { value: null, unknown_reason: "not-applicable" },
  denominator: { value: null, unknown_reason: "not-applicable" },
  evaluation_bundle: { value: null, unknown_reason: "not-applicable" },
  aggregate_close: { counter: "hugin-m5-join-denominator", period_utc: "2026-06", included_through: "2026-07-01T00:00:00Z", event_count: 42, immutable_event_set_digest: { algorithm: "sha256", version: "pipeline-event-set-jcs-v1", digest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, verification_scope: "partial-dataset-deferred", partition_proof: { value: null, unknown_reason: "not-applicable" }, closed_at: "2026-07-01T00:00:01Z" },
};
assert.deepEqual(validateDataset([aggregateClose]), [], "closed-period aggregates are immutable snapshots over event sets");
const correctedDenominator = structuredClone(accountingSeed);
correctedDenominator.record_id = "opaque:42424242-4242-4242-8242-424242424242";
correctedDenominator.recorded_at = "2026-07-19T10:00:06Z";
correctedDenominator.pipeline_accounting.event_id = "opaque:43434343-4343-4343-8343-434343434343";
correctedDenominator.pipeline_accounting.failure_code = "consumer-error";
correctedDenominator.lineage.correction_targets = [{ producer: "hugin", record_kind: "pipeline-accounting", fact_domain: "pipeline-accounting", record_id: accountingSeed.record_id }];
correctedDenominator.lineage.correction_ref = "mimir:correction/pipeline-denominator-001";
assert.deepEqual(validateDataset([accountingSeed, correctedDenominator]), [], "a denominator correction forms one explicit same-natural-key supersession chain");
const unlinkedDenominatorDuplicate = structuredClone(correctedDenominator);
unlinkedDenominatorDuplicate.lineage.correction_targets = [];
unlinkedDenominatorDuplicate.lineage.correction_ref = { value: null, unknown_reason: "not-applicable" };
assert.ok(validateDataset([accountingSeed, unlinkedDenominatorDuplicate]).some((error) => error.includes("denominator-decision") && error.includes("one effective leaf")), "a random event id cannot duplicate a denominator decision natural key");
const alternateRequestDuplicate = structuredClone(unlinkedDenominatorDuplicate);
alternateRequestDuplicate.pipeline_accounting.task_link.request_id = "opaque:50505050-5050-4050-8050-505050505050";
alternateRequestDuplicate.pipeline_accounting.task_link.idempotency_key = "opaque:51515151-5151-4151-8151-515151515151";
assert.ok(validateDataset([accountingSeed, alternateRequestDuplicate]).some((error) => error.includes("denominator-decision") && error.includes("one effective leaf")), "a second request id cannot create another denominator member for one attempt");
const denominatorFork = structuredClone(correctedDenominator);
denominatorFork.record_id = "opaque:44444444-4444-4444-8444-444444444445";
denominatorFork.pipeline_accounting.event_id = "opaque:45454545-4545-4545-8545-454545454545";
assert.ok(validateDataset([accountingSeed, correctedDenominator, denominatorFork]).some((error) => error.includes("cannot fork")), "denominator corrections cannot fork");

const verifiedAggregateClose = structuredClone(aggregateClose);
verifiedAggregateClose.record_id = "opaque:46464646-4646-4646-8646-464646464646";
verifiedAggregateClose.recorded_at = "2026-08-01T00:00:02Z";
verifiedAggregateClose.pipeline_accounting.event_id = "opaque:47474747-4747-4747-8747-474747474747";
verifiedAggregateClose.pipeline_accounting.observed_at = "2026-08-01T00:00:01Z";
verifiedAggregateClose.pipeline_accounting.aggregate_close = {
  counter: "hugin-m5-join-denominator",
  period_utc: "2026-07",
  included_through: "2026-08-01T00:00:00Z",
  event_count: 1,
  immutable_event_set_digest: { algorithm: "sha256", version: "pipeline-event-set-jcs-v1", digest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
  verification_scope: "full-period-partition",
  partition_proof: { value: null, unknown_reason: "not-applicable" },
  closed_at: "2026-08-01T00:00:01Z",
};
verifiedAggregateClose.pipeline_accounting.aggregate_close.immutable_event_set_digest.digest = digestCanonical(aggregateDigestPayload(verifiedAggregateClose, [correctedDenominator]));
function installPartitionProof(closeRecord, decisions) {
  const close = closeRecord.pipeline_accounting.aggregate_close;
  const entries = decisions.map((candidate) => ({ natural_key: denominatorNaturalKey(candidate.pipeline_accounting), event_id: candidate.pipeline_accounting.event_id })).sort((left, right) => compareUtf16CodeUnits(left.natural_key, right.natural_key) || compareUtf16CodeUnits(left.event_id, right.event_id));
  close.partition_proof = addTrustedFixtureEvidence("ledger-partition", closeRecord.pipeline_accounting.owner_component, { partition_id: `fixture:${close.counter}:${close.period_utc}:${close.closed_at}`, owner_component: closeRecord.pipeline_accounting.owner_component, counter: close.counter, period_utc: close.period_utc, included_through: close.included_through, high_water_event_id: entries.at(-1)?.event_id ?? "certified-empty-at-boundary", decisions: entries });
}
installPartitionProof(verifiedAggregateClose, [correctedDenominator]);
assert.deepEqual(validateDataset([accountingSeed, correctedDenominator, verifiedAggregateClose]), [], "full aggregate close hashes only the unique effective denominator leaf");
assert.ok(validateDataset([verifiedAggregateClose]).some((error) => error.includes("authoritative ledger partition/high-water proof")), "an empty loaded set cannot satisfy a trusted proof that contains a denominator decision");
const certifiedZeroAggregate = structuredClone(verifiedAggregateClose);
certifiedZeroAggregate.record_id = "opaque:70707070-7070-4070-8070-707070707070";
certifiedZeroAggregate.pipeline_accounting.event_id = "opaque:71717171-7171-4171-8171-717171717171";
certifiedZeroAggregate.pipeline_accounting.aggregate_close.event_count = 0;
certifiedZeroAggregate.pipeline_accounting.aggregate_close.immutable_event_set_digest.digest = digestCanonical(aggregateDigestPayload(certifiedZeroAggregate, []));
installPartitionProof(certifiedZeroAggregate, []);
assert.deepEqual(validateDataset([certifiedZeroAggregate]), [], "a trusted authoritative high-water proof can certify a legitimately zero-event month");
const untrustedZeroAggregate = structuredClone(certifiedZeroAggregate);
untrustedZeroAggregate.pipeline_accounting.aggregate_close.partition_proof.evidence_id = "producer-self-asserted-empty-partition";
assert.ok(validateDataset([untrustedZeroAggregate]).some((error) => error.includes("authoritative ledger partition/high-water proof")), "a self-asserted empty partition cannot certify a zero-event month");
const selfAssertedAggregate = structuredClone(verifiedAggregateClose);
selfAssertedAggregate.pipeline_accounting.aggregate_close.partition_proof.evidence_id = "producer-self-asserted-partition";
assert.ok(validateDataset([accountingSeed, correctedDenominator, selfAssertedAggregate]).some((error) => error.includes("authoritative ledger partition/high-water proof")), "a producer-authored full-period label is not an authoritative ledger partition proof");
const wrongIssuerAggregate = structuredClone(verifiedAggregateClose);
const trustedPartitionPayload = structuredClone(trustedEvidence.get(verifiedAggregateClose.pipeline_accounting.aggregate_close.partition_proof.evidence_id).payload);
wrongIssuerAggregate.pipeline_accounting.aggregate_close.partition_proof = addTrustedFixtureEvidence("ledger-partition", "service:attacker", trustedPartitionPayload);
assert.ok(validateDataset([accountingSeed, correctedDenominator, wrongIssuerAggregate]).some((error) => error.includes("authoritative ledger partition/high-water proof")), "trusted partition content must still be issued by the counter owner");
const wrongAggregateCount = structuredClone(verifiedAggregateClose);
wrongAggregateCount.pipeline_accounting.aggregate_close.event_count = 2;
assert.ok(validateDataset([accountingSeed, correctedDenominator, wrongAggregateCount]).includes("aggregate close event_count does not match the loaded full period partition"), "aggregate event count is mechanically verified");
const wrongAggregateDigest = structuredClone(verifiedAggregateClose);
wrongAggregateDigest.pipeline_accounting.aggregate_close.immutable_event_set_digest.digest = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
assert.ok(validateDataset([accountingSeed, correctedDenominator, wrongAggregateDigest]).includes("aggregate close digest does not bind its loaded full period partition"), "aggregate event-set digest is mechanically verified");
const deferredWithConstituents = structuredClone(verifiedAggregateClose);
deferredWithConstituents.pipeline_accounting.aggregate_close.verification_scope = "partial-dataset-deferred";
deferredWithConstituents.pipeline_accounting.aggregate_close.partition_proof = notApplicable();
assert.deepEqual(validateDataset([accountingSeed, correctedDenominator, deferredWithConstituents]), [], "partial dataset aggregate remains explicitly deferred and never certified");
const correctedAggregateClose = structuredClone(verifiedAggregateClose);
correctedAggregateClose.record_id = "opaque:48484848-4848-4848-8848-484848484848";
correctedAggregateClose.recorded_at = "2026-08-01T00:00:03Z";
correctedAggregateClose.pipeline_accounting.event_id = "opaque:49494949-4949-4949-8949-494949494949";
correctedAggregateClose.lineage.correction_targets = [{ producer: "hugin", record_kind: "pipeline-accounting", fact_domain: "pipeline-accounting", record_id: verifiedAggregateClose.record_id }];
correctedAggregateClose.lineage.correction_ref = "mimir:correction/aggregate-close-001";
assert.deepEqual(validateDataset([accountingSeed, correctedDenominator, verifiedAggregateClose, correctedAggregateClose]), [], "a late aggregate re-close is an explicit same-key supersession with one effective snapshot");
const unlinkedAggregateClose = structuredClone(correctedAggregateClose);
unlinkedAggregateClose.lineage.correction_targets = [];
unlinkedAggregateClose.lineage.correction_ref = { value: null, unknown_reason: "not-applicable" };
assert.ok(validateDataset([accountingSeed, correctedDenominator, verifiedAggregateClose, unlinkedAggregateClose]).some((error) => error.includes("aggregate-close") && error.includes("one effective leaf")), "unlinked duplicate aggregate closes fail closed");
const tooEarlyAggregateCutoff = structuredClone(aggregateClose);
tooEarlyAggregateCutoff.pipeline_accounting.aggregate_close.included_through = "2026-06-30T23:59:59.999Z";
assert.ok(validateDataset([tooEarlyAggregateCutoff]).some((error) => error.includes("included_through must reach the next UTC month boundary")), "period close uses a complete half-open UTC month boundary");

const preCorrectionClose = structuredClone(verifiedAggregateClose);
preCorrectionClose.pipeline_accounting.aggregate_close.immutable_event_set_digest.digest = digestCanonical(aggregateDigestPayload(preCorrectionClose, [accountingSeed]));
installPartitionProof(preCorrectionClose, [accountingSeed]);
const postCloseDenominatorCorrection = structuredClone(correctedDenominator);
postCloseDenominatorCorrection.recorded_at = "2026-08-01T00:00:05Z";
const postCorrectionReclose = structuredClone(preCorrectionClose);
postCorrectionReclose.record_id = "opaque:52525252-5252-4252-8252-525252525252";
postCorrectionReclose.recorded_at = "2026-08-01T00:00:07Z";
postCorrectionReclose.pipeline_accounting.event_id = "opaque:53535353-5353-4353-8353-535353535353";
postCorrectionReclose.pipeline_accounting.observed_at = "2026-08-01T00:00:06Z";
postCorrectionReclose.pipeline_accounting.aggregate_close.closed_at = "2026-08-01T00:00:06Z";
postCorrectionReclose.lineage.correction_targets = [{ producer: "hugin", record_kind: "pipeline-accounting", fact_domain: "pipeline-accounting", record_id: preCorrectionClose.record_id }];
postCorrectionReclose.lineage.correction_ref = "mimir:correction/aggregate-close-as-of-001";
postCorrectionReclose.pipeline_accounting.aggregate_close.immutable_event_set_digest.digest = digestCanonical(aggregateDigestPayload(postCorrectionReclose, [postCloseDenominatorCorrection]));
installPartitionProof(postCorrectionReclose, [postCloseDenominatorCorrection]);
assert.deepEqual(validateDataset([accountingSeed, preCorrectionClose, postCloseDenominatorCorrection, postCorrectionReclose]), [], "an old close keeps its as-of leaf while an explicit re-close incorporates a later denominator correction");

const deliberateExecution = structuredClone(positive[0]);
deliberateExecution.record_id = "opaque:26262626-2626-4626-8626-262626262626";
deliberateExecution.execution.attempt_id = "attempt-2";
deliberateExecution.transport.hugin_request_stamp.attempt_id = "attempt-2";
deliberateExecution.transport.hugin_request_stamp.request_id = "opaque:27272727-2727-4727-8727-272727272727";
deliberateExecution.transport.hugin_request_stamp.idempotency_key = "opaque:28282828-2828-4828-8828-282828282828";
deliberateExecution.transport.gateway_echo.echoed_request = structuredClone(deliberateExecution.transport.hugin_request_stamp);
deliberateExecution.transport.gateway_echo.principal_binding_digest.digest = digestCanonical({ authenticated_principal_id: deliberateExecution.transport.gateway_echo.authenticated_principal_id, request_stamp: deliberateExecution.transport.hugin_request_stamp });
assert.deepEqual(validateDataset([positive[0], deliberateExecution]), [], "deliberate new model execution uses new attempt, request, and idempotency identities");
const reusedExecutionIdentity = structuredClone(deliberateExecution);
reusedExecutionIdentity.transport.hugin_request_stamp.idempotency_key = positive[0].transport.hugin_request_stamp.idempotency_key;
reusedExecutionIdentity.transport.gateway_echo.echoed_request = structuredClone(reusedExecutionIdentity.transport.hugin_request_stamp);
reusedExecutionIdentity.transport.gateway_echo.principal_binding_digest.digest = digestCanonical({ authenticated_principal_id: reusedExecutionIdentity.transport.gateway_echo.authenticated_principal_id, request_stamp: reusedExecutionIdentity.transport.hugin_request_stamp });
assert.ok(validateDataset([positive[0], reusedExecutionIdentity]).includes("idempotency key was reused for a different task/attempt/model execution"), "new execution cannot reuse request idempotency identity");
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
assert.equal(Object.hasOwn(joinedOutcome.transport, "record_delivery_attempt"), false, "mutable delivery attempts never enter immutable learning evidence");

const joinedQuality = positive.find((record) => record.record_kind === "quality-receipt");
function buildEvaluationBundle(outcome, exposure, capability, qualities, decisionAt) {
  const payloads = evaluationBundlePayloads(outcome, exposure, capability, qualities, decisionAt);
  const stamp = (version, payload) => ({ algorithm: "sha256", version, digest: digestCanonical(payload) });
  return {
    bundle_id: "opaque:60606060-6060-4060-8060-606060606060",
    decision_at: decisionAt,
    task_outcome: evidenceRef(outcome),
    exposure: evidenceRef(exposure),
    capability_evidence: evidenceRef(capability),
    quality_receipts: qualities.map(evidenceRef),
    governance_snapshot_digest: stamp("evaluation-governance-jcs-v1", payloads.governance),
    complete_provenance_digest: stamp("evaluation-provenance-jcs-v1", payloads.provenance),
    exposure_coverage_digest: stamp("evaluation-exposure-jcs-v1", payloads.exposure),
    quality_consensus_digest: stamp("evaluation-quality-jcs-v1", payloads.quality),
    unique_lineage_digest: stamp("evaluation-lineage-jcs-v1", payloads.lineage),
  };
}
const evaluationAdmitted = structuredClone(accountingSeed);
evaluationAdmitted.record_id = "opaque:61616161-6161-4161-8161-616161616161";
evaluationAdmitted.recorded_at = "2026-07-19T10:02:02Z";
evaluationAdmitted.pipeline_accounting.event_id = "opaque:62626262-6262-4262-8262-626262626262";
evaluationAdmitted.pipeline_accounting.stage = "evaluation";
evaluationAdmitted.pipeline_accounting.disposition = "admitted";
evaluationAdmitted.pipeline_accounting.failure_code = "not-applicable";
evaluationAdmitted.pipeline_accounting.observed_at = "2026-07-19T10:02:01.500Z";
evaluationAdmitted.pipeline_accounting.related_record = evidenceRef(joinedOutcome);
evaluationAdmitted.pipeline_accounting.denominator = { counter: "evaluation-candidate-denominator", occurrence_at: "2026-07-19T10:02:01Z", occurrence_month_utc: "2026-07", decision: "admitted", boundary_evidence: notApplicable() };
evaluationAdmitted.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [joinedQuality], "2026-07-19T10:02:01Z");
assert.deepEqual(validateDataset([joinedOutcome, joinedExposure, joinedCapability, joinedQuality, evaluationAdmitted]), [], "evaluation admission succeeds only with the complete joined candidate evidence bundle loaded");
const prematureEvaluation = structuredClone(evaluationAdmitted);
prematureEvaluation.pipeline_accounting.observed_at = "2026-07-19T10:00:59Z";
prematureEvaluation.pipeline_accounting.denominator.occurrence_at = "2026-07-19T10:00:59Z";
prematureEvaluation.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [joinedQuality], "2026-07-19T10:00:59Z");
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, joinedQuality, prematureEvaluation]).some((error) => error.includes("evidence that was not available at decision time")), "evaluation cannot predate its loaded outcome, exposure, capability, or quality evidence");
const incoherentEvaluationClock = structuredClone(evaluationAdmitted);
incoherentEvaluationClock.pipeline_accounting.denominator.occurrence_at = "2026-07-19T10:02:00Z";
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, joinedQuality, incoherentEvaluationClock]).some((error) => error.includes("denominator occurrence must equal decision time")), "evaluation denominator occurrence cannot drift from the exact decision clock");
const unratedEvaluationAdmitted = structuredClone(evaluationAdmitted);
unratedEvaluationAdmitted.record_id = "opaque:72727272-7272-4272-8272-727272727272";
unratedEvaluationAdmitted.pipeline_accounting.event_id = "opaque:73737373-7373-4373-8373-737373737373";
unratedEvaluationAdmitted.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [], "2026-07-19T10:02:01Z");
assert.deepEqual(validateDataset([joinedOutcome, joinedExposure, joinedCapability, unratedEvaluationAdmitted]), [], "an independently verified candidate may be admitted with an empty quality cohort bound as unrated");
const recordIdOnlyAdmission = structuredClone(evaluationAdmitted);
recordIdOnlyAdmission.pipeline_accounting.evaluation_bundle = notApplicable();
assert.ok(validateDataset([joinedOutcome, recordIdOnlyAdmission]).some((error) => error.includes("complete joined evidence bundle")), "candidate record identity alone cannot establish evaluation admission");
const nonAdmittedOutcome = nonAdmittedFixture.record;
const incompleteProvenanceAdmission = structuredClone(evaluationAdmitted);
incompleteProvenanceAdmission.pipeline_accounting.related_record = evidenceRef(nonAdmittedOutcome);
incompleteProvenanceAdmission.pipeline_accounting.evaluation_bundle.task_outcome = evidenceRef(nonAdmittedOutcome);
assert.ok(validateDataset([nonAdmittedOutcome, joinedExposure, joinedCapability, joinedQuality, incompleteProvenanceAdmission]).some((error) => error.includes("lacks complete provenance/governance")), "an m5-not-admitted/provenance-incomplete candidate cannot enter evaluation even when a bundle-shaped body is present");

const quality = positive.find((record) => record.record_kind === "quality-receipt");
const nativeQualityV1 = sourceDocuments.get(quality.quality_receipt.native_receipt.artifact_digest.source_ref).document;
assert.equal(Object.hasOwn(nativeQualityV1, "attemptId"), false, "current native Hugin quality receipt v1 does not claim an attempt field");
assert.equal(Object.hasOwn(nativeQualityV1, "rubric"), false, "current native Hugin quality receipt v1 does not claim a rubric field");
assert.equal(typeof nativeQualityV1.ratingReason, "string", "current native Hugin quality receipt v1 preserves reason text in its immutable artifact");
function installQualityNativeArtifact(record, schemaVersion, reason, correctsReceiptId) {
  const receipt = record.quality_receipt;
  const oldRef = receipt.native_receipt.artifact_digest.source_ref;
  const binding = normalizedNativeBinding(receipt.binding);
  const common = {
    taskId: receipt.task_id,
    ...(schemaVersion === 2 ? { attemptId: receipt.attempt_id } : {}),
    rating: receipt.rating,
    ratingReason: reason,
    verificationOutcome: receipt.disposition,
    ...(Number.isInteger(receipt.retries_count) ? { retriesCount: receipt.retries_count } : {}),
    ratedAt: receipt.rated_at,
    reviewer: receipt.reviewer,
    ...(schemaVersion === 2 ? { rubric: receipt.rubric } : {}),
    bindingAttestation: receipt.binding_attestation,
    binding,
    ...(schemaVersion === 2 ? { correctsReceiptId } : {}),
  };
  const semantic = schemaVersion === 1
    ? { taskId: common.taskId, reviewerPrincipal: common.reviewer.principal, reviewerIndependence: common.reviewer.independence, rating: common.rating, ratingReason: common.ratingReason, verificationOutcome: common.verificationOutcome, retriesCount: common.retriesCount, bindingAttestation: common.bindingAttestation, binding: common.binding }
    : common;
  const receiptId = schemaVersion === 1 ? huginReceiptId(semantic) : `qr-${digestCanonical(semantic).slice(0, 24)}`;
  const document = { schemaVersion, receiptId, ...common };
  const sourceRef = `source-doc:quality/${receiptId}`;
  const sourceType = `quality-receipt-native-v${schemaVersion}`;
  sourceDocuments.set(sourceRef, { source_ref: sourceRef, source_type: sourceType, source_version: schemaVersion === 1 ? "hugin-quality-receipt-v1" : "future-hugin-quality-receipt-v2", document });
  receipt.native_receipt = { schema_version: schemaVersion, receipt_id: receiptId, artifact_digest: { algorithm: "sha256", canonicalization: "jcs-rfc8785-utf8-v1", source_ref: sourceRef, source_type: sourceType, source_version: schemaVersion === 1 ? "hugin-quality-receipt-v1" : "future-hugin-quality-receipt-v2", digest: digestCanonical(document) } };
  receipt.rating_reason_sha256 = digest(reason);
  receipt.correction_group_key.digest = digestCanonical({ task_id: receipt.task_id, attempt_id: receipt.attempt_id, reviewer: receipt.reviewer, rubric: receipt.rubric, binding: receipt.binding });
  const policy = record.governance.policies.find((candidate) => candidate.subject_ref === oldRef);
  if (policy) policy.subject_ref = sourceRef;
  record.governance.effective.derived_from_subject_refs = record.governance.effective.derived_from_subject_refs.map((ref) => ref === oldRef ? sourceRef : ref).sort(compareUtf16CodeUnits);
}
function installCorrectionGovernance(record, sourceRef, correctionRef) {
  const oldSourceRef = record.governance.policy_manifest.digest.source_ref;
  record.governance.policy_manifest.manifest_id = "opaque:54545454-5454-4454-8454-545454545454";
  record.governance.policy_manifest.digest.source_ref = sourceRef;
  const manifestPolicy = record.governance.policies.find((policy) => policy.subject_ref === oldSourceRef);
  manifestPolicy.subject_ref = sourceRef;
  if (correctionRef) {
    const correctionPolicy = structuredClone(record.governance.policies[0]);
    correctionPolicy.subject_ref = correctionRef;
    correctionPolicy.subject_kind = "artifact";
    record.governance.policies.push(correctionPolicy);
  }
  record.governance.effective.derived_from_subject_refs = record.governance.effective.derived_from_subject_refs.map((ref) => ref === oldSourceRef ? sourceRef : ref);
  if (correctionRef) record.governance.effective.derived_from_subject_refs.push(correctionRef);
  record.governance.effective.derived_from_subject_refs.sort(compareUtf16CodeUnits);
  installOwnerApproval(record);
  const manifest = record.governance.policy_manifest;
  const document = {
    schema_version: "governance-policy-manifest/v1",
    contract: { contract_version: record.contract_version, schema_revision: record.schema_revision },
    manifest: {
      manifest_id: manifest.manifest_id,
      version: manifest.version,
      approved_at: manifest.approved_at,
      owner_attestations: [...manifest.owner_attestations].sort((a, b) => compareUtf16CodeUnits(a.content_owner, b.content_owner)),
    },
    record_binding: { record_kind: record.record_kind, producer: record.producer.component, task: record.task },
    policies: [...record.governance.policies].sort((a, b) => compareUtf16CodeUnits(a.subject_ref, b.subject_ref)),
  };
  sourceDocuments.set(sourceRef, { source_ref: sourceRef, source_type: "governance-policy-manifest", source_version: "governance-policy-manifest-v1", document });
  manifest.digest.digest = digestCanonical(document);
}

function correctedRecord(source, { recordId, recordedAt, correctionRef, manifestRef }) {
  const record = structuredClone(source);
  record.record_id = recordId;
  record.recorded_at = recordedAt;
  record.artifacts.items.push({ kind: "correction", owner: "principal:owner", ref: correctionRef, content_hash: { value: null, unknown_reason: "not-observed" } });
  const factDomain = { "task-outcome": "outcome", "inference-exposure": "exposure", "capability-evidence": "capability" }[source.record_kind];
  record.lineage.correction_targets = [{ producer: source.producer.component, record_kind: source.record_kind, fact_domain: factDomain, record_id: source.record_id }];
  record.lineage.correction_ref = correctionRef;
  installCorrectionGovernance(record, manifestRef, correctionRef);
  return record;
}

const preDecisionExposureCorrection = correctedRecord(joinedExposure, { recordId: "opaque:76767676-7676-4676-8676-767676767677", recordedAt: "2026-07-19T10:01:02Z", correctionRef: "mimir:correction/exposure-pre-decision", manifestRef: "source-doc:governance/exposure-pre-decision" });
const staleExposureAdmission = structuredClone(evaluationAdmitted);
assert.ok(validateDataset([joinedOutcome, joinedExposure, preDecisionExposureCorrection, joinedCapability, joinedQuality, staleExposureAdmission]).some((error) => error.includes("effective correction leaf at decision time")), "evaluation cannot select an exposure predecessor corrected before its decision");
const preDecisionCapabilityCorrection = correctedRecord(joinedCapability, { recordId: "opaque:79797979-7979-4979-8979-797979797979", recordedAt: "2026-07-19T10:01:03Z", correctionRef: "mimir:correction/capability-pre-decision", manifestRef: "source-doc:governance/capability-pre-decision" });
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, preDecisionCapabilityCorrection, joinedQuality, evaluationAdmitted]).some((error) => error.includes("effective correction leaf at decision time")), "evaluation cannot select a capability predecessor corrected before its decision");
const postDecisionExposureCorrection = correctedRecord(joinedExposure, { recordId: "opaque:77777777-7777-4777-8777-777777777778", recordedAt: "2026-07-19T10:02:02Z", correctionRef: "mimir:correction/exposure-post-decision", manifestRef: "source-doc:governance/exposure-post-decision" });
assert.deepEqual(validateDataset([joinedOutcome, joinedExposure, postDecisionExposureCorrection, joinedCapability, joinedQuality, evaluationAdmitted]), [], "a correction recorded after evaluation does not invalidate the leaf selected at decision time");
const correctedOutcomeLeaf = correctedRecord(joinedOutcome, { recordId: "opaque:78787878-7878-4878-8878-787878787878", recordedAt: "2026-07-19T10:01:01Z", correctionRef: "mimir:correction/outcome-pre-decision", manifestRef: "source-doc:governance/outcome-pre-decision" });
const correctedOutcomeAdmission = structuredClone(unratedEvaluationAdmitted);
correctedOutcomeAdmission.pipeline_accounting.related_record = evidenceRef(correctedOutcomeLeaf);
correctedOutcomeAdmission.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(correctedOutcomeLeaf, joinedExposure, joinedCapability, [], "2026-07-19T10:02:01Z");
assert.deepEqual(validateDataset([joinedOutcome, correctedOutcomeLeaf, joinedExposure, joinedCapability, correctedOutcomeAdmission]), [], "a corrected task outcome remains eligible when the bundle references its unique effective lineage leaf");

const correctedQuality = structuredClone(quality);
correctedQuality.record_id = "opaque:55555555-5555-4555-8555-555555555556";
correctedQuality.recorded_at = "2026-07-19T10:02:02Z";
correctedQuality.quality_receipt.disposition = "minor_edit";
installQualityNativeArtifact(correctedQuality, 2, "Fixture corrected review.", quality.quality_receipt.native_receipt.receipt_id);
const qualityCorrectionRef = "mimir:correction/quality-receipt-001";
correctedQuality.artifacts.items.push({ kind: "correction", owner: "principal:owner", ref: qualityCorrectionRef, content_hash: { value: null, unknown_reason: "not-observed" } });
correctedQuality.lineage.correction_targets = [{ producer: "hugin", record_kind: "quality-receipt", fact_domain: "quality", record_id: quality.record_id }];
correctedQuality.lineage.correction_ref = qualityCorrectionRef;
const correctedQualityManifestRef = "source-doc:governance/corrected-quality";
installCorrectionGovernance(correctedQuality, correctedQualityManifestRef, qualityCorrectionRef);
assert.deepEqual(validateDataset([quality, correctedQuality]), [], "a real fact correction preserves the original task attempt and forms one same-key supersession chain");
assert.notEqual(correctedQuality.quality_receipt.native_receipt.receipt_id, quality.quality_receipt.native_receipt.receipt_id, "a correction mints a distinct future native receipt id instead of reusing content-derived v1 identity");
assert.deepEqual(correctedQuality.quality_receipt.correction_group_key, quality.quality_receipt.correction_group_key, "the explicit correction group, not receipt id, links one reviewer's corrected verdict chain");
assert.deepEqual(summarizeImmutable([quality, correctedQuality], "quality_receipt", ["rating", "disposition"], ["task_id", "attempt_id", "binding"])[0].result, { rating: "pass", disposition: "minor_edit" }, "derived summaries select the unique corrected leaf rather than reporting a false conflict");
const correctedQualityAdmission = structuredClone(evaluationAdmitted);
correctedQualityAdmission.recorded_at = "2026-07-19T10:02:04Z";
correctedQualityAdmission.pipeline_accounting.observed_at = "2026-07-19T10:02:03.500Z";
correctedQualityAdmission.pipeline_accounting.denominator.occurrence_at = "2026-07-19T10:02:03Z";
correctedQualityAdmission.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [correctedQuality], "2026-07-19T10:02:03Z");
assert.deepEqual(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, correctedQuality, correctedQualityAdmission]), [], "quality corrections collapse to the effective leaf before complete-cohort evaluation");
const crossKeyCorrection = structuredClone(correctedQuality);
crossKeyCorrection.quality_receipt.attempt_id = "attempt-other";
installQualityNativeArtifact(crossKeyCorrection, 2, "Fixture cross-key review.", quality.quality_receipt.native_receipt.receipt_id);
installCorrectionGovernance(crossKeyCorrection, "source-doc:governance/cross-key-quality");
assert.ok(validateDataset([quality, crossKeyCorrection]).includes("correction target belongs to another natural conflict key"), "corrections cannot move across natural conflict keys");
const missingCorrectionTarget = structuredClone(correctedQuality);
missingCorrectionTarget.lineage.correction_targets[0].record_id = "opaque:57575757-5757-4757-8757-575757575757";
assert.ok(validateDataset([quality, missingCorrectionTarget]).includes("correction target is missing from the validated dataset"), "correction targets must exist in the validated dataset");
const timeTravelCorrection = structuredClone(correctedQuality);
timeTravelCorrection.recorded_at = "2026-07-19T10:02:00Z";
assert.ok(validateDataset([quality, timeTravelCorrection]).some((error) => error.includes("strictly later than its predecessor")), "a correction cannot tie or predate the record it supersedes");
const sameTimeCorrection = structuredClone(correctedQuality);
sameTimeCorrection.recorded_at = quality.recorded_at;
assert.ok(validateDataset([quality, sameTimeCorrection]).some((error) => error.includes("strictly later than its predecessor")), "time-ordered correction chains require a strict clock advance");
const selfCorrection = structuredClone(correctedQuality);
selfCorrection.lineage.correction_targets[0].record_id = selfCorrection.record_id;
assert.ok(validateDataset([selfCorrection]).some((error) => error.includes("correction cannot target itself") || error.includes("correction target is missing")), "a correction cannot target itself");
const secondQuality = structuredClone(quality);
secondQuality.record_id = "opaque:12121212-1212-4212-8212-121212121212";
secondQuality.quality_receipt.reviewer.principal = "principal:reviewer-3";
secondQuality.review.reviewer_principal_id = "principal:reviewer-3";
installQualityNativeArtifact(secondQuality, 1, "Fixture independent review.");
installCorrectionGovernance(secondQuality, "source-doc:governance/second-quality");
assert.deepEqual(validateDataset([quality, secondQuality]), [], "multiple immutable quality receipts for one task/attempt are permitted");
assert.notDeepEqual(quality.quality_receipt.correction_group_key, secondQuality.quality_receipt.correction_group_key, "independent reviewers retain separate receipt ids and correction groups");
assert.deepEqual(summarizeImmutable([quality, secondQuality], "quality_receipt", ["rating", "disposition"], ["task_id", "attempt_id", "binding"])[0].result, { rating: "pass", disposition: "accepted_unchanged" }, "unanimous receipts summarize full rating/disposition without newest-wins");
const completeQualityCohortAdmission = structuredClone(evaluationAdmitted);
completeQualityCohortAdmission.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [quality, secondQuality], "2026-07-19T10:02:01Z");
assert.deepEqual(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, secondQuality, completeQualityCohortAdmission]), [], "evaluation accepts every available effective receipt in one exact non-conflicted cohort");
const postDecisionQuality = structuredClone(secondQuality);
postDecisionQuality.recorded_at = "2026-07-19T10:02:02Z";
assert.deepEqual(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, postDecisionQuality, evaluationAdmitted]), [], "an independent receipt recorded after decision does not rewrite the historical quality cohort");
const conflictingQuality = structuredClone(secondQuality);
conflictingQuality.quality_receipt.disposition = "minor_edit";
installQualityNativeArtifact(conflictingQuality, 1, "Fixture conflicting independent review.");
installCorrectionGovernance(conflictingQuality, "source-doc:governance/conflicting-quality");
assert.deepEqual(validateDataset([quality, conflictingQuality]), [], "an independently issued disagreeing receipt remains valid evidence");
assert.equal(summarizeImmutable([quality, conflictingQuality], "quality_receipt", ["rating", "disposition"], ["task_id", "attempt_id", "binding"])[0].result, "conflicted", "any rating/disposition disagreement summarizes as conflicted");
const cherryPickedQualityAdmission = structuredClone(evaluationAdmitted);
cherryPickedQualityAdmission.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [quality], "2026-07-19T10:02:01Z");
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, conflictingQuality, cherryPickedQualityAdmission]).some((error) => error.includes("every effective quality leaf")), "evaluation cannot cherry-pick the favorable receipt from a conflicting complete cohort");
const falselyUnratedAdmission = structuredClone(unratedEvaluationAdmitted);
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, conflictingQuality, falselyUnratedAdmission]).some((error) => error.includes("cannot claim unrated")), "evaluation cannot claim unrated when any effective receipt already exists for the task attempt");
const conflictedQualityAdmission = structuredClone(evaluationAdmitted);
conflictedQualityAdmission.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [quality, conflictingQuality], "2026-07-19T10:02:01Z");
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, conflictingQuality, conflictedQualityAdmission]).some((error) => error.includes("one independent non-conflicted binding/rubric cohort")), "a conflicting optional quality cohort cannot support evaluation admission");
const differentBindingQuality = structuredClone(quality);
differentBindingQuality.record_id = "opaque:75757575-7575-4575-8575-757575757575";
differentBindingQuality.quality_receipt.binding.structured_result_sha256 = "9999999999999999999999999999999999999999999999999999999999999999";
installQualityNativeArtifact(differentBindingQuality, 1, "Fixture different result binding.");
installCorrectionGovernance(differentBindingQuality, "source-doc:governance/different-binding-quality");
const omittedDifferentBindingAdmission = structuredClone(evaluationAdmitted);
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, differentBindingQuality, omittedDifferentBindingAdmission]).some((error) => error.includes("cannot choose among multiple available quality binding/rubric cohorts")), "evaluation cannot omit a pre-decision receipt from a different binding cohort");
const mixedCohortAdmission = structuredClone(evaluationAdmitted);
mixedCohortAdmission.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [quality, differentBindingQuality], "2026-07-19T10:02:01Z");
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, differentBindingQuality, mixedCohortAdmission]).some((error) => error.includes("one independent non-conflicted binding/rubric cohort")), "evaluation cannot silently summarize only the first of multiple binding or rubric cohorts");
const differentRubricQuality = structuredClone(quality);
differentRubricQuality.record_id = "opaque:73737373-7373-4373-8373-737373737373";
const originalRubricRef = differentRubricQuality.quality_receipt.rubric.config_digest.source_ref;
const differentRubricRef = "source-doc:rubric/quality-v2";
const differentRubricSource = structuredClone(sourceDocuments.get(originalRubricRef));
differentRubricSource.source_ref = differentRubricRef;
differentRubricSource.source_version = "rubric-source-v2";
differentRubricSource.document.version = "v2";
sourceDocuments.set(differentRubricRef, differentRubricSource);
differentRubricQuality.quality_receipt.rubric.version = "v2";
differentRubricQuality.quality_receipt.rubric.config_digest.source_ref = differentRubricRef;
differentRubricQuality.quality_receipt.rubric.config_digest.source_version = "rubric-source-v2";
differentRubricQuality.quality_receipt.rubric.config_digest.digest = digestCanonical(differentRubricSource.document);
differentRubricQuality.governance.policies.find((policy) => policy.subject_ref === originalRubricRef).subject_ref = differentRubricRef;
differentRubricQuality.governance.effective.derived_from_subject_refs = differentRubricQuality.governance.effective.derived_from_subject_refs.map((ref) => ref === originalRubricRef ? differentRubricRef : ref).sort(compareUtf16CodeUnits);
installQualityNativeArtifact(differentRubricQuality, 1, "Fixture different rubric review.");
installCorrectionGovernance(differentRubricQuality, "source-doc:governance/different-rubric-quality");
assert.deepEqual(validateDataset([quality, differentRubricQuality]), [], "immutable quality receipts may retain separate rubric cohorts outside evaluation admission");
const omittedDifferentRubricAdmission = structuredClone(evaluationAdmitted);
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, quality, differentRubricQuality, omittedDifferentRubricAdmission]).some((error) => error.includes("cannot choose among multiple available quality binding/rubric cohorts")), "evaluation cannot omit a pre-decision receipt from a different rubric cohort");
const selfReviewedQuality = structuredClone(quality);
selfReviewedQuality.record_id = "opaque:74747474-7474-4474-8474-747474747474";
selfReviewedQuality.quality_receipt.reviewer = { principal: "principal:self-reviewer", independence: "self" };
selfReviewedQuality.review.reviewer_principal_id = "principal:self-reviewer";
installQualityNativeArtifact(selfReviewedQuality, 1, "Fixture self review.");
installCorrectionGovernance(selfReviewedQuality, "source-doc:governance/self-reviewed-quality");
const selfReviewedAdmission = structuredClone(evaluationAdmitted);
selfReviewedAdmission.pipeline_accounting.evaluation_bundle = buildEvaluationBundle(joinedOutcome, joinedExposure, joinedCapability, [selfReviewedQuality], "2026-07-19T10:02:01Z");
assert.ok(validateDataset([joinedOutcome, joinedExposure, joinedCapability, selfReviewedQuality, selfReviewedAdmission]).some((error) => error.includes("one independent non-conflicted binding/rubric cohort")), "a non-independent optional quality receipt cannot support evaluation admission");
sourceDocuments.delete(correctedQualityManifestRef);
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

for (const record of positive.filter((candidate) => candidate.record_kind !== "pipeline-accounting")) {
  for (const claim of sourceDocumentClaims(record)) {
    const errors = [];
    validateSourceDocumentDigest(claim, errors);
    assert.deepEqual(errors, [], `source document claim ${claim.source_ref} must be executable`);
  }
}
for (const testCase of sourceDocumentNegative) {
  const original = sourceDocuments.get(testCase.source_ref);
  const mutated = structuredClone(original);
  mutate(mutated, { op: "set", path: testCase.path, value: testCase.value });
  sourceDocuments.set(testCase.source_ref, mutated);
  const errors = validateDataset([positive[0]]);
  sourceDocuments.set(testCase.source_ref, original);
  assert.ok(errors.join("\n").includes(testCase.expected_error), `${testCase.name}: expected ${testCase.expected_error} in:\n${errors.join("\n")}`);
}

const erasedErrors = validateDataset([positiveErased]);
assert.deepEqual(erasedErrors, [], `erased tombstone fixture must validate:\n${erasedErrors.join("\n")}`);
assert.deepEqual(Object.keys(positiveErased).sort(), ["contract_version", "lifecycle_state", "producer", "record_id", "record_kind", "recorded_at", "schema_revision", "tombstone"].sort(), "tombstone must expose only its reduced envelope");
function setMembershipReceipt(entry, counter, owner, membershipKey) {
  entry.counter = counter;
  entry.period_utc = "2026-07";
  entry.membership_receipt.owner_component = owner;
  delete entry.membership_receipt.membership_key;
  entry.membership_receipt.membership_key_digest = { algorithm: "sha256", version: "denominator-natural-key-jcs-v1", digest: digestCanonical({ owner_component: owner, counter, occurrence_month_utc: entry.period_utc, fixture_natural_key: membershipKey }) };
  const payload = { owner_component: owner, counter, period_utc: entry.period_utc, denominator_natural_key_digest: entry.membership_receipt.membership_key_digest, superseded_record_id: positiveErased.tombstone.superseded_record_id, issued_at: "2026-07-19T10:00:01Z" };
  entry.membership_receipt.membership_token = addTrustedFixtureEvidence("denominator-membership", owner, payload);
}
function installDenominatorBasisEvidence(record, issuer) {
  const counters = record.tombstone.counter_audit.map((entry) => entry.counter).sort(compareUtf16CodeUnits);
  const payload = { producer: record.producer.component, record_kind: record.record_kind, superseded_record_id: record.tombstone.superseded_record_id, denominator_basis: record.tombstone.denominator_basis, counters, issued_at: "2026-07-19T10:00:01Z" };
  record.tombstone.denominator_basis_evidence = addTrustedFixtureEvidence("denominator-basis", issuer, payload);
}
const joinedExposureTombstone = structuredClone(positiveErased);
joinedExposureTombstone.tombstone.denominator_basis = "joined-exposure";
setMembershipReceipt(joinedExposureTombstone.tombstone.counter_audit[0], "hugin-m5-join-denominator", "hugin", "membership:hugin-join:opaque-erased-001");
installDenominatorBasisEvidence(joinedExposureTombstone, "hugin");
assert.deepEqual(validateDataset([joinedExposureTombstone]), [], "gille-produced joined exposure may carry the Hugin-owned join membership receipt");
assert.equal(joinedExposureTombstone.tombstone.counter_audit[0].membership_receipt.membership_token.issuer, "hugin", "cross-owner erasure cites a trusted Hugin-issued immutable membership token");
const missingMembershipIssueClock = structuredClone(positiveErased);
const missingClockPayload = structuredClone(trustedEvidence.get("fixture-membership-direct-july").payload);
delete missingClockPayload.issued_at;
missingMembershipIssueClock.tombstone.counter_audit[0].membership_receipt.membership_token = addTrustedFixtureEvidence("denominator-membership", "gille-inference", missingClockPayload);
assert.ok(validateDataset([missingMembershipIssueClock]).some((error) => error.includes("valid issue time")), "membership authority without an exact issue clock fails closed");
const impossibleBasisClock = structuredClone(positiveErased);
const impossibleBasisPayload = structuredClone(trustedEvidence.get("fixture-denominator-basis-direct").payload);
impossibleBasisPayload.issued_at = "2026-02-30T00:00:00Z";
impossibleBasisClock.tombstone.denominator_basis_evidence = addTrustedFixtureEvidence("denominator-basis", "gille-inference", impossibleBasisPayload);
assert.ok(validateDataset([impossibleBasisClock]).some((error) => error.includes("valid pre-erasure issue clock")), "denominator basis authority rejects calendar-normalized impossible issue dates");
const shiftedMembershipPeriod = structuredClone(joinedExposureTombstone);
shiftedMembershipPeriod.tombstone.counter_audit[0].period_utc = "2026-08";
assert.ok(validateDataset([shiftedMembershipPeriod]).some((error) => error.includes("membership token does not bind owner, natural key, occurrence month")), "erasure cannot shift a July denominator membership into August");
const shiftedExposureBasis = structuredClone(positiveErased);
shiftedExposureBasis.tombstone.denominator_basis = "joined-exposure";
assert.ok(validateDataset([shiftedExposureBasis]).some((error) => error.includes("do not exactly match the declared denominator basis")), "erasure cannot switch direct and joined denominator basis without the owning counter token");
const huginTaskM5Tombstone = structuredClone(positiveErased);
huginTaskM5Tombstone.record_kind = "task-outcome";
huginTaskM5Tombstone.producer = { component: "hugin", schema_version: "task-outcome-v1" };
huginTaskM5Tombstone.tombstone.denominator_basis = "hugin-task-m5";
const captureMembership = structuredClone(huginTaskM5Tombstone.tombstone.counter_audit[0]);
captureMembership.membership_receipt.receipt_id = "opaque:58585858-5858-4858-8858-585858585858";
setMembershipReceipt(captureMembership, "hugin-capture-denominator", "hugin", "membership:hugin-capture:opaque-erased-001");
const joinMembership = structuredClone(huginTaskM5Tombstone.tombstone.counter_audit[0]);
joinMembership.membership_receipt.receipt_id = "opaque:59595959-5959-4959-8959-595959595959";
setMembershipReceipt(joinMembership, "hugin-m5-join-denominator", "hugin", "membership:hugin-join:opaque-erased-002");
huginTaskM5Tombstone.tombstone.counter_audit = [captureMembership, joinMembership];
installDenominatorBasisEvidence(huginTaskM5Tombstone, "hugin");
assert.deepEqual(validateDataset([huginTaskM5Tombstone]), [], "M5-backed Hugin task erasure preserves exact capture and join memberships");
const huginTaskNonM5Tombstone = structuredClone(huginTaskM5Tombstone);
huginTaskNonM5Tombstone.tombstone.denominator_basis = "hugin-task-non-m5";
huginTaskNonM5Tombstone.tombstone.counter_audit = [captureMembership];
installDenominatorBasisEvidence(huginTaskNonM5Tombstone, "hugin");
assert.deepEqual(validateDataset([huginTaskNonM5Tombstone]), [], "non-M5 Hugin task erasure preserves exactly capture membership");
const forgedNonM5Basis = structuredClone(huginTaskM5Tombstone);
forgedNonM5Basis.tombstone.denominator_basis = "hugin-task-non-m5";
forgedNonM5Basis.tombstone.counter_audit = [captureMembership];
assert.ok(validateDataset([forgedNonM5Basis]).some((error) => error.includes("denominator basis is not authenticated")), "an M5 task cannot self-select non-M5 basis and suppress its trusted join membership");
const missingJoinMembership = structuredClone(huginTaskM5Tombstone);
missingJoinMembership.tombstone.counter_audit = [captureMembership];
assert.ok(validateDataset([missingJoinMembership]).some((error) => error.includes("do not exactly match the declared denominator basis")), "M5-backed task erasure cannot omit join membership");
const pipelineDenominatorTombstone = structuredClone(positiveErased);
pipelineDenominatorTombstone.record_kind = "pipeline-accounting";
pipelineDenominatorTombstone.producer = { component: "gille-inference", schema_version: "pipeline-accounting-v1" };
pipelineDenominatorTombstone.tombstone.denominator_basis = "pipeline-direct-m5-exposure-denominator";
installDenominatorBasisEvidence(pipelineDenominatorTombstone, "gille-inference");
assert.deepEqual(validateDataset([pipelineDenominatorTombstone]), [], "denominator-decision accounting erasure preserves exactly its counter membership");
const missingExposureMembership = structuredClone(positiveErased);
missingExposureMembership.tombstone.counter_audit = [];
missingExposureMembership.tombstone.denominator_impact = "not-denominator-bearing";
assert.ok(validateDataset([missingExposureMembership]).some((error) => error.includes("denominator-bearing tombstone requires an idempotent membership receipt")), "inference-exposure erasure cannot evade denominator membership");
const genuinelyNonDenominatorTombstone = structuredClone(positiveErased);
genuinelyNonDenominatorTombstone.record_kind = "quality-receipt";
genuinelyNonDenominatorTombstone.producer = { component: "hugin", schema_version: "quality-receipt-v1" };
genuinelyNonDenominatorTombstone.tombstone.denominator_basis = "not-denominator-bearing";
genuinelyNonDenominatorTombstone.tombstone.denominator_impact = "not-denominator-bearing";
genuinelyNonDenominatorTombstone.tombstone.counter_audit = [];
installDenominatorBasisEvidence(genuinelyNonDenominatorTombstone, "hugin");
assert.deepEqual(validateDataset([genuinelyNonDenominatorTombstone]), [], "genuinely non-denominator evidence erases without fabricating counter membership");

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
