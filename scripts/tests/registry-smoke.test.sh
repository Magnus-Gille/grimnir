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
      "needs_build": true, "persistent_paths": ["/home/magnus/.local/share/alpha"],
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

# ── Repository authority is bounded and machine-readable (#112) ───────────
cat > "$TMP_DIR/bad-repository-authority.json" << 'EOF'
{
  "repository_authority": {
    "default_owner": "owner|unsafe",
    "owner_overrides": [],
    "additional_repositories": [
      { "repo": "../escape", "checkout": "/absolute/path" }
    ]
  },
  "components": []
}
EOF
assert_eq "unsafe repository authority -> exit 1" "1" \
  "$(run_validator "$TMP_DIR/bad-repository-authority.json")"

cat > "$TMP_DIR/duplicate-repository-checkout.json" << 'EOF'
{
  "repository_authority": {
    "default_owner": "Magnus-Gille",
    "owner_overrides": {},
    "additional_repositories": [
      { "repo": "other", "checkout": "alpha" }
    ]
  },
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": null, "port": null,
      "deploy": false, "scan": false, "needs_build": false,
      "systemd_units": []
    }
  ]
}
EOF
assert_eq "repository authority cannot silently shadow a component checkout -> exit 1" "1" \
  "$(run_validator "$TMP_DIR/duplicate-repository-checkout.json")"

# ── rsync persistent-path safety ───────────────────────────────────────────
cat > "$TMP_DIR/missing-persistent-paths.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "rsync deploy without persistent_paths audit -> exit 1" "1" "$(run_validator "$TMP_DIR/missing-persistent-paths.json")"

cat > "$TMP_DIR/internal-persistent-unprotected.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "persistent_paths": ["/srv/alpha/data"],
      "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "persistent path inside rsync target without exclusion -> exit 1" "1" "$(run_validator "$TMP_DIR/internal-persistent-unprotected.json")"

cat > "$TMP_DIR/internal-persistent-protected.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "persistent_paths": ["/srv/alpha/data/db"],
      "rsync_excludes": ["/data/"], "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "ancestor exclusion protects persistent path inside rsync target -> exit 0" "0" "$(run_validator "$TMP_DIR/internal-persistent-protected.json")"

cat > "$TMP_DIR/persistent-equals-target.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "persistent_paths": ["/srv/alpha"],
      "rsync_excludes": ["/data/"], "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "persistent path equal to rsync target -> exit 1" "1" "$(run_validator "$TMP_DIR/persistent-equals-target.json")"

cat > "$TMP_DIR/root-deploy-path.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/", "persistent_paths": ["/var/lib/alpha"],
      "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "filesystem root cannot be an rsync deploy target -> exit 1" "1" "$(run_validator "$TMP_DIR/root-deploy-path.json")"

cat > "$TMP_DIR/trailing-slash-deploy-path.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha/", "persistent_paths": ["/srv/alpha/data"],
      "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "trailing slash cannot bypass deploy-path containment -> exit 1" "1" "$(run_validator "$TMP_DIR/trailing-slash-deploy-path.json")"

cat > "$TMP_DIR/unsafe-rsync-exclude.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "persistent_paths": ["/srv/alpha/data"],
      "rsync_excludes": ["/**/data*"], "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "wildcard rsync exclusion -> exit 1" "1" "$(run_validator "$TMP_DIR/unsafe-rsync-exclude.json")"

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

cat > "$TMP_DIR/out-of-range-port.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": 70000,
      "deploy": false, "scan": true, "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "out-of-range port -> exit 1" "1" "$(run_validator "$TMP_DIR/out-of-range-port.json")"

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

# ── Bad systemd unit name ───────────────────────────────────────────────────
cat > "$TMP_DIR/bad-unit-name.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false,
      "systemd_units": [{ "name": "alpha;rm -rf /", "type": "service" }] }
  ]
}
EOF
assert_eq "invalid systemd unit name -> exit 1" "1" "$(run_validator "$TMP_DIR/bad-unit-name.json")"

# ── Timer semantics are bounded and timer-only ──────────────────────────────
cat > "$TMP_DIR/bad-timer-semantics.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "timer", "timer_semantics": "elapsed-is-fine" }] }
  ]
}
EOF
assert_eq "invalid timer semantics -> exit 1" "1" "$(run_validator "$TMP_DIR/bad-timer-semantics.json")"

cat > "$TMP_DIR/service-timer-semantics.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "timer_semantics": "one-shot" }] }
  ]
}
EOF
assert_eq "timer semantics on service -> exit 1" "1" "$(run_validator "$TMP_DIR/service-timer-semantics.json")"

