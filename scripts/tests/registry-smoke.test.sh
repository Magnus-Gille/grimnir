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

# Node/Substrate v2 may be pinned for an explicitly v2 workload requirement.
# The registry validates only the closed provenance tuple; the owning contract
# and placement validators remain responsible for semantic compatibility.
REPO_REGISTRY="$REPO_REGISTRY" OUTPUT="$TMP_DIR/valid-workload-v2.json" node --input-type=commonjs -e '
  const fs = require("fs");
  const registry = JSON.parse(fs.readFileSync(process.env.REPO_REGISTRY, "utf8"));
  registry.components[0].workload_contract.schema_version = "v2";
  fs.writeFileSync(process.env.OUTPUT, JSON.stringify(registry));
'
assert_eq "v2 workload contract provenance -> exit 0" "0" "$(run_validator "$TMP_DIR/valid-workload-v2.json")"

# Managed legacy nodes remain observable without becoming workload deployment
# targets. This is the Grimnir-side regression for issue #190.
NODE_JSON="$(REGISTRY_PATH="$REPO_REGISTRY" QUERY=nodes-json node --input-type=commonjs "$SCRIPT_DIR/../lib/registry.js")"
if NODE_JSON="$NODE_JSON" node -e '
  const nodes = JSON.parse(process.env.NODE_JSON);
  const node = nodes.find((candidate) => candidate.node_id === "node-munin-zero");
  if (!node || node.name !== "munin-zero" || node.hostname !== "munin-zero.local" || node.role !== "memory-appliance" || node.status !== "active" || node.monitor !== true) process.exit(1);
'; then
  echo "  PASS: munin-zero is an active monitored managed node"
  PASS=$((PASS + 1))
else
  echo "  FAIL: munin-zero is an active monitored managed node"
  FAIL=$((FAIL + 1))
fi
if REGISTRY_PATH="$REPO_REGISTRY" node -e '
  const registry = require(process.env.REGISTRY_PATH);
  if (registry.components.some((component) => component.target_node_id === "node-munin-zero")) process.exit(1);
'; then
  echo "  PASS: munin-zero is not a component deployment target"
  PASS=$((PASS + 1))
else
  echo "  FAIL: munin-zero is not a component deployment target"
  FAIL=$((FAIL + 1))
fi

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

cat > "$TMP_DIR/legacy-repository-authority.json" << 'EOF'
{
  "repository_authority": {
    "default_owner": "Magnus-Gille",
    "owner_overrides": {},
    "additional_repositories": []
  },
  "components": []
}
EOF
assert_eq "repository authority with canonical checkout names remains valid" "0" \
  "$(run_validator "$TMP_DIR/legacy-repository-authority.json")"

cat > "$TMP_DIR/bad-repository-checkout-override.json" << 'EOF'
{
  "repository_authority": {
    "default_owner": "Magnus-Gille",
    "owner_overrides": {},
    "checkout_overrides": { "alpha": "elsewhere" },
    "additional_repositories": []
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
assert_eq "repository checkout overrides are rejected as host-specific authority" "1" \
  "$(run_validator "$TMP_DIR/bad-repository-checkout-override.json")"

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

# ── external_environment_files (issue #200) ─────────────────────────────────
cat > "$TMP_DIR/valid-external-env.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "persistent_paths": [], "needs_build": false,
      "deploy_mode": "git-pull",
      "external_environment_files": ["/etc/alpha/owner.env"],
      "systemd_units": [] }
  ]
}
EOF
assert_eq "canonical external environment file declaration -> exit 0" "0" "$(run_validator "$TMP_DIR/valid-external-env.json")"

cat > "$TMP_DIR/nonarray-external-env.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "persistent_paths": [], "needs_build": false,
      "external_environment_files": "/etc/alpha/owner.env",
      "systemd_units": [] }
  ]
}
EOF
assert_eq "non-array external_environment_files -> exit 1" "1" "$(run_validator "$TMP_DIR/nonarray-external-env.json")"

