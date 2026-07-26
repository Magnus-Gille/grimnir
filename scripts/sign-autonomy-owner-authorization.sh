#!/usr/bin/env bash
# Owner-operated helper. It never creates, imports, stores, or prints a private key.
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "usage: $0 /explicit/path/to/owner-ed25519-private.pem unsigned-manifest.json" >&2
  exit 64
fi
private_key=$1
manifest=$2
[[ -f "$private_key" && -r "$private_key" ]] || { echo "private key path is not readable" >&2; exit 66; }
[[ -f "$manifest" && -r "$manifest" ]] || { echo "manifest path is not readable" >&2; exit 66; }
canonical_file=$(mktemp "${TMPDIR:-/tmp}/grimnir-owner-authorization.XXXXXX")
trap 'rm -f "$canonical_file"' EXIT
node - "$manifest" <<'NODE' >"$canonical_file"
const fs = require("fs");
const value = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
delete value.signature;
const plain = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
const canonical = (x) => plain(x) ? `{${Object.keys(x).sort().map((k) => `${JSON.stringify(k)}:${canonical(x[k])}`).join(",")}}` : Array.isArray(x) ? `[${x.map(canonical).join(",")}]` : JSON.stringify(x);
process.stdout.write(canonical(value));
NODE
openssl pkeyutl -sign -inkey "$private_key" -rawin -in "$canonical_file" | base64 | tr -d '\n'
echo
