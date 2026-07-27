#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fixture="$root/tests/fixtures/autonomy-contract"
fixture_v2="$root/tests/fixtures/autonomy-contract-v2"
work=$(mktemp -d "${TMPDIR:-/tmp}/grimnir-owner-auth.XXXXXX")
trap 'rm -rf "$work"' EXIT
verify() {
  node "$root/scripts/verify-autonomy-owner-authorization.mjs" "$@"
}
checkpoint="$fixture/test-owner-authorization-checkpoint.json"
node "$root/scripts/prepare-autonomy-owner-authorization.mjs" "$fixture/test-owner-ed25519-public.pem" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" 1 >"$work/prepared.json"
signature=$(bash "$root/scripts/sign-autonomy-owner-authorization.sh" "$fixture/test-owner-ed25519-private.pem" "$work/prepared.json")
node - "$work/prepared.json" "$signature" "$work/prepared-signed.json" <<'NODE'
const fs = require("fs"); const x = JSON.parse(fs.readFileSync(process.argv[2])); x.signature.value_base64 = process.argv[3]; fs.writeFileSync(process.argv[4], JSON.stringify(x));
NODE
node "$root/scripts/prepare-autonomy-owner-authorization-checkpoint.mjs" "$work/prepared-signed.json" >"$work/prepared-checkpoint.json"
verify "$work/prepared-signed.json" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$work/prepared-checkpoint.json" >/dev/null

# The current owner ceremony signs the complete v2 constitution/coverage epoch.
node "$root/scripts/prepare-autonomy-owner-authorization.mjs" "$fixture/test-owner-ed25519-public.pem" "$root/docs/autonomy-constitution-v2.json" "$fixture_v2/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" 1 >"$work/prepared-v2.json"
signature_v2=$(bash "$root/scripts/sign-autonomy-owner-authorization.sh" "$fixture/test-owner-ed25519-private.pem" "$work/prepared-v2.json")
node - "$work/prepared-v2.json" "$signature_v2" "$work/prepared-v2-signed.json" <<'NODE'
const fs = require("fs"); const x = JSON.parse(fs.readFileSync(process.argv[2])); x.signature.value_base64 = process.argv[3]; fs.writeFileSync(process.argv[4], JSON.stringify(x));
NODE
node "$root/scripts/prepare-autonomy-owner-authorization-checkpoint.mjs" "$work/prepared-v2-signed.json" >"$work/prepared-v2-checkpoint.json"
verify "$work/prepared-v2-signed.json" "$root/docs/autonomy-constitution-v2.json" "$fixture_v2/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$work/prepared-v2-checkpoint.json" >/dev/null
if verify "$work/prepared-v2-signed.json" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$work/prepared-v2-checkpoint.json" >/dev/null 2>&1; then
  echo "v2 owner authorization accepted a mixed historical v1 bundle" >&2; exit 1
fi
if node "$root/scripts/prepare-autonomy-owner-authorization.mjs" "$fixture/test-owner-ed25519-public.pem" "$root/docs/autonomy-constitution-v2.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" 1 >/dev/null 2>&1; then
  echo "owner preparation accepted a mixed v2 constitution and v1 coverage epoch" >&2; exit 1
fi
node - "$work/prepared-v2.json" "$fixture/coverage-armed-canary.json" "$work/mixed-epoch.json" <<'NODE'
const fs = require("fs"); const x = JSON.parse(fs.readFileSync(process.argv[2])); const coverage = JSON.parse(fs.readFileSync(process.argv[3])); x.bindings.coverage_intent_digest = coverage.registry_digest; fs.writeFileSync(process.argv[4], JSON.stringify(x));
NODE
mixed_signature=$(bash "$root/scripts/sign-autonomy-owner-authorization.sh" "$fixture/test-owner-ed25519-private.pem" "$work/mixed-epoch.json")
node - "$work/mixed-epoch.json" "$mixed_signature" <<'NODE'
const fs = require("fs"); const x = JSON.parse(fs.readFileSync(process.argv[2])); x.signature.value_base64 = process.argv[3]; fs.writeFileSync(process.argv[2], JSON.stringify(x));
NODE
node "$root/scripts/prepare-autonomy-owner-authorization-checkpoint.mjs" "$work/mixed-epoch.json" >"$work/mixed-epoch-checkpoint.json"
if verify "$work/mixed-epoch.json" "$root/docs/autonomy-constitution-v2.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$work/mixed-epoch-checkpoint.json" >/dev/null 2>&1; then
  echo "verifier accepted an owner-signed mixed v2 constitution and v1 coverage epoch" >&2; exit 1
