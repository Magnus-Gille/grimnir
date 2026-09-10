#!/usr/bin/env bash
# Regression for grimnir#194: guarded deploy must honor an explicit
# boot-enablement policy for system services on clean installs.
#
# A fresh reinstall previously left e.g. heimdall.service active but
# disabled, so it would not survive reboot: deploy restarted declared
# services but only enabled declared timers.
#
# Contract under test:
# - Optional boolean `boot_enable` on systemd_units service entries only.
#   Default (absent/false) is never-enable; unknown unit fields fail closed.
# - A boot-enabled service is enabled (user/system scope) before deploy can
#   succeed, and must read back both is-enabled and is-active.
# - Services without an explicit declaration are never enabled.
# - Enablement failure or a disabled readback fails closed before the
#   .deployed-commit marker is repaired (markerless/unknown).
# - Timer enablement and unit target guards are unchanged.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy.sh"
VALIDATOR="$SCRIPT_DIR/../lib/validate-registry.js"
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

run_validator() {
  local fixture=$1 rc=0
  REGISTRY_PATH="$fixture" node --input-type=commonjs "$VALIDATOR" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

commit_fixture_repo() {
  local repo_path=$1
  git init -q -b main "$repo_path"
  git -C "$repo_path" add .
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -C "$repo_path" commit -q -m seed
}

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/repos"

cat > "$TMP_DIR/bin/ssh" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_CAPTURE"
command=${*: -1}
if [[ "$command" == *"DEPLOY_MARKER_INVALIDATED"* ]]; then
  printf '%s\n' invalidate >> "$ORDER_CAPTURE"
  prior=unknown
  if [[ -f "$REMOTE_MARKER_STATE" ]]; then
    prior=$(cat "$REMOTE_MARKER_STATE")
  fi
  rm -f "$REMOTE_MARKER_STATE"
  printf 'DEPLOY_MARKER_INVALIDATED:%s\n' "$prior"
elif [[ "$command" == *"DEPLOY_OK"* ]]; then
  printf '%s\n' gates >> "$ORDER_CAPTURE"
  if [[ "${SSH_FAIL_MODE:-}" == "enable-fail" && "$command" == *"enable 'alpha.service'"* ]]; then
    exit 1
  fi
  if [[ "${SSH_FAIL_MODE:-}" == "is-enabled-fail" && "$command" == *"is-enabled"* ]]; then
    exit 1
  fi
  printf '%s\n' accepted > "$REMOTE_MARKER_STATE"
  echo "DEPLOY_OK"
fi
exit 0
EOF

cat > "$TMP_DIR/bin/rsync" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RSYNC_CAPTURE"
printf '%s\n' rsync >> "$ORDER_CAPTURE"
exit 0
EOF

cat > "$TMP_DIR/bin/npm" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/rsync" "$TMP_DIR/bin/npm"

SSH_CAPTURE="$TMP_DIR/ssh.calls"
RSYNC_CAPTURE="$TMP_DIR/rsync.args"
ORDER_CAPTURE="$TMP_DIR/order.calls"
REMOTE_MARKER_STATE="$TMP_DIR/remote-marker.state"
PRIOR_SHA=1111111111111111111111111111111111111111
export SSH_CAPTURE RSYNC_CAPTURE ORDER_CAPTURE REMOTE_MARKER_STATE

echo "deploy boot-enable policy tests"
echo "================================"

# ── Validator: boot_enable is service-only, boolean, closed ──────────────

cat > "$TMP_DIR/valid-boot.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "boot_enable": true }]
    }
  ]
}
EOF
if [[ "$(run_validator "$TMP_DIR/valid-boot.json")" == "0" ]]; then
  pass "validator accepts boot_enable:true on a service"
else
  fail "validator must accept boot_enable:true on a service"
fi

cat > "$TMP_DIR/valid-boot-false.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "boot_enable": false }]
    }
  ]
}
EOF
if [[ "$(run_validator "$TMP_DIR/valid-boot-false.json")" == "0" ]]; then
  pass "validator accepts explicit boot_enable:false on a service"