cat > "$TMP_DIR/relative-external-env.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": null, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "persistent_paths": [], "needs_build": false,
      "external_environment_files": ["../etc/owner.env"],
      "systemd_units": [] }
  ]
}
EOF
assert_eq "non-canonical external environment file -> exit 1" "1" "$(run_validator "$TMP_DIR/relative-external-env.json")"

cat > "$TMP_DIR/rendered-external-env.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": "h1", "port": 3030, "deploy": true, "scan": false,
      "deploy_path": "/srv/alpha", "persistent_paths": [], "needs_build": false,
      "external_environment_files": ["/etc/alpha/owner.env"],
      "systemd_runtime": { "user": "alpha", "home": "/home/alpha", "deploy_target": "/srv/alpha",
        "environment_files": [], "sandbox_paths": [] },
      "health_check": { "boundary": "host", "paths": ["/health"] },
      "systemd_units": [{ "name": "alpha", "type": "service" }] }
  ]
}
EOF
assert_eq "external_environment_files with systemd_runtime -> exit 1" "1" "$(run_validator "$TMP_DIR/rendered-external-env.json")"

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

# ── Timer companion overrides are bounded and timer-only ───────────────────
cat > "$TMP_DIR/service-name-on-service.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "service_name": "alpha-worker" }] }
  ]
}
EOF
assert_eq "service_name on service -> exit 1" "1" "$(run_validator "$TMP_DIR/service-name-on-service.json")"

cat > "$TMP_DIR/bad-timer-service-name.json" << 'EOF'
{
  "components": [
    { "name": "alpha", "repo": "alpha", "host": null, "port": null, "deploy": false, "scan": true, "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "timer", "service_name": "alpha;worker" }] }
  ]
}
EOF
assert_eq "unsafe timer service_name -> exit 1" "1" "$(run_validator "$TMP_DIR/bad-timer-service-name.json")"

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
# systemd_units[0]. Hugin's primary unit must stay a user-scoped rsync service
# while its two user-scoped timers remain declared in the owning contract. Pin
# the real services.json plus the ordering contract on a synthetic fixture.
REGISTRY_JS="$SCRIPT_DIR/../lib/registry.js"
repository_authority_rows="$(
  REGISTRY_PATH="$REPO_REGISTRY" QUERY=repository-authority \
    node --input-type=commonjs "$REGISTRY_JS"
)"
assert_eq "Heimdall checkout authority uses its canonical repository name" \
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
hugin_units="$(deploy_field "$REPO_REGISTRY" hugin systemd_units)"
assert_eq "real services.json: hugin declares the live service and timer contract" \
  '[{"name":"hugin","type":"service","scope":"user","boot_enable":true},{"name":"hugin-daily-exam-factory","type":"timer","scope":"user"},{"name":"hugin-experiment-cadence","type":"timer","scope":"user"}]' \
  "$hugin_units"
assert_eq "real services.json: retired hugin daily-analysis timer is absent" \
  "false" "$(printf '%s\n' "$hugin_units" | grep -Fq 'hugin-daily-analysis' && echo true || echo false)"

assert_eq "real services.json: Heimdall deploy refreshes boot-check timer companion" \
  '[{"name":"heimdall","type":"service","boot_enable":true},{"name":"heimdall-collect","type":"timer"},{"name":"heimdall-maintain","type":"timer"},{"name":"heimdall-boot-check","type":"timer"}]' \
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

assert_eq "real services.json: Heimdall protects host-owned fleet-agent state and its producer-token rollback backup" \
  '["/home/magnus/.heimdall","/home/magnus/repos/heimdall/agent/config.env","/home/magnus/repos/heimdall/agent/VERSION","/home/magnus/repos/heimdall/agent/config.env.pre-producer-tokens"]' \
  "$(component_persistent_paths "$REPO_REGISTRY" heimdall)"

assert_eq "real services.json: Heimdall deploy carries fleet-agent exclusions" \
  '["/agent/config.env","/agent/VERSION","/agent/config.env.pre-producer-tokens"]' "$(deploy_field "$REPO_REGISTRY" heimdall rsync_excludes)"

