#!/usr/bin/env node
// Public-only checkpoint derivation. It does not verify the signature or handle private material.
import crypto from "node:crypto";
import fs from "node:fs";
const [manifestPath] = process.argv.slice(2);
if (!manifestPath) { console.error("usage: prepare-autonomy-owner-authorization-checkpoint.mjs SIGNED_MANIFEST"); process.exit(64); }
const raw = fs.readFileSync(manifestPath, "utf8");
if (Buffer.byteLength(raw) > 1_000_000) throw new Error("manifest exceeds 1 MiB");
const manifest = JSON.parse(raw);
const exact = (value, keys) => value && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const id = /^[a-z][a-z0-9-]{2,62}$/, digest = /^sha256:[a-f0-9]{64}$/, utc = (v) => typeof v === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(v) && new Date(v).toISOString().replace(".000Z", "Z") === v;
if (!exact(manifest, ["kind", "schema_version", "authorization_id", "authorization_sequence", "previous_authorization_digest", "issued_at", "authority", "bindings", "signature"]) || manifest.kind !== "autonomy-owner-authorization" || manifest.schema_version !== "v1" || !id.test(manifest.authorization_id) || !Number.isSafeInteger(manifest.authorization_sequence) || manifest.authorization_sequence < 1 || !utc(manifest.issued_at) || (manifest.previous_authorization_digest !== null && !digest.test(manifest.previous_authorization_digest)) || !exact(manifest.authority, ["key_id", "algorithm", "public_key_pem", "public_key_fingerprint"]) || !exact(manifest.bindings, ["constitution_digest", "coverage_intent_digest", "owner_attestation_registry_digest", "recovery_worker_registry_digest"]) || !exact(manifest.signature, ["algorithm", "value_base64"]) || manifest.signature.algorithm !== "Ed25519") throw new Error("invalid closed signed-manifest shape");
if ((manifest.authorization_sequence === 1) !== (manifest.previous_authorization_digest === null)) throw new Error("invalid authorization predecessor chain");
const plain = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const canonical = (v) => plain(v) ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}` : Array.isArray(v) ? `[${v.map(canonical).join(",")}]` : JSON.stringify(v);
console.log(JSON.stringify({ kind: "autonomy-owner-authorization-checkpoint", schema_version: "v1", authorization_digest: `sha256:${crypto.createHash("sha256").update(canonical(manifest)).digest("hex")}`, minimum_sequence: manifest.authorization_sequence }, null, 2));