fi
node - "$root/docs/autonomy-constitution-v1.json" "$root/docs/autonomy-coverage-registry-v1.json" "$work/relabeled-v1-constitution.json" "$work/relabeled-v1-coverage.json" <<'NODE'
const crypto = require("crypto"); const fs = require("fs");
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const canonical = (value) => plain(value) ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : JSON.stringify(value);
const digest = (value, omittedField) => { const copy = structuredClone(value); delete copy[omittedField]; return `sha256:${crypto.createHash("sha256").update(canonical(copy)).digest("hex")}`; };
const constitution = JSON.parse(fs.readFileSync(process.argv[2])); const coverage = JSON.parse(fs.readFileSync(process.argv[3]));
constitution.schema_version = "v2"; constitution.constitution_digest = digest(constitution, "constitution_digest");
coverage.schema_version = "v2"; coverage.constitution_digest = constitution.constitution_digest; coverage.registry_digest = digest(coverage, "registry_digest");
fs.writeFileSync(process.argv[4], JSON.stringify(constitution)); fs.writeFileSync(process.argv[5], JSON.stringify(coverage));
NODE
relabel_failures=0
if node "$root/scripts/prepare-autonomy-owner-authorization.mjs" "$fixture/test-owner-ed25519-public.pem" "$work/relabeled-v1-constitution.json" "$work/relabeled-v1-coverage.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" 1 >/dev/null 2>&1; then
  echo "owner preparation accepted v1 contract data relabelled and re-digested as v2" >&2
  relabel_failures=$((relabel_failures + 1))
fi
node - "$work/prepared-v2.json" "$work/relabeled-v1-constitution.json" "$work/relabeled-v1-coverage.json" "$work/relabeled-v1-manifest.json" <<'NODE'
const fs = require("fs"); const manifest = JSON.parse(fs.readFileSync(process.argv[2])); const constitution = JSON.parse(fs.readFileSync(process.argv[3])); const coverage = JSON.parse(fs.readFileSync(process.argv[4]));
manifest.bindings.constitution_digest = constitution.constitution_digest; manifest.bindings.coverage_intent_digest = coverage.registry_digest;
fs.writeFileSync(process.argv[5], JSON.stringify(manifest));
NODE
relabeled_signature=$(bash "$root/scripts/sign-autonomy-owner-authorization.sh" "$fixture/test-owner-ed25519-private.pem" "$work/relabeled-v1-manifest.json")
node - "$work/relabeled-v1-manifest.json" "$relabeled_signature" <<'NODE'
const fs = require("fs"); const manifest = JSON.parse(fs.readFileSync(process.argv[2])); manifest.signature.value_base64 = process.argv[3]; fs.writeFileSync(process.argv[2], JSON.stringify(manifest));
NODE
node "$root/scripts/prepare-autonomy-owner-authorization-checkpoint.mjs" "$work/relabeled-v1-manifest.json" >"$work/relabeled-v1-checkpoint.json"
if verify "$work/relabeled-v1-manifest.json" "$work/relabeled-v1-constitution.json" "$work/relabeled-v1-coverage.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$work/relabeled-v1-checkpoint.json" >/dev/null 2>&1; then
  echo "independent verifier accepted owner-signed v1 contract data relabelled and re-digested as v2" >&2
  relabel_failures=$((relabel_failures + 1))
fi
if [[ $relabel_failures -ne 0 ]]; then exit 1; fi
if node "$root/scripts/prepare-autonomy-owner-authorization.mjs" "$fixture/test-owner-ed25519-public.pem" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" 0 >/dev/null 2>&1; then echo "unsafe authorization sequence was prepared" >&2; exit 1; fi
if node "$root/scripts/prepare-autonomy-owner-authorization.mjs" "$fixture/test-owner-ed25519-public.pem" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" 2 bad-digest >/dev/null 2>&1; then echo "invalid previous digest was prepared" >&2; exit 1; fi
if node "$root/scripts/prepare-autonomy-owner-authorization.mjs" "$fixture/test-owner-ed25519-public.pem" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" 2 >/dev/null 2>&1; then echo "chainless successor was prepared" >&2; exit 1; fi
verify "$fixture/test-owner-authorization.json" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$checkpoint" >/dev/null
node - "$checkpoint" "$work/newer-authorization-checkpoint.json" <<'NODE'
const fs = require("fs"); const x = JSON.parse(fs.readFileSync(process.argv[2])); x.authorization_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"; x.minimum_sequence = 2; fs.writeFileSync(process.argv[3], JSON.stringify(x));
NODE
if verify "$fixture/test-owner-authorization.json" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$work/newer-authorization-checkpoint.json" >/dev/null 2>&1; then
  echo "replayed older signed authorization was accepted" >&2; exit 1
