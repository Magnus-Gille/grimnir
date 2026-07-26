#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fixture="$root/tests/fixtures/autonomy-contract"
work=$(mktemp -d "${TMPDIR:-/tmp}/grimnir-owner-auth.XXXXXX")
trap 'rm -rf "$work"' EXIT
verify() {
  node "$root/scripts/verify-autonomy-owner-authorization.mjs" "$@"
}
checkpoint="$fixture/test-owner-authorization-checkpoint.json"
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
