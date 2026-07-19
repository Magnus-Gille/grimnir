#!/usr/bin/env bash
# Publication/deployment contract checks that do not need a live systemd host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCAN_UNIT="$ROOT/systemd/grimnir-security-scan.service"
VALIDATE_UNIT="$ROOT/systemd/grimnir-validate.service"
SCHEMA="$ROOT/docs/learning-task-contract-v1.schema.json"
CREDENTIAL_LIB="$ROOT/scripts/lib/credentials.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_unit_line() {
  local unit=$1 expected=$2
  grep -Fxq -- "$expected" "$unit" || fail "$(basename "$unit") missing: $expected"
}

# shellcheck source=scripts/lib/credentials.sh
source "$CREDENTIAL_LIB"
credential_fixture="$(mktemp -d)"
trap 'rm -rf "$credential_fixture"' EXIT
printf '%s\n' 'synthetic-test-token' > "$credential_fixture/valid"
[[ "$(read_credential_file "$credential_fixture/valid" munin-api-key)" == \
   "synthetic-test-token" ]] || fail "single-line systemd credential did not round-trip"
printf '%s\n%s\n' 'first' 'second' > "$credential_fixture/multiline"
if read_credential_file "$credential_fixture/multiline" munin-api-key >/dev/null 2>&1; then
  fail "multi-line credential must be rejected"
fi
if read_credential_file "$credential_fixture/missing" munin-api-key >/dev/null 2>&1; then
  fail "missing credential must be rejected"
fi

for unit in "$SCAN_UNIT" "$VALIDATE_UNIT"; do
  assert_unit_line "$unit" "LoadCredential=munin-api-key:/etc/grimnir/credentials/munin-api-key"
  grep -Eq '^ExecStart=.*--munin-token-file %d/munin-api-key' "$unit" || \
    fail "$(basename "$unit") does not consume the systemd credential path"
  if grep -Eq '^Environment=.*MUNIN_TOKEN=' "$unit"; then
    fail "$(basename "$unit") exposes the Munin token through Environment="
  fi
done

assert_unit_line "$SCAN_UNIT" "Environment=REPOS_DIR=/srv/grimnir/source"
assert_unit_line "$SCAN_UNIT" "ReadOnlyPaths=/srv/grimnir/source"

schema_id="$(SCHEMA_PATH="$SCHEMA" node --input-type=commonjs -e \
  'var schema = JSON.parse(require("fs").readFileSync(process.env.SCHEMA_PATH, "utf8"));
   process.stdout.write(schema[String.fromCharCode(36) + "id"] || "")')"
[[ "$schema_id" == "urn:grimnir:contract:learning-task:v1" ]] || \
  fail "canonical schema id is not the stable Grimnir URN: $schema_id"

echo "PASS: deployment publication configuration is pinned and credential-safe"
