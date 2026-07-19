#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY_JS="$ROOT/scripts/lib/registry.js"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

actual="$(cd "$ROOT" && QUERY=is-example node --input-type=commonjs "$REGISTRY_JS")"
[[ "$actual" == "true" ]] || fail "the committed registry must identify itself as an example"

output_file="$(mktemp)"
trap 'rm -f "$output_file"' EXIT
rc=0
(cd "$ROOT" && ./scripts/deploy.sh grimnir) >"$output_file" 2>&1 || rc=$?

[[ "$rc" -ne 0 ]] || fail "deploy accepted the committed example registry"
grep -qi "example registry" "$output_file" || fail "deploy did not explain how to provide a private registry"

echo "PASS: committed example registry cannot trigger deployment"