fi
runtime_args=("$fixture/test-runtime-narrowing.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-authorization.json" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-owner-ed25519-public.pem" "$checkpoint" "$fixture/test-runtime-narrowing-checkpoint.json")
node "$root/scripts/verify-autonomy-runtime-narrowing.mjs" "${runtime_args[@]}" >/dev/null
if node "$root/scripts/verify-autonomy-runtime-narrowing.mjs" "$fixture/test-runtime-narrowing.json" "$root/docs/autonomy-recovery-worker-registry-v1.json" "${runtime_args[@]:2}" >/dev/null 2>&1; then
  echo "substituted recovery registry was accepted" >&2; exit 1
fi
node - "$fixture/test-runtime-narrowing.json" "$work/forged-narrowing.json" <<'NODE'
const fs = require("fs"); const x = JSON.parse(fs.readFileSync(process.argv[2])); x.entries[0].to_state = "armed-fleet"; fs.writeFileSync(process.argv[3], JSON.stringify(x));
NODE
if node "$root/scripts/verify-autonomy-runtime-narrowing.mjs" "$work/forged-narrowing.json" "${runtime_args[@]:1}" >/dev/null 2>&1; then
  echo "recovery widening was accepted" >&2; exit 1
fi
node - "$fixture/test-runtime-narrowing.json" "$work/truncated-narrowing.json" <<'NODE'
const fs = require("fs"); const x = JSON.parse(fs.readFileSync(process.argv[2])); x.entries = []; fs.writeFileSync(process.argv[3], JSON.stringify(x));
NODE
if node "$root/scripts/verify-autonomy-runtime-narrowing.mjs" "$work/truncated-narrowing.json" "${runtime_args[@]:1}" >/dev/null 2>&1; then
  echo "truncated signed narrowing ledger was accepted" >&2; exit 1
fi

# An editor may recompute a self-digest, but cannot repair the detached owner authorization.
node - "$fixture/coverage-armed-canary.json" "$work/redigested-coverage.json" <<'NODE'
const crypto = require("crypto"), fs = require("fs");
const x = JSON.parse(fs.readFileSync(process.argv[2]));
x.domains.find((d) => d.domain === "micro-routing").coverage = "armed-fleet";
const plain = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const canonical = (v) => plain(v) ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}` : Array.isArray(v) ? `[${v.map(canonical).join(",")}]` : JSON.stringify(v);
delete x.registry_digest; x.registry_digest = `sha256:${crypto.createHash("sha256").update(canonical(x)).digest("hex")}`;
fs.writeFileSync(process.argv[3], JSON.stringify(x));
NODE
if verify "$fixture/test-owner-authorization.json" "$root/docs/autonomy-constitution-v1.json" "$work/redigested-coverage.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$checkpoint" >/dev/null 2>&1; then
  echo "re-digested unsigned coverage was accepted" >&2; exit 1
fi

# A complete attacker replacement (key, fingerprint, and signature) still loses to the external pin.
node - "$fixture/test-owner-authorization.json" "$fixture/test-attacker-ed25519-private.pem" "$fixture/test-attacker-ed25519-public.pem" "$work/attacker.json" <<'NODE'
const crypto = require("crypto"), fs = require("fs");
const x = JSON.parse(fs.readFileSync(process.argv[2]));
const pub = fs.readFileSync(process.argv[4], "utf8");
const key = crypto.createPublicKey(pub);
const plain = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const canonical = (v) => plain(v) ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}` : Array.isArray(v) ? `[${v.map(canonical).join(",")}]` : JSON.stringify(v);
x.authority.public_key_pem = pub;
x.authority.public_key_fingerprint = `sha256:${crypto.createHash("sha256").update(key.export({ type: "spki", format: "der" })).digest("hex")}`;
delete x.signature; x.signature = { algorithm: "Ed25519", value_base64: crypto.sign(null, Buffer.from(canonical(x)), fs.readFileSync(process.argv[3])).toString("base64") };
fs.writeFileSync(process.argv[5], JSON.stringify(x));
NODE
if verify "$work/attacker.json" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$checkpoint" >/dev/null 2>&1; then
  echo "attacker key replacement was accepted" >&2; exit 1
fi

# The intentionally unconfigured production placeholder cannot be admitted under any expected key.
if verify "$root/docs/autonomy-owner-authorization-v1.json" "$root/docs/autonomy-constitution-v1.json" "$root/docs/autonomy-coverage-registry-v1.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$root/docs/autonomy-recovery-worker-registry-v1.json" "$fixture/test-owner-ed25519-public.pem" "$checkpoint" >/dev/null 2>&1; then
  echo "unconfigured production authorization was accepted" >&2; exit 1
fi
node - "$work/oversized.json" "$work/deep.json" <<'NODE'
const fs = require("fs"); fs.writeFileSync(process.argv[2], " ".repeat(1_000_001)); let x = 0; for (let i = 0; i < 65; i++) x = [x]; fs.writeFileSync(process.argv[3], JSON.stringify(x));
NODE
if verify "$work/oversized.json" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$checkpoint" >/dev/null 2>&1; then echo "oversized authorization input was accepted" >&2; exit 1; fi
if verify "$work/deep.json" "$root/docs/autonomy-constitution-v1.json" "$fixture/coverage-armed-canary.json" "$root/docs/autonomy-owner-attestation-registry-v1.json" "$fixture/test-recovery-worker-registry.json" "$fixture/test-owner-ed25519-public.pem" "$checkpoint" >/dev/null 2>&1; then echo "deep authorization input was accepted" >&2; exit 1; fi
echo "autonomy owner authorization tests passed"