assert_eq "real services.json: grimnir deploy carries the declared external environment file" \
  '["/home/magnus/.config/grimnir/security-scan.env"]' "$(deploy_field "$REPO_REGISTRY" grimnir external_environment_files)"

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

# ── Owning-repository deployments (mimir search reader) ───────────────────
# Owning-repo deploy entry points are a separate registry section: they route
# through scripts/guarded-deploy.sh and are never selected by deploy.sh.
GUARDED_DEPLOY="$SCRIPT_DIR/../guarded-deploy.sh"

owning_query() {  # $1 = registry path; prints JSON Lines
  REGISTRY_PATH="$1" QUERY=owning-deploys node --input-type=commonjs "$REGISTRY_JS"
}
owning_field() {  # $1 = registry, $2 = entry name, $3 = JS expression over `entry`
  owning_query "$1" | ENTRY_NAME="$2" FIELD_EXPR="$3" node --input-type=commonjs -e '
    var input = "";
    process.stdin.on("data", function (chunk) { input += chunk; });
    process.stdin.on("end", function () {
      var entry = input.trim().split("\n").filter(Boolean).map(function (l) { return JSON.parse(l); })
        .filter(function (e) { return e.name === process.env.ENTRY_NAME; })[0];
      if (!entry) process.exit(1);
      process.stdout.write(String(eval(process.env.FIELD_EXPR)));
    });
  '
}

assert_eq "real services.json: mimir-search-reader owns its deploy command" \
  "./scripts/deploy-search-reader.sh" \
  "$(owning_field "$REPO_REGISTRY" mimir-search-reader 'entry.command.join(" ")')"
assert_eq "real services.json: mimir-search-reader targets node-m5 in the mimir repo" \
  "mimir@node-m5" \
  "$(owning_field "$REPO_REGISTRY" mimir-search-reader 'entry.repo + "@" + entry.target_node_id')"
assert_eq "real services.json: mimir-search-reader couples the Mac client pin" \
  "node-laptop:.config/mimir-search/client.json:release,package_sha256" \
  "$(owning_field "$REPO_REGISTRY" mimir-search-reader 'entry.coupled_state.map(function (s) { return s.node_id + ":" + s.home_relative_path + ":" + s.fields.join(","); }).join(";")')"
assert_eq "real services.json: reader listener is the registered loopback port" \
  "8791" "$(owning_field "$REPO_REGISTRY" mimir-search-reader 'entry.loopback_port')"

# The central deploy query must never select an owning-repo deployment.
CENTRAL_DEPLOY_NAMES="$(REGISTRY_PATH="$REPO_REGISTRY" QUERY=deploy node --input-type=commonjs "$REGISTRY_JS" \
  | node --input-type=commonjs -e '
      var input = "";
      process.stdin.on("data", function (chunk) { input += chunk; });
      process.stdin.on("end", function () {
        process.stdout.write(input.trim().split("\n").map(function (l) { return JSON.parse(l).name; }).join(" "));
      });
    ')"
case " $CENTRAL_DEPLOY_NAMES " in
  *" mimir-search-reader "*) echo "  FAIL: central deploy query must not select mimir-search-reader"; FAIL=$((FAIL + 1)) ;;
  *) echo "  PASS: central deploy query does not select mimir-search-reader"; PASS=$((PASS + 1)) ;;
esac
assert_eq "registries without owning_repo_deployments yield no owning-deploys rows" "" \
  "$(owning_query "$TMP_DIR/valid.json")"