else
  fail "validator must accept explicit boot_enable:false on a service"
fi

cat > "$TMP_DIR/timer-boot.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "timer", "boot_enable": true }]
    }
  ]
}
EOF
if [[ "$(run_validator "$TMP_DIR/timer-boot.json")" == "1" ]]; then
  pass "validator rejects boot_enable on a timer"
else
  fail "validator must reject boot_enable on a timer"
fi

cat > "$TMP_DIR/nonbool-boot.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "boot_enable": "yes" }]
    }
  ]
}
EOF
if [[ "$(run_validator "$TMP_DIR/nonbool-boot.json")" == "1" ]]; then
  pass "validator rejects non-boolean boot_enable"
else
  fail "validator must reject non-boolean boot_enable"
fi

cat > "$TMP_DIR/unknown-field.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "wanted_by": "multi-user.target" }]
    }
  ]
}
EOF
if [[ "$(run_validator "$TMP_DIR/unknown-field.json")" == "1" ]]; then
  pass "validator rejects unknown unit fields fail-closed"
else
  fail "validator must reject unknown unit fields fail-closed"
fi

# ── Real registry policy: explicit, never inferred ───────────────────────

REPO_REGISTRY="$SCRIPT_DIR/../../services.json"
if REGISTRY_PATH="$REPO_REGISTRY" node --input-type=commonjs -e '
  var data = require(process.env.REGISTRY_PATH);
  function units(name) {
    return data.components.filter(function (c) { return c.name === name; })[0].systemd_units;
  }
  function boot(name) {
    return units(name).filter(function (u) { return u.type === "service" && u.boot_enable === true; }).map(function (u) { return u.name; });
  }
  // Incident case plus primary long-running daemons are explicit.
  ["heimdall", "munin-memory", "ratatoskr", "mimir", "hugin"].forEach(function (name) {
    if (boot(name).length !== 1) throw new Error(name + " must declare exactly one boot-enabled service");
  });
  // Stopped services and timers are never boot-enabled.
  if (boot("verdandi").length !== 0) throw new Error("verdandi must never be boot-enabled");
  data.components.forEach(function (c) {
    c.systemd_units.forEach(function (u) {
      if (u.type === "timer" && u.boot_enable !== undefined) throw new Error("timer must not declare boot_enable: " + u.name);
    });
  });
'; then
  pass "real services.json declares explicit boot policy for primaries, never timers/stopped"
else
  fail "real services.json must declare explicit boot policy for primaries, never timers/stopped"
fi

# ── Deploy fixtures ─────────────────────────────────────────────────────

mkdir -p "$TMP_DIR/repos/alpha/systemd"
cat > "$TMP_DIR/repos/alpha/systemd/alpha.service" << 'EOF'
[Service]
ExecStart=/bin/true
EOF
printf '%s\n' '{"name":"alpha"}' > "$TMP_DIR/repos/alpha/package.json"
commit_fixture_repo "$TMP_DIR/repos/alpha"
ALPHA_SHA=$(git -C "$TMP_DIR/repos/alpha" rev-parse HEAD)
ALPHA_REQUEST="alpha=$TMP_DIR/repos/alpha@$ALPHA_SHA"

cat > "$TMP_DIR/boot.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "boot_enable": true }]
    }
  ]
}
EOF

cat > "$TMP_DIR/plain.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF

cat > "$TMP_DIR/user-boot.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "scope": "user", "boot_enable": true }]
    }
  ]
}
EOF

cat > "$TMP_DIR/timer.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [
        { "name": "alpha", "type": "service" },
        { "name": "alpha-once", "type": "timer", "timer_semantics": "one-shot" }
      ]
    }
  ]
}
EOF
cat > "$TMP_DIR/repos/alpha/alpha-once.timer" << 'EOF'
[Timer]
OnCalendar=daily
EOF
git -C "$TMP_DIR/repos/alpha" add alpha-once.timer
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/repos/alpha" commit -q -m timer
ALPHA_SHA=$(git -C "$TMP_DIR/repos/alpha" rev-parse HEAD)
ALPHA_REQUEST="alpha=$TMP_DIR/repos/alpha@$ALPHA_SHA"