# ── Registry strings crossing deploy shell boundaries must be strict ───────
cat > "$TMP_DIR/unsafe-component-strings.json" << 'EOF'
{
  "components": [
    { "name": "alpha|evil", "repo": "alpha'evil", "host": "h1;evil", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha$(evil)",
      "persistent_paths": [], "needs_build": false, "systemd_units": [] }
  ]
}
EOF
assert_eq "unsafe name/repo/host/path strings -> exit 1" "1" "$(run_validator "$TMP_DIR/unsafe-component-strings.json")"

# ── Desired runtime state is bounded and internally consistent ─────────────
cat > "$TMP_DIR/bad-runtime-state.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null,
      "deploy": false, "scan": true, "needs_build": false,
      "desired_runtime_state": "paused-maybe", "systemd_units": [] }
  ]
}
EOF
assert_eq "invalid desired runtime state -> exit 1" "1" \
  "$(run_validator "$TMP_DIR/bad-runtime-state.json")"

cat > "$TMP_DIR/not-applicable-with-runtime.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": 3030,
      "deploy": false, "scan": true, "needs_build": false,
      "desired_runtime_state": "not-applicable",
      "systemd_units": [{ "name": "alpha", "type": "service" }] }
  ]
}
EOF
assert_eq "not-applicable runtime cannot declare units or health -> exit 1" "1" \
  "$(run_validator "$TMP_DIR/not-applicable-with-runtime.json")"

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

# ── deploy_mode: valid git-pull passes ──────────────────────────────────────
cat > "$TMP_DIR/deploy-mode-git-pull.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/x", "needs_build": false, "deploy_mode": "git-pull", "systemd_units": [] }
  ]
}
EOF
assert_eq "deploy_mode git-pull -> exit 0" "0" "$(run_validator "$TMP_DIR/deploy-mode-git-pull.json")"

# ── deploy_mode: bogus value fails ──────────────────────────────────────────
cat > "$TMP_DIR/deploy-mode-bogus.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/x", "needs_build": false, "deploy_mode": "ftp", "systemd_units": [] }
  ]
}
EOF
assert_eq "deploy_mode bogus value -> exit 1" "1" "$(run_validator "$TMP_DIR/deploy-mode-bogus.json")"

# ── Host-specific systemd runtime rendering contract (#107) ────────────────
cat > "$TMP_DIR/systemd-runtime-valid.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": 3030,
      "deploy": true, "scan": false, "deploy_path": "/home/alpha/app",
      "persistent_paths": ["/home/alpha/state"], "needs_build": false,
      "systemd_runtime": {
        "user": "alpha", "home": "/home/alpha", "deploy_target": "/home/alpha/app",
        "environment_files": ["/home/alpha/state/env"],
        "sandbox_paths": ["/home/alpha/.ssh/read-only-key"]
      },
      "health_check": { "boundary": "network", "host": "health-alpha", "paths": ["/health"] },
      "systemd_units": [{ "name": "alpha", "type": "service" }] }
  ]
}
EOF
assert_eq "valid systemd runtime rendering contract -> exit 0" "0" \
  "$(run_validator "$TMP_DIR/systemd-runtime-valid.json")"

cat > "$TMP_DIR/systemd-runtime-unregistered-env.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": 3030,
      "deploy": true, "scan": false, "deploy_path": "/home/alpha/app",
      "persistent_paths": ["/home/alpha/state"], "needs_build": false,
      "systemd_runtime": {
        "user": "alpha", "home": "/home/alpha", "deploy_target": "/home/alpha/app",
        "environment_files": ["/home/other/private.env"],
        "sandbox_paths": []
      },
      "health_check": { "boundary": "network", "host": "health-alpha", "paths": ["/health"] },
      "systemd_units": [{ "name": "alpha", "type": "service" }] }
  ]
}
EOF
assert_eq "environment file outside deploy/persistent roots -> exit 1" "1" \
  "$(run_validator "$TMP_DIR/systemd-runtime-unregistered-env.json")"

cat > "$TMP_DIR/network-health-missing-host.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "ssh-alpha", "port": 3030,
      "deploy": true, "scan": false, "deploy_path": "/home/alpha/app",
      "persistent_paths": [], "needs_build": false,
      "health_check": { "boundary": "network", "paths": ["/health"] },
      "systemd_units": [{ "name": "alpha", "type": "service" }] }
  ]
}
EOF
assert_eq "network health without an explicit host -> exit 1" "1" \
  "$(run_validator "$TMP_DIR/network-health-missing-host.json")"

