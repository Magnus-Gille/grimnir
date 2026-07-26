#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";

const [manifestPath, constitutionPath, coveragePath, attestationsPath, recoveryRegistryPath, expectedPublicKeyPath, checkpointPath] = process.argv.slice(2);
if (![manifestPath, constitutionPath, coveragePath, attestationsPath, recoveryRegistryPath, expectedPublicKeyPath, checkpointPath].every(Boolean)) {
  console.error("usage: verify-autonomy-owner-authorization.mjs MANIFEST CONSTITUTION COVERAGE_INTENT ATTESTATIONS RECOVERY_WORKER_REGISTRY EXPECTED_OWNER_PUBLIC_KEY EXPECTED_AUTHORIZATION_CHECKPOINT");
  process.exit(64);
}
const read = (file) => { const raw = fs.readFileSync(file, "utf8"); if (Buffer.byteLength(raw) > 1_000_000) fail("input exceeds 1 MiB"); const value = JSON.parse(raw); let nodes = 0; const walk = (v, depth = 0) => { if (++nodes > 10_000 || depth > 64) fail("input exceeds structural limits"); if (v && typeof v === "object") for (const child of Object.values(v)) walk(child, depth + 1); }; walk(value); return value; };
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const canonical = (value) => plain(value) ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : JSON.stringify(value);
const digest = (value, omit) => { const copy = structuredClone(value); if (omit) delete copy[omit]; return `sha256:${crypto.createHash("sha256").update(canonical(copy)).digest("hex")}`; };
const fail = (message) => { throw new Error(`owner authorization rejected: ${message}`); };
const exactKeys = (value, keys) => value && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const digestPattern = /^sha256:[a-f0-9]{64}$/;
const idPattern = /^[a-z][a-z0-9-]{2,62}$/;
const utc = (value) => typeof value === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(value) && new Date(value).toISOString().replace(".000Z", "Z") === value;
const domains = new Set(["micro-routing", "macro-routing", "prompt", "harness", "tool-policy", "served-model-roster", "no-reboot-security-bugfix-maintenance"]);
try {
  const manifest = read(manifestPath);
  const constitution = read(constitutionPath);
  const coverage = read(coveragePath);
  const attestations = read(attestationsPath);
  const recoveryRegistry = read(recoveryRegistryPath);
  const checkpoint = read(checkpointPath);
  if (!exactKeys(manifest, ["kind", "schema_version", "authorization_id", "authorization_sequence", "previous_authorization_digest", "issued_at", "authority", "bindings", "signature"]) || !exactKeys(manifest.authority, ["key_id", "algorithm", "public_key_pem", "public_key_fingerprint"]) || !exactKeys(manifest.bindings, ["constitution_digest", "coverage_intent_digest", "owner_attestation_registry_digest", "recovery_worker_registry_digest"]) || !exactKeys(manifest.signature, ["algorithm", "value_base64"])) fail("invalid closed manifest shape");
  if (!exactKeys(checkpoint, ["kind", "schema_version", "authorization_digest", "minimum_sequence"]) || checkpoint.kind !== "autonomy-owner-authorization-checkpoint" || checkpoint.schema_version !== "v1" || !digestPattern.test(checkpoint.authorization_digest) || !Number.isSafeInteger(checkpoint.minimum_sequence)) fail("invalid externally protected authorization checkpoint");
  if (!exactKeys(recoveryRegistry, ["kind", "schema_version", "registry_id", "entries", "registry_digest", "extensions"]) || recoveryRegistry.kind !== "autonomy-recovery-worker-registry" || recoveryRegistry.schema_version !== "v1" || !idPattern.test(recoveryRegistry.registry_id) || !Array.isArray(recoveryRegistry.entries) || recoveryRegistry.entries.length > 256 || !Array.isArray(recoveryRegistry.extensions) || recoveryRegistry.extensions.length) fail("invalid closed recovery registry shape");
  if (!idPattern.test(manifest.authorization_id) || !idPattern.test(manifest.authority.key_id) || !utc(manifest.issued_at) || !Number.isSafeInteger(manifest.authorization_sequence) || manifest.authorization_sequence < checkpoint.minimum_sequence || (manifest.previous_authorization_digest !== null && !digestPattern.test(manifest.previous_authorization_digest))) fail("invalid authorization identity, time, or sequence");
  if ((manifest.authorization_sequence === 1) !== (manifest.previous_authorization_digest === null)) fail("invalid authorization predecessor chain");
  if (manifest.kind !== "autonomy-owner-authorization" || manifest.schema_version !== "v1") fail("unsupported manifest");
  if (manifest.authority.algorithm !== "Ed25519" || manifest.signature.algorithm !== "Ed25519") fail("non-Ed25519 authority");
  const key = crypto.createPublicKey(manifest.authority.public_key_pem);
  const expectedKey = crypto.createPublicKey(fs.readFileSync(expectedPublicKeyPath, "utf8"));
  if (key.asymmetricKeyType !== "ed25519" || expectedKey.asymmetricKeyType !== "ed25519") fail("owner key is not Ed25519");
  if (!key.export({ type: "spki", format: "der" }).equals(expectedKey.export({ type: "spki", format: "der" }))) fail("manifest key is not the independently pinned owner key");
  const fingerprint = `sha256:${crypto.createHash("sha256").update(key.export({ type: "spki", format: "der" })).digest("hex")}`;
  if (fingerprint !== manifest.authority.public_key_fingerprint) fail("public key fingerprint mismatch");
  const unsigned = structuredClone(manifest); delete unsigned.signature;
  if (!crypto.verify(null, Buffer.from(canonical(unsigned)), key, Buffer.from(manifest.signature.value_base64, "base64"))) fail("invalid detached signature");
  if (manifest.bindings.constitution_digest !== digest(constitution, "constitution_digest")) fail("constitution digest mismatch");
  if (manifest.bindings.coverage_intent_digest !== digest(coverage, "registry_digest")) fail("coverage intent digest mismatch");
  if (manifest.bindings.owner_attestation_registry_digest !== digest(attestations, "registry_digest")) fail("owner attestation digest mismatch");
  if (manifest.bindings.recovery_worker_registry_digest !== digest(recoveryRegistry, "registry_digest")) fail("recovery worker registry digest mismatch");
  if (constitution.constitution_digest !== digest(constitution, "constitution_digest") || coverage.registry_digest !== digest(coverage, "registry_digest") || attestations.registry_digest !== digest(attestations, "registry_digest") || recoveryRegistry.registry_digest !== digest(recoveryRegistry, "registry_digest")) fail("embedded artifact self-digest mismatch");
  const recoveryKeys = new Set(), fingerprints = new Set();
  for (const entry of recoveryRegistry.entries ?? []) {
    if (!exactKeys(entry, ["domain", "target_scope_digest", "recovery_worker_identity", "public_key_pem", "public_key_fingerprint"]) || !domains.has(entry.domain) || !idPattern.test(entry.recovery_worker_identity) || !digestPattern.test(entry.target_scope_digest)) fail("invalid recovery binding");
    const recoveryKey = crypto.createPublicKey(entry.public_key_pem);
    const recoveryFingerprint = `sha256:${crypto.createHash("sha256").update(recoveryKey.export({ type: "spki", format: "der" })).digest("hex")}`;
    if (recoveryKey.asymmetricKeyType !== "ed25519" || recoveryFingerprint !== entry.public_key_fingerprint) fail("invalid recovery key");
    const identity = `${entry.domain}:${entry.target_scope_digest}:${entry.recovery_worker_identity}`;
    if (recoveryKeys.has(identity)) fail("ambiguous recovery binding"); recoveryKeys.add(identity);
    if (fingerprints.has(recoveryFingerprint)) fail("recovery key fingerprint is reused across bindings"); fingerprints.add(recoveryFingerprint);
  }
  if (checkpoint.authorization_digest !== digest(manifest)) fail("authorization is not the independently protected current authorization");
  console.log(JSON.stringify({ ok: true, authorization_digest: digest(manifest), key_id: manifest.authority.key_id }));
} catch (error) { console.error(error.message); process.exit(1); }