# ── Fresh install: disabled primary ends enabled+active ──────────────────

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
if REGISTRY_PATH="$TMP_DIR/boot.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/boot.out" 2>&1; then
  pass "boot-enabled service completes mocked fresh-install deploy"
else
  fail "boot-enabled service must complete mocked fresh-install deploy"
  sed -n '1,80p' "$TMP_DIR/boot.out"
fi
if grep -Fq -- "sudo systemctl enable 'alpha.service'" "$SSH_CAPTURE"; then
  pass "boot-enabled system service is enabled"
else
  fail "boot-enabled system service must be enabled"
fi
if grep -Fq -- "sudo systemctl is-enabled --quiet 'alpha.service'" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl is-active --quiet 'alpha.service'" "$SSH_CAPTURE"; then
  pass "boot-enabled system service reads back enabled and active"
else
  fail "boot-enabled system service must read back enabled and active"
fi
if [[ "$(cat "$REMOTE_MARKER_STATE")" == "accepted" ]]; then
  pass "marker is repaired after enablement and readback succeed"
else
  fail "marker must be repaired after enablement and readback succeed"
fi
final_call="$(grep -F 'DEPLOY_OK' "$SSH_CAPTURE" | tail -1)"
case "$final_call" in
  *"sudo systemctl enable 'alpha.service'"*"sudo systemctl restart 'alpha.service'"*"sudo systemctl is-active --quiet 'alpha.service'"*"sudo systemctl is-enabled --quiet 'alpha.service'"*"> .deployed-commit"*)
    pass "enable, restart, active/enabled readback, and marker ordering is strict"
    ;;
  *)
    fail "ordering must be enable -> restart -> active/enabled readback -> marker"
    ;;
esac

# ── Idempotent: already-enabled service stays success ────────────────────

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
if REGISTRY_PATH="$TMP_DIR/boot.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/boot-again.out" 2>&1 &&
   [[ "$(cat "$REMOTE_MARKER_STATE")" == "accepted" ]]; then
  pass "already-enabled service stays idempotent success"
else
  fail "already-enabled service must stay idempotent success"
fi

# ── No declaration: never enabled ────────────────────────────────────────

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
if REGISTRY_PATH="$TMP_DIR/plain.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/plain.out" 2>&1; then
  pass "service without boot declaration still deploys"
else
  fail "service without boot declaration must still deploy"
fi
if grep -Fq -- "enable 'alpha.service'" "$SSH_CAPTURE" ||
   grep -Fq -- "is-enabled" "$SSH_CAPTURE"; then
  fail "service without boot declaration must never be enabled or read back"
else
  pass "service without boot declaration is never enabled"
fi
if grep -Fq -- "sudo systemctl restart 'alpha.service'" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl is-active --quiet 'alpha.service'" "$SSH_CAPTURE"; then
  pass "undeclared service still restarts and gates active"
else
  fail "undeclared service must still restart and gate active"
fi

# ── Enablement failure prevents the marker ───────────────────────────────

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
rc=0
SSH_FAIL_MODE=enable-fail REGISTRY_PATH="$TMP_DIR/boot.json" \
  LOCAL_REPOS_ROOT="$TMP_DIR/repos" PATH="$TMP_DIR/bin:$PATH" \
  bash "$DEPLOY" "$ALPHA_REQUEST" >"$TMP_DIR/enable-fail.out" 2>&1 || rc=$?
if [[ "$rc" == 1 && ! -e "$REMOTE_MARKER_STATE" ]] &&
   grep -Fq "markerless/unknown" "$TMP_DIR/enable-fail.out"; then
  pass "enablement failure leaves the deployment markerless"
