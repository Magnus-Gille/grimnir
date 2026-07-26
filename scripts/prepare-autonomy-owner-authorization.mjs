#!/usr/bin/env node
// Owner-operated preparation only: reads a public key and public artifacts; never touches a private key.
import crypto from "node:crypto";
import fs from "node:fs";
const [publicKeyPath, constitutionPath, coveragePath, attestationsPath, recoveryPath, sequence, previousDigest] = process.argv.slice(2);
if (![publicKeyPath, constitutionPath, coveragePath, attestationsPath, recoveryPath, sequence].every(Boolean)) { console.error("usage: prepare-autonomy-owner-authorization.mjs OWNER_PUBLIC_KEY CONSTITUTION COVERAGE ATTESTATIONS RECOVERY_REGISTRY SEQUENCE [PREVIOUS_DIGEST]"); process.exit(64); }
const read = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const plain = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const canonical = (v) => plain(v) ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}` : Array.isArray(v) ? `[${v.map(canonical).join(",")}]` : JSON.stringify(v);
const digest = (v, omit) => { const x = structuredClone(v); if (omit) delete x[omit]; return `sha256:${crypto.createHash("sha256").update(canonical(x)).digest("hex")}`; };
const key = crypto.createPublicKey(fs.readFileSync(publicKeyPath, "utf8"));
if (key.asymmetricKeyType !== "ed25519" || !Number.isInteger(Number(sequence)) || Number(sequence) < 1) throw new Error("Ed25519 public key and positive sequence required");
const constitution = read(constitutionPath), coverage = read(coveragePath), attestations = read(attestationsPath), recovery = read(recoveryPath);
for (const [value, field] of [[constitution, "constitution_digest"], [coverage, "registry_digest"], [attestations, "registry_digest"], [recovery, "registry_digest"]]) if (value[field] !== digest(value, field)) throw new Error(`invalid ${field}`);
const publicPem = fs.readFileSync(publicKeyPath, "utf8");
console.log(JSON.stringify({ kind: "autonomy-owner-authorization", schema_version: "v1", authorization_id: "owner-provided-authorization", authorization_sequence: Number(sequence), previous_authorization_digest: previousDigest ?? null, issued_at: new Date().toISOString().replace(".000Z", "Z"), authority: { key_id: "owner-provided-ed25519", algorithm: "Ed25519", public_key_pem: publicPem, public_key_fingerprint: `sha256:${crypto.createHash("sha256").update(key.export({ type: "spki", format: "der" })).digest("hex")}` }, bindings: { constitution_digest: digest(constitution, "constitution_digest"), coverage_intent_digest: digest(coverage, "registry_digest"), owner_attestation_registry_digest: digest(attestations, "registry_digest"), recovery_worker_registry_digest: digest(recovery, "registry_digest") }, signature: { algorithm: "Ed25519", value_base64: "REPLACE_WITH_SIGN_AUTONOMY_OUTPUT" } }, null, 2));