cat > "$TMP_DIR/network-health-private-ip.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "ssh-alpha", "port": 3030,
      "deploy": true, "scan": false, "deploy_path": "/home/alpha/app",
      "persistent_paths": [], "needs_build": false,
      "health_check": { "boundary": "network", "host": "100.64.0.1", "paths": ["/health"] },
      "systemd_units": [{ "name": "alpha", "type": "service" }] }
  ]
}
EOF
assert_eq "network health private IP locator -> exit 1" "1" \
  "$(run_validator "$TMP_DIR/network-health-private-ip.json")"

cat > "$TMP_DIR/host-health-without-host.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "ssh-alpha", "port": 3030,
      "deploy": true, "scan": false, "deploy_path": "/home/alpha/app",
      "persistent_paths": [], "needs_build": false,
      "health_check": { "boundary": "host", "paths": ["/health"] },
      "systemd_units": [{ "name": "alpha", "type": "service" }] }
  ]
}
EOF
assert_eq "host-boundary health retains implicit local targets -> exit 0" "0" \
  "$(run_validator "$TMP_DIR/host-health-without-host.json")"

cat > "$TMP_DIR/systemd-runtime-mismatch.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1.local", "port": 3030,
      "deploy": true, "scan": false, "deploy_path": "/home/alpha/app",
      "persistent_paths": [], "needs_build": false,
      "systemd_runtime": {
        "user": "missing user", "home": "/home/alpha", "deploy_target": "/home/other/app",
        "environment_files": ["/home/alpha/private.env"],
        "sandbox_paths": ["/tmp/unregistered"]
      },
      "systemd_units": [{ "name": "alpha", "type": "service" }] }
  ]
}
EOF
assert_eq "mismatched runtime identity/paths and missing health boundary -> exit 1" "1" \
  "$(run_validator "$TMP_DIR/systemd-runtime-mismatch.json")"

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

# ── registry.js structured deploy-query invariant (#43 / #33) ──────────────
# The JSON Lines `deploy` projection derives each component's primary unit_type/scope from
# systemd_units[0]. hugin must stay a user-scoped rsync service even after a
# system-scoped `hugin-daily-analysis` timer was appended to its systemd_units —
# appending units must never change the deploy row. Pin the real services.json
# plus the ordering contract on a synthetic fixture.
REGISTRY_JS="$SCRIPT_DIR/../lib/registry.js"
repository_authority_rows="$(
  REGISTRY_PATH="$REPO_REGISTRY" QUERY=repository-authority \
    node --input-type=commonjs "$REGISTRY_JS"
)"
assert_eq "Heimdall checkout authority is canonical public repo" \
  "heimdall|Magnus-Gille/heimdall" \
  "$(printf '%s\n' "$repository_authority_rows" | grep '^heimdall|')"
assert_eq "Skuld checkout uses the default canonical owner" \
  "skuld|Magnus-Gille/skuld" \
  "$(printf '%s\n' "$repository_authority_rows" | grep '^skuld|')"
assert_eq "Gille Inference canonical checkout maps to public authority" \
  "gille-inference|Magnus-Gille/gille-inference" \
  "$(printf '%s\n' "$repository_authority_rows" | grep '^gille-inference|')"

deploy_field() {  # $1 = registry path, $2 = component name, $3 = field
  REGISTRY_PATH="$1" QUERY=deploy node --input-type=commonjs "$REGISTRY_JS" 2>/dev/null \
    | COMPONENT_NAME="$2" COMPONENT_FIELD="$3" node --input-type=commonjs -e '
        var input = "";
        process.stdin.on("data", function (chunk) { input += chunk; });
        process.stdin.on("end", function () {
          var rows = input.trim().split("\n").filter(Boolean).map(JSON.parse);
          var row = rows.filter(function (r) { return r.name === process.env.COMPONENT_NAME; })[0];
          if (!row) process.exit(1);
          var value = row[process.env.COMPONENT_FIELD];
          process.stdout.write(value !== null && typeof value === "object" ? JSON.stringify(value) : String(value));
        });
      '
}
assert_eq "real services.json: hugin primary unit remains service" "service" \
  "$(deploy_field "$REPO_REGISTRY" hugin unit_type)"
assert_eq "real services.json: hugin deploy scope remains user" "user" \
  "$(deploy_field "$REPO_REGISTRY" hugin unit_scope)"
assert_eq "real services.json: hugin structured units include appended timer" \
  '[{"name":"hugin","type":"service","scope":"user"},{"name":"hugin-daily-analysis","type":"timer"}]' \
  "$(deploy_field "$REPO_REGISTRY" hugin systemd_units)"