else
  fail "enablement failure must leave the deployment markerless"
fi

# ── Disabled readback prevents the marker ────────────────────────────────

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
rc=0
SSH_FAIL_MODE=is-enabled-fail REGISTRY_PATH="$TMP_DIR/boot.json" \
  LOCAL_REPOS_ROOT="$TMP_DIR/repos" PATH="$TMP_DIR/bin:$PATH" \
  bash "$DEPLOY" "$ALPHA_REQUEST" >"$TMP_DIR/readback-fail.out" 2>&1 || rc=$?
if [[ "$rc" == 1 && ! -e "$REMOTE_MARKER_STATE" ]] &&
   grep -Fq "markerless/unknown" "$TMP_DIR/readback-fail.out"; then
  pass "disabled readback leaves the deployment markerless"
else
  fail "disabled readback must leave the deployment markerless"
fi

# ── User scope honors the same explicit policy ───────────────────────────

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
if REGISTRY_PATH="$TMP_DIR/user-boot.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/user-boot.out" 2>&1; then
  pass "boot-enabled user service completes mocked deploy"
else
  fail "boot-enabled user service must complete mocked deploy"
fi
if grep -Fq -- "systemctl --user enable 'alpha.service'" "$SSH_CAPTURE" &&
   grep -Fq -- "systemctl --user is-enabled --quiet 'alpha.service'" "$SSH_CAPTURE"; then
  pass "boot-enabled user service uses user-manager enable and readback"
else
  fail "boot-enabled user service must use user-manager enable and readback"
fi
if grep -Fq -- "sudo systemctl enable 'alpha.service'" "$SSH_CAPTURE"; then
  fail "user service must not be enabled via the system manager"
else
  pass "user service is never enabled via the system manager"
fi

# ── Timer enablement is unchanged ────────────────────────────────────────

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
if REGISTRY_PATH="$TMP_DIR/timer.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/timer.out" 2>&1; then
  pass "timer deployment still completes"
else
  fail "timer deployment must still complete"
fi
if grep -Fq -- "sudo systemctl enable 'alpha-once.timer'" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl restart 'alpha-once.timer'" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl is-active --quiet 'alpha-once.timer'" "$SSH_CAPTURE"; then
  pass "timer enablement, restart, and active gate are unchanged"
else
  fail "timer enablement, restart, and active gate must be unchanged"
fi
if grep -Fq -- "enable 'alpha.service'" "$SSH_CAPTURE"; then
  fail "undeclared companion service must not gain enablement via its timer"
else
  pass "undeclared service stays unenabled alongside its timer"
fi

# ── Unit target guard still applies with boot_enable set ─────────────────

mkdir -p "$TMP_DIR/repos/guard-mismatch/systemd"
cat > "$TMP_DIR/repos/guard-mismatch/systemd/alpha.service" << 'EOF'
[Service]
WorkingDirectory=/elsewhere/alpha
ExecStart=/bin/true
EOF
printf '%s\n' '{"name":"alpha"}' > "$TMP_DIR/repos/guard-mismatch/package.json"
commit_fixture_repo "$TMP_DIR/repos/guard-mismatch"
GUARD_SHA=$(git -C "$TMP_DIR/repos/guard-mismatch" rev-parse HEAD)
cat > "$TMP_DIR/guard-mismatch.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "guard-mismatch", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service", "boot_enable": true }]
    }
  ]
}
EOF
rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE"
rc=0
REGISTRY_PATH="$TMP_DIR/guard-mismatch.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
  PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "alpha=$TMP_DIR/repos/guard-mismatch@$GUARD_SHA" \
    >"$TMP_DIR/guard-mismatch.out" 2>&1 || rc=$?
if [[ "$rc" != 0 && ! -e "$SSH_CAPTURE" && ! -e "$RSYNC_CAPTURE" ]]; then
  pass "unit target contradiction with boot_enable still fails before remote"
else
  fail "unit target contradiction with boot_enable must still fail before remote"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