# Each mutation of the real registry must fail validation cleanly.
mutate_owning() {  # $1 = fixture name, $2 = JS mutation over `entry` and `registry`
  REPO_REGISTRY="$REPO_REGISTRY" OUTPUT="$TMP_DIR/$1.json" MUTATION="$2" node --input-type=commonjs -e '
    var fs = require("fs");
    var registry = JSON.parse(fs.readFileSync(process.env.REPO_REGISTRY, "utf8"));
    var entry = registry.owning_repo_deployments[0];
    eval(process.env.MUTATION);
    fs.writeFileSync(process.env.OUTPUT, JSON.stringify(registry));
  '
}
reject_owning() {  # $1 = description, $2 = JS mutation
  local fixture
  fixture="owning-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mutate_owning "$fixture" "$2"
  assert_clean_failure "owning deploy: $1" "$TMP_DIR/$fixture.json"
}

reject_owning "unknown field"                "entry.shell = \"bash -c x\""
reject_owning "repo not registered"          "entry.repo = \"not-a-repo\""
reject_owning "target node not registered"   "entry.target_node_id = \"node-missing\""
reject_owning "missing target node"          "delete entry.target_node_id"
reject_owning "command escapes the repo"     "entry.command = [\"./scripts/../../evil.sh\"]"
reject_owning "command is absolute"          "entry.command = [\"/usr/bin/evil\"]"
reject_owning "command is a bare name"       "entry.command = [\"deploy.sh\"]"
reject_owning "command has shell metachar"   "entry.command = [\"./scripts/deploy-search-reader.sh\", \"x;reboot\"]"
reject_owning "command is a string"          "entry.command = \"./scripts/deploy-search-reader.sh\""
reject_owning "command is empty"             "entry.command = []"
reject_owning "command repeats revision arg" "entry.command.push(\"--release\")"
reject_owning "revision argument missing"    "delete entry.revision_argument"
reject_owning "revision argument malformed"  "entry.revision_argument = \"release\""
reject_owning "release root not canonical"   "entry.release_root = \"/home/magnus/releases/\""
reject_owning "marker inside release root"   "entry.deployed_marker = entry.release_root + \"/.deployed-commit\""
reject_owning "marker missing"               "delete entry.deployed_marker"
reject_owning "port collides with component" "entry.loopback_port = 3031"
reject_owning "port out of range"            "entry.loopback_port = 70000"
reject_owning "no units"                     "entry.systemd_units = []"
reject_owning "bad unit type"                "entry.systemd_units[0].type = \"socket\""
reject_owning "unknown unit field"           "entry.systemd_units[0].extra = true"
reject_owning "duplicate name"               "registry.owning_repo_deployments.push(JSON.parse(JSON.stringify(entry)))"
reject_owning "name collides with component" "entry.name = \"mimir\""
reject_owning "coupled node not registered"  "entry.coupled_state[0].node_id = \"node-missing\""
reject_owning "coupled path escapes home"    "entry.coupled_state[0].home_relative_path = \"../etc/passwd\""
reject_owning "coupled path is absolute"     "entry.coupled_state[0].home_relative_path = \"/etc/passwd\""
reject_owning "coupled fields empty"         "entry.coupled_state[0].fields = []"
reject_owning "coupled unknown field"        "entry.coupled_state[0].mode = \"0600\""
reject_owning "section is not an array"      "registry.owning_repo_deployments = {}"
reject_owning "null entry"                   "registry.owning_repo_deployments = [null]"

# Inherited Object.prototype names must never satisfy a membership check.
reject_owning "repo is inherited constructor"      "entry.repo = \"constructor\""
reject_owning "repo is inherited __proto__"        "entry.repo = \"__proto__\""
reject_owning "target node is inherited constructor" "entry.target_node_id = \"constructor\""
reject_owning "target node is inherited toString"  "entry.target_node_id = \"toString\""
reject_owning "coupled node is inherited __proto__" "entry.coupled_state[0].node_id = \"__proto__\""
reject_owning "coupled node is inherited constructor" "entry.coupled_state[0].node_id = \"constructor\""

# Port collisions are tracked across owning deployments and components.
reject_owning "port collides with another owning deployment on the same node" \
  "var twin = JSON.parse(JSON.stringify(entry)); twin.name = \"mimir-search-twin\"; registry.owning_repo_deployments.push(twin)"
