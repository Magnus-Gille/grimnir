#!/usr/bin/env bash
# registry-smoke.test.sh — unit tests for validate-registry.js
# (issue #48: services.json schema/consistency smoke check on every PR)
#
# Builds a set of fixture services.json files (one valid, several broken in a
# specific way) and asserts that scripts/lib/validate-registry.js accepts the
# valid one and rejects each broken one with a non-zero exit — without ever
# crashing uncontrolled (no bare excepts, no unhandled exceptions).
#
# Usage:
#   bash scripts/tests/registry-smoke.test.sh
#
# Exit codes: 0 = all assertions passed, 1 = at least one assertion failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../lib/validate-registry.js"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# Runs the validator against $1 (a fixture path) and returns its exit code
# via echo, without letting `set -e` abort this script on a non-zero exit.
run_validator() {
  local fixture="$1"
  local rc=0
  REGISTRY_PATH="$fixture" node --input-type=commonjs "$VALIDATOR" > /dev/null 2>&1 || rc=$?
  echo "$rc"
}

# Runs the validator and asserts it fails cleanly (exit 1, a controlled
# "validation FAILED" message on stderr) rather than crashing with a raw
# Node stack trace (TypeError) on malformed/null entries.
assert_clean_failure() {
  local desc="$1" fixture="$2"
  local rc=0
  local stderr
  stderr="$(REGISTRY_PATH="$fixture" node --input-type=commonjs "$VALIDATOR" 2>&1 >/dev/null)" || rc=$?
  assert_eq "$desc: exit 1" "1" "$rc"
  if [[ "$stderr" == *"TypeError"* ]]; then
    echo "  FAIL: $desc: stderr must not contain an uncaught TypeError — got: $stderr"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc: stderr has no uncaught TypeError"
    PASS=$((PASS + 1))
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "registry smoke-check tests"
echo "==========================="

# ── Valid registry ─────────────────────────────────────────────────────────
cat > "$TMP_DIR/valid.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1.local", "port": 3030,
      "deploy": true, "scan": true, "deploy_path": "/home/magnus/repos/alpha",
      "needs_build": true,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    },
    {
      "name": "beta", "repo": "beta", "host": null, "port": null,
      "deploy": false, "scan": true, "needs_build": false,
      "systemd_units": []
    }
  ],
  "nodes": [
    { "name": "h1", "hostname": "h1.local", "role": "service-host", "status": "active" }
  ]
}
EOF
assert_eq "valid registry -> exit 0" "0" "$(run_validator "$TMP_DIR/valid.json")"

# ── Real repo registry (regression: must always pass) ─────────────────────
REPO_REGISTRY="$SCRIPT_DIR/../../services.json"
assert_eq "real services.json -> exit 0" "0" "$(run_validator "$REPO_REGISTRY")"

# ── Malformed JSON ──────────────────────────────────────────────────────────
echo '{ not valid json' > "$TMP_DIR/bad-json.json"
assert_eq "malformed JSON -> exit 1" "1" "$(run_validator "$TMP_DIR/bad-json.json")"

# ── Missing components array ────────────────────────────────────────────────
echo '{ "nodes": [] }' > "$TMP_DIR/no-components.json"
assert_eq "missing components array -> exit 1" "1" "$(run_validator "$TMP_DIR/no-components.json")"

# ── Duplicate component name ────────────────────────────────────────────────
cat > "$TMP_DIR/dup-name.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false, "systemd_units": [] },
    { "name": "alpha", "repo": "alpha2", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "duplicate component name -> exit 1" "1" "$(run_validator "$TMP_DIR/dup-name.json")"

# ── Duplicate port ───────────────────────────────────────────────────────────
cat > "$TMP_DIR/dup-port.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": 3030, "deploy": false, "scan": true, "needs_build": false, "systemd_units": [] },
    { "name": "beta", "repo": "beta", "host": "h1.local", "port": 3030, "deploy": false, "scan": true, "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "duplicate port -> exit 1" "1" "$(run_validator "$TMP_DIR/dup-port.json")"

# ── deploy=true without deploy_path ─────────────────────────────────────────
cat > "$TMP_DIR/missing-deploy-path.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": 3030, "deploy": true, "scan": true, "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "deploy=true without deploy_path -> exit 1" "1" "$(run_validator "$TMP_DIR/missing-deploy-path.json")"

# ── deploy=true without host ────────────────────────────────────────────────
cat > "$TMP_DIR/missing-host.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": 3030, "deploy": true, "scan": true, "deploy_path": "/x", "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "deploy=true without host -> exit 1" "1" "$(run_validator "$TMP_DIR/missing-host.json")"

# ── Missing required field (repo) ───────────────────────────────────────────
cat > "$TMP_DIR/missing-repo.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "missing required field -> exit 1" "1" "$(run_validator "$TMP_DIR/missing-repo.json")"

# ── Bad systemd_units shape (not an array) ──────────────────────────────────
cat > "$TMP_DIR/bad-units.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false, "systemd_units": "not-an-array" }
  ]
}
EOF
assert_eq "systemd_units not an array -> exit 1" "1" "$(run_validator "$TMP_DIR/bad-units.json")"

# ── Bad systemd unit type ───────────────────────────────────────────────────
cat > "$TMP_DIR/bad-unit-type.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "daemon" }] }
  ]
}
EOF
assert_eq "invalid systemd unit type -> exit 1" "1" "$(run_validator "$TMP_DIR/bad-unit-type.json")"

# ── Duplicate node name ──────────────────────────────────────────────────────
cat > "$TMP_DIR/dup-node.json" << 'EOF'
{
  "components": [],
  "nodes": [
    { "name": "h1", "hostname": "h1.local" },
    { "name": "h1", "hostname": "h2.local" }
  ]
}
EOF
assert_eq "duplicate node name -> exit 1" "1" "$(run_validator "$TMP_DIR/dup-node.json")"

# ── Missing file entirely ───────────────────────────────────────────────────
assert_eq "missing file -> exit 1" "1" "$(run_validator "$TMP_DIR/does-not-exist.json")"

# ── Malformed shapes must fail cleanly, not crash with an uncaught TypeError ─
echo 'null' > "$TMP_DIR/top-level-null.json"
assert_clean_failure "top-level null" "$TMP_DIR/top-level-null.json"

echo '[]' > "$TMP_DIR/top-level-array.json"
assert_clean_failure "top-level array" "$TMP_DIR/top-level-array.json"

echo '{ "components": [null] }' > "$TMP_DIR/null-component.json"
assert_clean_failure "null entry in components" "$TMP_DIR/null-component.json"

cat > "$TMP_DIR/null-unit.json" << 'EOF'
{ "components": [
  { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false,
    "systemd_units": [null] }
] }
EOF
assert_clean_failure "null entry in systemd_units" "$TMP_DIR/null-unit.json"

echo '{ "components": [], "nodes": [null] }' > "$TMP_DIR/null-node.json"
assert_clean_failure "null entry in nodes" "$TMP_DIR/null-node.json"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
