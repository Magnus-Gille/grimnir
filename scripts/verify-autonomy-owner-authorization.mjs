#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";

const [manifestPath, constitutionPath, coveragePath, attestationsPath, recoveryRegistryPath, expectedPublicKeyPath] = process.argv.slice(2);
if (![manifestPath, constitutionPath, coveragePath, attestationsPath, recoveryRegistryPath, expectedPublicKeyPath].every(Boolean)) {
  console.error("usage: verify-autonomy-owner-authorization.mjs MANIFEST CONSTITUTION COVERAGE_INTENT ATTESTATIONS RECOVERY_WORKER_REGISTRY EXPECTED_OWNER_PUBLIC_KEY");
  process.exit(64);
}
const read = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const canonical = (value) => plain(value) ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : JSON.stringify(value);
const digest = (value, omit) => { const copy = structuredClone(value); if (omit) delete copy[omit]; return `sha256:${crypto.createHash("sha256").update(canonical(copy)).digest("hex")}`; };
const fail = (message) => { throw new Error(`owner authorization rejected: ${message}`); };
const exactKeys = (value, keys) => value && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
try {
  const manifest = read(manifestPath);
  const constitution = read(constitutionPath);
  const coverage = read(coveragePath);
  const attestations = read(attestationsPath);
  const recoveryRegistry = read(recoveryRegistryPath);
  if (!exactKeys(manifest, ["kind", "schema_version", "authorization_id", "issued_at", "authority", "bindings", "signature"]) || !exactKeys(manifest.authority, ["key_id", "algorithm", "public_key_pem", "public_key_fingerprint"]) || !exactKeys(manifest.bindings, ["constitution_digest", "coverage_intent_digest", "owner_attestation_registry_digest", "recovery_worker_registry_digest"]) || !exactKeys(manifest.signature, ["algorithm", "value_base64"])) fail("invalid closed manifest shape");
  if (manifest.kind !== "autonomy-owner-authorization" || manifest.schema_version !== "v1") fail("unsupported manifest");
  if (manifest.authority.algorithm !== "Ed25519" || manifest.signature.algorithm !== "Ed25519") fail("non-Ed25519 authority");
  const key = crypto.createPublicKey(manifest.authority.public_key_pem);
  const expectedKey = crypto.createPublicKey(fs.readFileSync(expectedPublicKeyPath, "utf8"));
  if (!key.export({ type: "spki", format: "der" }).equals(expectedKey.export({ type: "spki", format: "der" }))) fail("manifest key is not the independently pinned owner key");
  const fingerprint = `sha256:${crypto.createHash("sha256").update(key.export({ type: "spki", format: "der" })).digest("hex")}`;
  if (fingerprint !== manifest.authority.public_key_fingerprint) fail("public key fingerprint mismatch");
  const unsigned = structuredClone(manifest); delete unsigned.signature;
  if (!crypto.verify(null, Buffer.from(canonical(unsigned)), key, Buffer.from(manifest.signature.value_base64, "base64"))) fail("invalid detached signature");
  if (manifest.bindings.constitution_digest !== digest(constitution, "constitution_digest")) fail("constitution digest mismatch");
  if (manifest.bindings.coverage_intent_digest !== digest(coverage, "registry_digest")) fail("coverage intent digest mismatch");
  if (manifest.bindings.owner_attestation_registry_digest !== digest(attestations, "registry_digest")) fail("owner attestation digest mismatch");
  if (manifest.bindings.recovery_worker_registry_digest !== digest(recoveryRegistry, "registry_digest")) fail("recovery worker registry digest mismatch");
  console.log(JSON.stringify({ ok: true, authorization_digest: digest(manifest), key_id: manifest.authority.key_id }));
} catch (error) { console.error(error.message); process.exit(1); }