reject_owning "port collides with a component on the same node" \
  "var squatter = JSON.parse(JSON.stringify(registry.components.filter(function (c) { return c.name === \"mimir\"; })[0])); squatter.name = \"m5-port-squatter\"; squatter.host = \"100.76.72.59\"; squatter.target_node_id = \"node-m5\"; squatter.port = 8791; registry.components.push(squatter)"

# The same loopback port on a different node is not a collision.
mutate_owning owning-same-port-other-node \
  "var other = JSON.parse(JSON.stringify(entry)); other.name = \"mimir-search-other-node\"; other.target_node_id = \"node-orin\"; registry.owning_repo_deployments.push(other)"
assert_eq "owning deploy: same port on a different node is accepted" "0" \
  "$(run_validator "$TMP_DIR/owning-same-port-other-node.json")"

# Component names are data, not prototype keys.
mutate_owning component-named-constructor \
  "registry.components.filter(function (x) { return x.name === \"fortnox-mcp\"; })[0].name = \"constructor\""
assert_eq "component named like an Object.prototype member is not a false duplicate" "0" \
  "$(run_validator "$TMP_DIR/component-named-constructor.json")"

# Routing: the registered command runs only through guarded-deploy.sh, with
# the accepted full SHA appended as the registered revision argument.
ROUTE_REPO="$TMP_DIR/route-mimir"
mkdir -p "$ROUTE_REPO/scripts"
git -C "$ROUTE_REPO" init -q
git -C "$ROUTE_REPO" config user.email test@example.invalid
git -C "$ROUTE_REPO" config user.name test
cat > "$ROUTE_REPO/scripts/deploy-search-reader.sh" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$ROUTE_CAPTURE"
EOF
chmod +x "$ROUTE_REPO/scripts/deploy-search-reader.sh"
git -C "$ROUTE_REPO" add scripts
git -C "$ROUTE_REPO" commit -q -m fixture
ROUTE_SHA="$(git -C "$ROUTE_REPO" rev-parse HEAD)"
export ROUTE_CAPTURE="$TMP_DIR/route-capture"

route_argv() {  # one argv element per line: registered command..., then revision_argument
  owning_query "$REPO_REGISTRY" | node --input-type=commonjs -e '
    var input = "";
    process.stdin.on("data", function (chunk) { input += chunk; });
    process.stdin.on("end", function () {
      var entry = input.trim().split("\n").map(function (l) { return JSON.parse(l); })
        .filter(function (e) { return e.name === "mimir-search-reader"; })[0];
      process.stdout.write(entry.command.concat([entry.revision_argument]).join("\n") + "\n");
    });
  '
}
ROUTE_ARGV=()
while IFS= read -r line; do ROUTE_ARGV+=("$line"); done < <(route_argv)

rm -f "$ROUTE_CAPTURE"
route_rc=0
(cd "$ROUTE_REPO" && bash "$GUARDED_DEPLOY" "$ROUTE_REPO" "$ROUTE_SHA" -- "${ROUTE_ARGV[@]}" "$ROUTE_SHA") >/dev/null 2>&1 || route_rc=$?
assert_eq "guarded routing: matching worktree + SHA runs the registered command" "0" "$route_rc"
assert_eq "guarded routing: command receives the registered revision argument and SHA" \
  "--release $ROUTE_SHA" "$(cat "$ROUTE_CAPTURE" 2>/dev/null || echo missing)"

rm -f "$ROUTE_CAPTURE"
route_rc=0
WRONG_SHA="0000000000000000000000000000000000000000"
(cd "$ROUTE_REPO" && bash "$GUARDED_DEPLOY" "$ROUTE_REPO" "$WRONG_SHA" -- "${ROUTE_ARGV[@]}" "$WRONG_SHA") >/dev/null 2>&1 || route_rc=$?
assert_eq "guarded routing: SHA mismatch refuses the registered command" "1" "$route_rc"
assert_eq "guarded routing: refused command never ran" "missing" "$(cat "$ROUTE_CAPTURE" 2>/dev/null || echo missing)"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