assert_eq "real services.json: Heimdall deploy refreshes boot-check timer companion" \
  '[{"name":"heimdall","type":"service"},{"name":"heimdall-collect","type":"timer"},{"name":"heimdall-maintain","type":"timer"},{"name":"heimdall-boot-check","type":"timer"}]' \
  "$(deploy_field "$REPO_REGISTRY" heimdall systemd_units)"
assert_eq "real services.json: Heimdall deploy carries its health port" \
  "3033" "$(deploy_field "$REPO_REGISTRY" heimdall port)"
assert_eq "real services.json: munin-memory remains outside runtime rendering scope" \
  "null" "$(deploy_field "$REPO_REGISTRY" munin-memory systemd_runtime)"
assert_eq "real services.json: Heimdall owns the reviewed host runtime contract" \
  '{"user":"magnus","home":"/home/magnus","deploy_target":"/home/magnus/repos/heimdall","environment_files":["/home/magnus/.heimdall/env"],"sandbox_paths":["/home/magnus/.munin-memory","/home/magnus/.ssh/heimdall_ed25519"]}' \
  "$(deploy_field "$REPO_REGISTRY" heimdall systemd_runtime)"
assert_eq "real services.json: Heimdall health uses the network consumer boundary" \
  '{"boundary":"network","host":"huginmunin","paths":["/health","/api/health"]}' \
  "$(deploy_field "$REPO_REGISTRY" heimdall health_check)"

assert_eq "real services.json: skuld timer deploys via user manager" \
  "user" "$(deploy_field "$REPO_REGISTRY" skuld unit_scope)"

component_persistent_paths() {  # $1 = registry path, $2 = component name
  REGISTRY_PATH="$1" COMPONENT_NAME="$2" node --input-type=commonjs -e '
    var data = require(process.env.REGISTRY_PATH);
    var component = data.components.filter(function (c) { return c.name === process.env.COMPONENT_NAME; })[0];
    process.stdout.write(JSON.stringify(component && component.persistent_paths || []));
  '
}
assert_eq "real services.json: Verdandi protects legacy data and declares canonical migration target" \
  '["/home/magnus/repos/verdandi/data","/home/magnus/.local/share/verdandi"]' \
  "$(component_persistent_paths "$REPO_REGISTRY" verdandi)"

assert_eq "real services.json: Verdandi deploy carries legacy data exclusion" \
  '["/data/"]' "$(deploy_field "$REPO_REGISTRY" verdandi rsync_excludes)"

validate_field() {  # $1 = registry path, $2 = component name, $3 = zero-based field
  REGISTRY_PATH="$1" QUERY=validate node --input-type=commonjs "$REGISTRY_JS" 2>/dev/null \
    | COMPONENT_NAME="$2" COMPONENT_FIELD="$3" node --input-type=commonjs -e '
        var input = "";
        process.stdin.on("data", function (chunk) { input += chunk; });
        process.stdin.on("end", function () {
          var row = input.trim().split("\n").filter(Boolean)
            .map(function (line) { return line.split("|"); })
            .filter(function (fields) { return fields[0] === process.env.COMPONENT_NAME; })[0];
          if (!row) process.exit(1);
          process.stdout.write(row[Number(process.env.COMPONENT_FIELD)] || "");
        });
      '
}
assert_eq "Verdandi validation projection is intentionally stopped" "stopped" \
  "$(validate_field "$REPO_REGISTRY" verdandi 7)"
assert_eq "Verdandi remains deployment-marker managed" "true" \
  "$(validate_field "$REPO_REGISTRY" verdandi 6)"
assert_eq "Brokkr validation projection keeps active timers" "active" \
  "$(validate_field "$REPO_REGISTRY" brokkr 7)"
assert_eq "Brokkr validation projection skips deploy markers" "false" \
  "$(validate_field "$REPO_REGISTRY" brokkr 6)"
assert_eq "Fortnox has no managed runtime" "not-applicable" \
  "$(validate_field "$REPO_REGISTRY" fortnox-mcp 7)"

cat > "$TMP_DIR/order.json" << 'EOF'
{
  "components": [
    { "name": "svc", "repo": "svc", "host": "h1.local", "port": 3030, "deploy": true, "scan": false, "deploy_path": "/x", "needs_build": true,
      "systemd_units": [ { "name": "svc", "type": "service", "scope": "user" }, { "name": "svc-daily", "type": "timer" } ] }
  ]
}
EOF
assert_eq "deploy JSON derives type from systemd_units[0]" "service" \
  "$(deploy_field "$TMP_DIR/order.json" svc unit_type)"
assert_eq "deploy JSON derives scope from systemd_units[0]" "user" \
  "$(deploy_field "$TMP_DIR/order.json" svc unit_scope)"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
