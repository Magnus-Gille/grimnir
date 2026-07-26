#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import { spawnSync } from "node:child_process";
const [ledgerPath, registryPath, manifestPath, constitutionPath, coveragePath, attestationsPath, expectedOwnerKeyPath, checkpointPath, tailCheckpointPath] = process.argv.slice(2);
if (![ledgerPath, registryPath, manifestPath, constitutionPath, coveragePath, attestationsPath, expectedOwnerKeyPath, checkpointPath, tailCheckpointPath].every(Boolean)) { console.error("usage: verify-autonomy-runtime-narrowing.mjs LEDGER RECOVERY_WORKER_REGISTRY OWNER_AUTHORIZATION CONSTITUTION COVERAGE ATTESTATIONS EXPECTED_OWNER_KEY EXPECTED_AUTHORIZATION_CHECKPOINT EXPECTED_NARROWING_TAIL_CHECKPOINT"); process.exit(64); }
const read = (file) => { const raw = fs.readFileSync(file, "utf8"); if (Buffer.byteLength(raw) > 1_000_000) throw new Error("input exceeds 1 MiB"); const value = JSON.parse(raw); let nodes = 0; const walk = (v, depth = 0) => { if (++nodes > 10_000 || depth > 64) throw new Error("input exceeds structural limits"); if (v && typeof v === "object") for (const child of Object.values(v)) walk(child, depth + 1); }; walk(value); return value; };
const plain = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const canonical = (v) => plain(v) ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}` : Array.isArray(v) ? `[${v.map(canonical).join(",")}]` : JSON.stringify(v);
const digest = (v, omit) => { const x = structuredClone(v); if (omit) delete x[omit]; return `sha256:${crypto.createHash("sha256").update(canonical(x)).digest("hex")}`; };
const exactKeys = (value, keys) => Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const digestPattern = /^sha256:[a-f0-9]{64}$/, idPattern = /^[a-z][a-z0-9-]{2,62}$/, base64 = /^[A-Za-z0-9+/]+={0,2}$/;
const utc = (v) => typeof v === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(v) && new Date(v).toISOString().replace(".000Z", "Z") === v;
try {
  const ledger = read(ledgerPath), registry = read(registryPath);
  const auth = read(manifestPath);
  const tailCheckpoint = read(tailCheckpointPath);
  if (!exactKeys(ledger, ["kind", "schema_version", "ledger_id", "owner_authorization_digest", "entries", "extensions"]) || ledger.kind !== "autonomy-runtime-narrowing" || ledger.schema_version !== "v1" || !idPattern.test(ledger.ledger_id) || !digestPattern.test(ledger.owner_authorization_digest) || !Array.isArray(ledger.entries) || ledger.entries.length > 4096 || !Array.isArray(ledger.extensions) || ledger.extensions.length) throw new Error("invalid closed runtime ledger shape");
  if (!exactKeys(registry, ["kind", "schema_version", "registry_id", "entries", "registry_digest", "extensions"]) || registry.kind !== "autonomy-recovery-worker-registry" || registry.schema_version !== "v1" || !Array.isArray(registry.entries) || !Array.isArray(registry.extensions) || registry.extensions.length || registry.registry_digest !== digest(registry, "registry_digest")) throw new Error("invalid closed recovery registry shape");
  const ownerCheck = spawnSync(process.execPath, [new URL("./verify-autonomy-owner-authorization.mjs", import.meta.url).pathname, manifestPath, constitutionPath, coveragePath, attestationsPath, registryPath, expectedOwnerKeyPath, checkpointPath], { encoding: "utf8" });
  if (ownerCheck.status !== 0) throw new Error(`owner authorization failed: ${ownerCheck.stderr.trim()}`);
  let childResult; try { childResult = JSON.parse(ownerCheck.stdout); } catch { throw new Error("owner verifier returned invalid result"); }
  if (childResult.authorization_digest !== digest(auth)) throw new Error("owner verifier observed a different authorization");
  if (auth.bindings?.recovery_worker_registry_digest !== digest(registry, "registry_digest")) throw new Error("owner verifier registry binding differs from cached registry");
  if (ledger.owner_authorization_digest !== digest(auth)) throw new Error("ledger is not bound to the verified owner authorization");
  let previous = null; const bindings = new Set();
  ledger.entries.forEach((entry, index) => {
    if (!exactKeys(entry, ["sequence", "recorded_at", "domain", "target_scope_digest", "from_state", "to_state", "recovery_worker_identity", "journal_receipt_digest", "previous_entry_digest", "entry_digest", "signature"]) || !exactKeys(entry.signature ?? {}, ["algorithm", "value_base64"]) || entry.signature.algorithm !== "Ed25519") throw new Error("invalid closed narrowing entry shape");
    if (!Number.isInteger(entry.sequence) || entry.sequence < 1 || !utc(entry.recorded_at) || !["micro-routing", "macro-routing", "prompt", "harness", "tool-policy", "served-model-roster", "no-reboot-security-bugfix-maintenance"].includes(entry.domain) || !idPattern.test(entry.recovery_worker_identity) || ![entry.target_scope_digest, entry.journal_receipt_digest, entry.entry_digest].every((v) => digestPattern.test(v)) || (entry.previous_entry_digest !== null && !digestPattern.test(entry.previous_entry_digest)) || !base64.test(entry.signature.value_base64)) throw new Error("invalid narrowing entry formats");
    if (entry.sequence !== index + 1 || entry.previous_entry_digest !== previous) throw new Error("non-append-only ledger chain");
    if (entry.to_state !== "shadow" || !["armed-canary", "armed-fleet"].includes(entry.from_state)) throw new Error("recovery may only narrow armed state to shadow");
    const bound = registry.entries.find((x) => x.domain === entry.domain && x.target_scope_digest === entry.target_scope_digest && x.recovery_worker_identity === entry.recovery_worker_identity);
    if (!bound) throw new Error("unbound recovery worker");
    const bindingIdentity = `${entry.domain}:${entry.target_scope_digest}:${entry.recovery_worker_identity}`;
    if (bindings.has(bindingIdentity)) throw new Error("duplicate narrowing worker binding"); bindings.add(bindingIdentity);
    const unsigned = structuredClone(entry); delete unsigned.signature;
    if (!crypto.verify(null, Buffer.from(canonical(unsigned)), crypto.createPublicKey(bound.public_key_pem), Buffer.from(entry.signature.value_base64, "base64"))) throw new Error("invalid recovery signature");
    const digestInput = structuredClone(entry); delete digestInput.entry_digest; delete digestInput.signature;
    if (entry.entry_digest !== digest(digestInput)) throw new Error("entry digest mismatch");
    previous = entry.entry_digest;
  });
  if (!exactKeys(tailCheckpoint, ["kind", "schema_version", "owner_authorization_digest", "ledger_tail_digest", "minimum_entries"]) || tailCheckpoint.kind !== "autonomy-runtime-narrowing-checkpoint" || tailCheckpoint.schema_version !== "v1" || tailCheckpoint.owner_authorization_digest !== ledger.owner_authorization_digest || !Number.isInteger(tailCheckpoint.minimum_entries) || tailCheckpoint.minimum_entries < 0 || ledger.entries.length < tailCheckpoint.minimum_entries || tailCheckpoint.ledger_tail_digest !== previous) throw new Error("ledger does not match independently protected tail checkpoint");
  console.log(JSON.stringify({ ok: true, entries: ledger.entries.length }));
} catch (error) { console.error(`runtime narrowing rejected: ${error.message}`); process.exit(1); }
