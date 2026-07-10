#!/usr/bin/env bash
# Proves deploy.sh fails before rsync on an unsafe registry and passes declared
# root-anchored exclusions through to rsync for an audited in-target data path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy.sh"
# shellcheck source=scripts/lib/deploy-safety.sh
source "$SCRIPT_DIR/../lib/deploy-safety.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

pass() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

assert_shell_quote_round_trip() {
  local desc=$1 value=$2 quoted actual
  quoted=$(posix_shell_quote "$value")
  actual=$(sh -c "set -- $quoted; printf '%s' \"\$1\"")
  if [[ "$actual" == "$value" ]]; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/repos/alpha"

cat > "$TMP_DIR/bin/ssh" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_CAPTURE"
if [[ "$*" == *"DEPLOY_OK"* ]]; then
  echo "DEPLOY_OK"
fi
exit 0
EOF

cat > "$TMP_DIR/bin/rsync" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RSYNC_CAPTURE"
exit 0
EOF

chmod +x "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/rsync"

SSH_CAPTURE="$TMP_DIR/ssh.calls"
RSYNC_CAPTURE="$TMP_DIR/rsync.args"
export SSH_CAPTURE RSYNC_CAPTURE

assert_shell_quote_round_trip "POSIX quote round-trips plain text" "alpha"
assert_shell_quote_round_trip "POSIX quote round-trips apostrophes and shell syntax" \
  "alpha'\$(touch $TMP_DIR/must-not-exist);beta"
if [[ -e "$TMP_DIR/must-not-exist" ]]; then
  fail "POSIX quote must not execute embedded shell syntax"
else
  pass "POSIX quote does not execute embedded shell syntax"
fi

assert_rejected_before_remote() {
  local desc=$1 fixture=$2
  rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE"
  if REGISTRY_PATH="$fixture" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
      PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" alpha >"$TMP_DIR/rejected.out" 2>&1; then
    fail "$desc: deploy must fail"
  else
    pass "$desc: deploy fails"
  fi
  if [[ -e "$SSH_CAPTURE" || -e "$RSYNC_CAPTURE" ]]; then
    fail "$desc: must invoke neither ssh nor rsync"
  else
    pass "$desc: invokes neither ssh nor rsync"
  fi
}

cat > "$TMP_DIR/unsafe.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": ["/srv/alpha/data"], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF

assert_rejected_before_remote "unexcluded persistent path" "$TMP_DIR/unsafe.json"

cat > "$TMP_DIR/trailing-slash.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha/",
      "persistent_paths": ["/srv/alpha/data"], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF
assert_rejected_before_remote "trailing-slash deploy path" "$TMP_DIR/trailing-slash.json"

cat > "$TMP_DIR/injected-name.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha|evil", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF
assert_rejected_before_remote "delimiter-bearing component name" "$TMP_DIR/injected-name.json"

cat > "$TMP_DIR/injected-repo.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha'evil", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF
assert_rejected_before_remote "shell-bearing repo name" "$TMP_DIR/injected-repo.json"

cat > "$TMP_DIR/injected-host.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1;evil", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF
assert_rejected_before_remote "shell-bearing host" "$TMP_DIR/injected-host.json"

cat > "$TMP_DIR/injected-path.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha$(evil)",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF
assert_rejected_before_remote "shell-bearing deploy path" "$TMP_DIR/injected-path.json"

cat > "$TMP_DIR/safe.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": ["/srv/alpha/data"], "rsync_excludes": ["/data/"],
      "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE"
if REGISTRY_PATH="$TMP_DIR/safe.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" alpha >"$TMP_DIR/safe.out" 2>&1; then
  pass "safe registry completes mocked deploy"
else
  fail "safe registry completes mocked deploy"
  sed -n '1,160p' "$TMP_DIR/safe.out"
fi
if grep -Fxq -- '--exclude=/data/' "$RSYNC_CAPTURE"; then
  pass "declared persistent-path exclusion reaches rsync"
else
  fail "declared persistent-path exclusion reaches rsync"
fi
if grep -Fxq -- '--exclude=.env' "$RSYNC_CAPTURE"; then
  pass "global .env policy preserves in-target service credentials"
else
  fail "global .env policy preserves in-target service credentials"
fi
if grep -Fxq -- "magnus@h1:'/srv/alpha/'" "$RSYNC_CAPTURE"; then
  pass "rsync remote path uses POSIX shell quoting"
else
  fail "rsync remote path uses POSIX shell quoting"
fi
if grep -Fq -- "mkdir -p '/srv/alpha'" "$SSH_CAPTURE"; then
  pass "ssh remote deploy path uses POSIX shell quoting"
else
  fail "ssh remote deploy path uses POSIX shell quoting"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
