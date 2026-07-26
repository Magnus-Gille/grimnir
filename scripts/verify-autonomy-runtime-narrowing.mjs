#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import { spawnSync } from "node:child_process";
const [ledgerPath, registryPath, manifestPath, constitutionPath, coveragePath, attestationsPath, expectedOwnerKeyPath] = process.argv.slice(2);
if (![ledgerPath, registryPath, manifestPath, constitutionPath, coveragePath, attestationsPath, expectedOwnerKeyPath].every(Boolean)) { console.error("usage: verify-autonomy-runtime-narrowing.mjs LEDGER RECOVERY_WORKER_REGISTRY OWNER_AUTHORIZATION CONSTITUTION COVERAGE ATTESTATIONS EXPECTED_OWNER_KEY"); process.exit(64); }
const read = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const plain = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const canonical = (v) => plain(v) ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}` : Array.isArray(v) ? `[${v.map(canonical).join(",")}]` : JSON.stringify(v);
const digest = (v, omit) => { const x = structuredClone(v); if (omit) delete x[omit]; return `sha256:${crypto.createHash("sha256").update(canonical(x)).digest("hex")}`; };
const exactKeys = (value, keys) => Object.keys(value).sort().join(",") === [...keys].sort().join(",");
try {
  const ledger = read(ledgerPath), registry = read(registryPath);
  const auth = read(manifestPath);
  if (!exactKeys(ledger, ["kind", "schema_version", "ledger_id", "owner_authorization_digest", "entries", "extensions"]) || ledger.kind !== "autonomy-runtime-narrowing" || ledger.schema_version !== "v1" || !Array.isArray(ledger.entries) || !Array.isArray(ledger.extensions) || ledger.extensions.length) throw new Error("invalid closed runtime ledger shape");
  if (!exactKeys(registry, ["kind", "schema_version", "registry_id", "entries", "registry_digest", "extensions"]) || registry.kind !== "autonomy-recovery-worker-registry" || registry.schema_version !== "v1" || !Array.isArray(registry.entries) || !Array.isArray(registry.extensions) || registry.extensions.length || registry.registry_digest !== digest(registry, "registry_digest")) throw new Error("invalid closed recovery registry shape");
  const ownerCheck = spawnSync(process.execPath, [new URL("./verify-autonomy-owner-authorization.mjs", import.meta.url).pathname, manifestPath, constitutionPath, coveragePath, attestationsPath, registryPath, expectedOwnerKeyPath], { encoding: "utf8" });
  if (ownerCheck.status !== 0) throw new Error(`owner authorization failed: ${ownerCheck.stderr.trim()}`);
  if (ledger.owner_authorization_digest !== digest(auth)) throw new Error("ledger is not bound to the verified owner authorization");
  let previous = null;
  ledger.entries.forEach((entry, index) => {
    if (!exactKeys(entry, ["sequence", "recorded_at", "domain", "target_scope_digest", "from_state", "to_state", "recovery_worker_identity", "journal_receipt_digest", "previous_entry_digest", "entry_digest", "signature"]) || !exactKeys(entry.signature ?? {}, ["algorithm", "value_base64"]) || entry.signature.algorithm !== "Ed25519") throw new Error("invalid closed narrowing entry shape");
    if (entry.sequence !== index + 1 || entry.previous_entry_digest !== previous) throw new Error("non-append-only ledger chain");
    if (entry.to_state !== "shadow" || !["armed-canary", "armed-fleet"].includes(entry.from_state)) throw new Error("recovery may only narrow armed state to shadow");
    const bound = registry.entries.find((x) => x.domain === entry.domain && x.target_scope_digest === entry.target_scope_digest && x.recovery_worker_identity === entry.recovery_worker_identity);
    if (!bound) throw new Error("unbound recovery worker");
    const unsigned = structuredClone(entry); delete unsigned.signature;
    if (!crypto.verify(null, Buffer.from(canonical(unsigned)), crypto.createPublicKey(bound.public_key_pem), Buffer.from(entry.signature.value_base64, "base64"))) throw new Error("invalid recovery signature");
    const digestInput = structuredClone(entry); delete digestInput.entry_digest; delete digestInput.signature;
    if (entry.entry_digest !== digest(digestInput)) throw new Error("entry digest mismatch");
    previous = entry.entry_digest;
  });
  console.log(JSON.stringify({ ok: true, entries: ledger.entries.length }));
} catch (error) { console.error(`runtime narrowing rejected: ${error.message}`); process.exit(1); }
