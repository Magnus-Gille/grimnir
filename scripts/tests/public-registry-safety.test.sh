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
unmarked_registry="$(mktemp)"
private_registry="$(mktemp)"
trap 'rm -f "$output_file" "$unmarked_registry" "$private_registry"' EXIT
printf '%s\n' '{"components":[]}' > "$unmarked_registry"
printf '%s\n' '{"public_example":false,"components":[]}' > "$private_registry"

actual="$(REGISTRY_PATH="$unmarked_registry" QUERY=is-example node --input-type=commonjs "$REGISTRY_JS")"
[[ "$actual" == "true" ]] || fail "an unmarked registry must fail closed as example data"
actual="$(REGISTRY_PATH="$private_registry" QUERY=is-example node --input-type=commonjs "$REGISTRY_JS")"
[[ "$actual" == "false" ]] || fail "an explicitly private registry must be deployable"

rc=0
(cd "$ROOT" && ./scripts/deploy.sh hugin) >"$output_file" 2>&1 || rc=$?

[[ "$rc" -ne 0 ]] || fail "deploy accepted the committed example registry"
grep -qi "example registry" "$output_file" || fail "deploy did not explain how to provide a private registry"

rc=0
REGISTRY_PATH="$ROOT/services.json" "$ROOT/scripts/deploy.sh" hugin >"$output_file" 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "explicit REGISTRY_PATH bypassed the example-registry guard"
grep -qi "example registry" "$output_file" || fail "explicit example registry was not explained"

echo "PASS: committed example registry cannot trigger deployment"
