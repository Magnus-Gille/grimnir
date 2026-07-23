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
command=${*: -1}
if [[ "$command" == *"DEPLOY_MARKER_INVALIDATED"* ]]; then
  printf '%s\n' invalidate >> "$ORDER_CAPTURE"
  prior=unknown
  if [[ -f "$REMOTE_MARKER_STATE" ]]; then
    prior=$(cat "$REMOTE_MARKER_STATE")
  fi
  rm -f "$REMOTE_MARKER_STATE"
  if [[ "${SSH_FAIL_MODE:-}" == "invalidate" ]]; then
    exit 255
  fi
  printf 'DEPLOY_MARKER_INVALIDATED:%s\n' "$prior"
elif [[ "$command" == *"pull --ff-only"* ]]; then
  printf '%s\n' pull >> "$ORDER_CAPTURE"
  [[ "${SSH_FAIL_MODE:-}" == "pull" ]] && exit 1
elif [[ "$command" == *"npm ci --omit=dev"* ]]; then
  printf '%s\n' npm >> "$ORDER_CAPTURE"
  [[ "${SSH_FAIL_MODE:-}" == "npm" ]] && exit 1
elif [[ "$command" == *"rm -rf --"*"/.git"* ]]; then
  printf '%s\n' prepare >> "$ORDER_CAPTURE"
elif [[ "$command" == *"DEPLOY_OK"* ]]; then
  printf '%s\n' gates >> "$ORDER_CAPTURE"
  [[ "${SSH_FAIL_MODE:-}" == "gates" ]] && exit 1
  printf '%s\n' accepted > "$REMOTE_MARKER_STATE"
  echo "DEPLOY_OK"
fi
exit 0
EOF

cat > "$TMP_DIR/bin/rsync" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RSYNC_CAPTURE"
printf '%s\n' rsync >> "$ORDER_CAPTURE"
[[ "${RSYNC_FAIL_MODE:-}" == "fail" ]] && exit 23
exit 0
EOF

cat > "$TMP_DIR/bin/systemctl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

count=0
[[ -f "$TIMER_SHOW_COUNT" ]] && count=$(cat "$TIMER_SHOW_COUNT")
count=$((count + 1))
printf '%s\n' "$count" > "$TIMER_SHOW_COUNT"

case "${TIMER_SHOW_MODE:-}" in
  transient)
    if [[ "$count" -lt 3 ]]; then
      printf 'NextElapseUSecRealtime=\nNextElapseUSecMonotonic=\n'
    else
      printf 'NextElapseUSecRealtime=\nNextElapseUSecMonotonic=123456789\n'
    fi
    ;;
  permanent)
    printf 'NextElapseUSecRealtime=\nNextElapseUSecMonotonic=infinity\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF

cat > "$TMP_DIR/bin/sleep" << 'EOF'
#!/usr/bin/env bash
# Keep the production 30 x 1-second bound intact while making failure tests fast.
[[ "$#" -eq 1 && "$1" == "1" ]]
EOF

cat > "$TMP_DIR/bin/npm" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BUILD_CAPTURE"
exit 0
EOF

chmod +x "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/rsync" "$TMP_DIR/bin/systemctl" \
  "$TMP_DIR/bin/sleep" "$TMP_DIR/bin/npm"

SSH_CAPTURE="$TMP_DIR/ssh.calls"
RSYNC_CAPTURE="$TMP_DIR/rsync.args"
ORDER_CAPTURE="$TMP_DIR/order.calls"
REMOTE_MARKER_STATE="$TMP_DIR/remote-marker.state"
BUILD_CAPTURE="$TMP_DIR/build.calls"
PRIOR_SHA=1111111111111111111111111111111111111111
export SSH_CAPTURE RSYNC_CAPTURE ORDER_CAPTURE REMOTE_MARKER_STATE BUILD_CAPTURE

assert_shell_quote_round_trip "POSIX quote round-trips plain text" "alpha"
assert_shell_quote_round_trip "POSIX quote round-trips apostrophes and shell syntax" \
  "alpha'\$(touch $TMP_DIR/must-not-exist);beta"
if [[ -e "$TMP_DIR/must-not-exist" ]]; then
  fail "POSIX quote must not execute embedded shell syntax"
else
  pass "POSIX quote does not execute embedded shell syntax"
fi

# The cleanup command must remove both Git repository directories and worktree
# pointer files without touching normal release contents.
REMOTE_FIXTURE="$TMP_DIR/remote alpha"
mkdir -p "$REMOTE_FIXTURE/.git"
printf '%s\n' keep > "$REMOTE_FIXTURE/app.js"
sh -c "$(prepare_rsync_destination_command "$REMOTE_FIXTURE")"
if [[ ! -e "$REMOTE_FIXTURE/.git" && -f "$REMOTE_FIXTURE/app.js" ]]; then
  pass "rsync destination cleanup removes .git directory only"
else
  fail "rsync destination cleanup must remove .git directory only"
fi
printf '%s\n' "gitdir: /Users/example/repo/.git/worktrees/alpha" > "$REMOTE_FIXTURE/.git"
sh -c "$(prepare_rsync_destination_command "$REMOTE_FIXTURE")"
if [[ ! -e "$REMOTE_FIXTURE/.git" && -f "$REMOTE_FIXTURE/app.js" ]]; then
  pass "rsync destination cleanup removes worktree .git file only"
else
  fail "rsync destination cleanup must remove worktree .git file only"
fi

printf '%s\n' "$PRIOR_SHA" > "$REMOTE_FIXTURE/.deployed-commit"
marker_receipt=$(sh -c "$(prepare_deploy_marker_invalidation_command "$REMOTE_FIXTURE")")
if [[ "$marker_receipt" == "DEPLOY_MARKER_INVALIDATED:${PRIOR_SHA}" ]] &&
   [[ ! -e "$REMOTE_FIXTURE/.deployed-commit" ]]; then
  pass "marker invalidation captures prior accepted SHA and removes marker"
else
  fail "marker invalidation must capture prior accepted SHA and remove marker"
fi

assert_recurring_timer_schedule() {
  local desc=$1 expected=$2 properties=$3 rc=0 awk_program
  awk_program=$(recurring_timer_next_check_awk)
  printf '%s\n' "$properties" | awk -F= "$awk_program" >/dev/null || rc=$?
  if [[ "$rc" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc: expected exit $expected, got $rc"
  fi
}

assert_recurring_timer_schedule "recurring timer accepts a realtime next trigger" 0 \
  $'NextElapseUSecRealtime=Mon 2026-07-14 03:00:00 CEST\nNextElapseUSecMonotonic=infinity'
assert_recurring_timer_schedule "recurring timer accepts a monotonic next trigger" 0 \
  $'NextElapseUSecRealtime=infinity\nNextElapseUSecMonotonic=123456789'
assert_recurring_timer_schedule "active elapsed timer with no next trigger is rejected" 1 \
  $'NextElapseUSecRealtime=infinity\nNextElapseUSecMonotonic=infinity'

assert_recurring_timer_poll() {
  local desc=$1 mode=$2 expected_rc=$3 expected_attempts=$4
  local command rc=0 attempts=0
  TIMER_SHOW_COUNT="$TMP_DIR/timer-show.count"
  export TIMER_SHOW_COUNT
  rm -f "$TIMER_SHOW_COUNT"
  command=$(prepare_recurring_timer_next_check_command user "alpha-recurring.timer")
  TIMER_SHOW_MODE="$mode" PATH="$TMP_DIR/bin:$PATH" sh -c "$command" \
    >"$TMP_DIR/timer-poll.out" 2>"$TMP_DIR/timer-poll.err" || rc=$?
  [[ -f "$TIMER_SHOW_COUNT" ]] && attempts=$(cat "$TIMER_SHOW_COUNT")
  if [[ "$rc" == "$expected_rc" && "$attempts" == "$expected_attempts" ]]; then
    pass "$desc"
  else
    fail "$desc: expected rc/attempts ${expected_rc}/${expected_attempts}, got ${rc}/${attempts}"
  fi
}

assert_recurring_timer_poll \
  "recurring timer poll tolerates a transient empty next trigger" transient 0 3
assert_recurring_timer_poll \
  "recurring timer poll rejects permanently empty/infinity next triggers" permanent 1 30
if grep -Fq -- \
  "ERROR: recurring timer has no concrete next trigger: alpha-recurring.timer" \
  "$TMP_DIR/timer-poll.err"; then
  pass "recurring timer poll reports the failing timer"
else
  fail "recurring timer poll must report the failing timer"
fi

UNIT_FIXTURE="$TMP_DIR/unit-fixture"
mkdir -p "$UNIT_FIXTURE/systemd"
cat > "$UNIT_FIXTURE/systemd/alpha.service" << 'EOF'
# Template prose such as <user> is allowed in comments.
[Service]
ExecStart=/bin/true
EOF
cat > "$UNIT_FIXTURE/alpha.service" << 'EOF'
[Service]
User=<user>
EOF
if [[ "$(resolve_local_unit_source "$UNIT_FIXTURE" alpha.service)" == \
      "$UNIT_FIXTURE/systemd/alpha.service" ]] &&
   preflight_local_install_ready_unit_source "$UNIT_FIXTURE" alpha.service true; then
  pass "install-ready systemd unit is preferred and comment placeholders are allowed"
else
  fail "preferred systemd unit must win over the root fallback"
fi
remote_unit_guard=$(prepare_remote_install_ready_unit_check_command unit_src alpha.service)
if sh -c "unit_src=$(posix_shell_quote "$UNIT_FIXTURE/systemd/alpha.service"); $remote_unit_guard"; then
  pass "remote install-ready guard allows comment-only placeholders"
else
  fail "remote install-ready guard must allow comment-only placeholders"
fi
rm "$UNIT_FIXTURE/systemd/alpha.service"
if preflight_local_install_ready_unit_source "$UNIT_FIXTURE" alpha.service true \
    >"$TMP_DIR/root-template.out" 2>&1; then
  fail "root fallback template must be rejected"
elif grep -Fq -- "$UNIT_FIXTURE/alpha.service" "$TMP_DIR/root-template.out" &&
     grep -Fq -- "unit alpha.service" "$TMP_DIR/root-template.out" &&
     grep -Fq -- "<user>" "$TMP_DIR/root-template.out"; then
  pass "root fallback template failure names its file, unit, and placeholder"
else
  fail "root fallback template failure must identify its source"
fi
if sh -c "unit_src=$(posix_shell_quote "$UNIT_FIXTURE/alpha.service"); $remote_unit_guard" \
    >"$TMP_DIR/remote-template.out" 2>&1; then
  fail "remote install-ready guard must reject active placeholders"
elif grep -Fq -- "$UNIT_FIXTURE/alpha.service" "$TMP_DIR/remote-template.out" &&
     grep -Fq -- "unit alpha.service" "$TMP_DIR/remote-template.out" &&
     grep -Fq -- "<user>" "$TMP_DIR/remote-template.out"; then
  pass "remote template failure names its file, unit, and placeholder"
else
  fail "remote template failure must identify its source"
fi

commit_fixture_repo() {
  local repo_path=$1
  git init -q -b main "$repo_path"
  git -C "$repo_path" add .
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -C "$repo_path" commit -q -m seed
}

assert_rejected_before_remote() {
  local desc=$1 fixture=$2 expected_error=${3:-}
  local fixture_name fixture_repo fixture_source fixture_revision fixture_request
  fixture_name=$(REGISTRY_PATH="$fixture" node -e '
    var data = require(process.env.REGISTRY_PATH);
    process.stdout.write(String(data.components[0].name));
  ')
  fixture_repo=$(REGISTRY_PATH="$fixture" node -e '
    var data = require(process.env.REGISTRY_PATH);
    process.stdout.write(String(data.components[0].repo));
  ')
  fixture_source="$TMP_DIR/repos/$fixture_repo"
  fixture_revision=$(git -C "$fixture_source" rev-parse HEAD 2>/dev/null ||
    printf '%040d' 0)
  fixture_request="${fixture_name}=${fixture_source}@${fixture_revision}"
  rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$BUILD_CAPTURE"
  if REGISTRY_PATH="$fixture" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
      PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$fixture_request" \
        >"$TMP_DIR/rejected.out" 2>&1; then
    fail "$desc: deploy must fail"
  else
    pass "$desc: deploy fails"
  fi
  if [[ -e "$SSH_CAPTURE" || -e "$RSYNC_CAPTURE" ]]; then
    fail "$desc: must invoke neither ssh nor rsync"
  else
    pass "$desc: invokes neither ssh nor rsync"
  fi
  if [[ -e "$BUILD_CAPTURE" ]]; then
    fail "$desc: must not build"
  else
    pass "$desc: does not build"
  fi
  if [[ -n "$expected_error" ]]; then
    if grep -Fq -- "$expected_error" "$TMP_DIR/rejected.out"; then
      pass "$desc: reports the selected source"
    else
      fail "$desc: must report $expected_error"
    fi
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

mkdir -p "$TMP_DIR/repos/missing-unit"
printf '%s\n' '{"name":"missing-unit"}' > "$TMP_DIR/repos/missing-unit/package.json"
commit_fixture_repo "$TMP_DIR/repos/missing-unit"
cat > "$TMP_DIR/missing-unit.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "missing-unit", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": true,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF
assert_rejected_before_remote "missing primary unit" "$TMP_DIR/missing-unit.json" \
  "install-ready unit source missing: alpha.service"

mkdir -p "$TMP_DIR/repos/systemd-template/systemd"
cat > "$TMP_DIR/repos/systemd-template/systemd/alpha.service" << 'EOF'
# This is the preferred path, but active placeholders are never rendered.
[Service]
User=<user>
EOF
cat > "$TMP_DIR/repos/systemd-template/alpha.service" << 'EOF'
[Service]
ExecStart=/bin/true
EOF
commit_fixture_repo "$TMP_DIR/repos/systemd-template"
cat > "$TMP_DIR/systemd-template.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "systemd-template", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": true,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF
assert_rejected_before_remote "preferred systemd template" "$TMP_DIR/systemd-template.json" \
  "systemd/alpha.service (unit alpha.service contains unresolved placeholder <user>)"

mkdir -p "$TMP_DIR/repos/munin-template"
cat > "$TMP_DIR/repos/munin-template/munin-memory.service" << 'EOF'
# NOTE: Replace <user> and <install-dir> before installing this template.
[Service]
User=<user>
WorkingDirectory=/home/<user>/<install-dir>
EnvironmentFile=/home/<user>/<install-dir>/.env
EOF
commit_fixture_repo "$TMP_DIR/repos/munin-template"
cat > "$TMP_DIR/munin-template.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "munin-template", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": true,
      "systemd_units": [{ "name": "munin-memory", "type": "service" }]
    }
  ]
}
EOF
assert_rejected_before_remote "Munin-shaped root template" "$TMP_DIR/munin-template.json" \
  "munin-memory.service (unit munin-memory.service contains unresolved placeholder <user>)"

mkdir -p "$TMP_DIR/repos/companion-template/systemd"
cat > "$TMP_DIR/repos/companion-template/systemd/alpha.timer" << 'EOF'
[Timer]
OnCalendar=daily
EOF
cat > "$TMP_DIR/repos/companion-template/systemd/alpha.service" << 'EOF'
[Service]
WorkingDirectory=/home/<user>/alpha
EOF
commit_fixture_repo "$TMP_DIR/repos/companion-template"
cat > "$TMP_DIR/companion-template.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "companion-template", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": true,
      "systemd_units": [{ "name": "alpha", "type": "timer" }]
    }
  ]
}
EOF
assert_rejected_before_remote "present timer companion template" "$TMP_DIR/companion-template.json" \
  "systemd/alpha.service (unit alpha.service contains unresolved placeholder <user>)"

cat > "$TMP_DIR/safe.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": 3033,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": ["/srv/alpha/data"], "rsync_excludes": ["/data/"],
      "needs_build": false,
      "systemd_units": [
        { "name": "alpha", "type": "service" },
        { "name": "heimdall-boot-check", "type": "timer" },
        { "name": "alpha-once", "type": "timer", "timer_semantics": "one-shot" },
        { "name": "alpha-recurring", "type": "timer" },
        { "name": "alpha-user-recurring", "type": "timer", "scope": "user" }
      ]
    }
  ]
}
EOF

# A deploy source must be an addressable, clean commit so its marker and
# rollback recipe are meaningful.
printf '%s\n' '{"name":"alpha","lockfileVersion":3,"packages":{}}' > "$TMP_DIR/repos/alpha/package-lock.json"
mkdir -p "$TMP_DIR/repos/alpha/systemd"
cat > "$TMP_DIR/repos/alpha/systemd/alpha.service" << 'EOF'
# Install-ready unit; illustrative <user> prose in comments is allowed.
[Service]
ExecStart=/bin/true
EOF
cat > "$TMP_DIR/repos/alpha/alpha.service" << 'EOF'
[Service]
User=<ignored-root-template>
EOF
for timer in heimdall-boot-check alpha-once alpha-recurring alpha-user-recurring; do
  cat > "$TMP_DIR/repos/alpha/${timer}.timer" << EOF
[Timer]
OnCalendar=daily
EOF
done
cat > "$TMP_DIR/repos/alpha/alpha-recurring.service" << 'EOF'
[Service]
ExecStart=/bin/true
EOF
commit_fixture_repo "$TMP_DIR/repos/alpha"
ALPHA_SHA=$(git -C "$TMP_DIR/repos/alpha" rev-parse HEAD)
ALPHA_REQUEST="alpha=$TMP_DIR/repos/alpha@$ALPHA_SHA"

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
if REGISTRY_PATH="$TMP_DIR/safe.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/safe.out" 2>&1; then
  pass "safe registry completes mocked deploy"
else
  fail "safe registry completes mocked deploy"
  sed -n '1,160p' "$TMP_DIR/safe.out"
fi
invalidate_line=$(grep -n '^invalidate$' "$ORDER_CAPTURE" | head -1 | cut -d: -f1)
prepare_line=$(grep -n '^prepare$' "$ORDER_CAPTURE" | head -1 | cut -d: -f1)
rsync_line=$(grep -n '^rsync$' "$ORDER_CAPTURE" | head -1 | cut -d: -f1)
if [[ -n "$invalidate_line" && -n "$prepare_line" && -n "$rsync_line" ]] &&
   [[ "$invalidate_line" -lt "$prepare_line" && "$invalidate_line" -lt "$rsync_line" ]]; then
  pass "accepted marker is invalidated before rsync destination mutation"
else
  fail "accepted marker must be invalidated before rsync destination mutation"
fi
if grep -Fq "Previous accepted deployment: ${PRIOR_SHA} (marker invalidated)" "$TMP_DIR/safe.out"; then
  pass "prior accepted SHA is retained in the deploy rollback log"
else
  fail "deploy must log the prior accepted SHA for rollback"
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
if grep -Fq -- "mkdir -p '/srv/alpha' && rm -rf -- '/srv/alpha'/.git" "$SSH_CAPTURE"; then
  pass "rsync destination is quoted and stale Git metadata is removed"
else
  fail "rsync destination must be quoted and remove stale Git metadata"
fi
if grep -Fq -- "npm ci --omit=dev" "$SSH_CAPTURE"; then
  pass "locked runtime dependencies use npm ci"
else
  fail "locked runtime dependencies must use npm ci"
fi
if grep -Fq -- "heimdall-boot-check.timer" "$SSH_CAPTURE" &&
   grep -Fq -- "heimdall-boot-check.service" "$SSH_CAPTURE"; then
  pass "boot-check timer and companion service are refreshed"
else
  fail "boot-check timer and companion service must both be refreshed"
fi
# shellcheck disable=SC2016 # literal remote-shell fragments expected in capture
if grep -Fq -- "for f in 'systemd/alpha.service' 'alpha.service'" "$SSH_CAPTURE" &&
   grep -Fq -- 'unit_src_placeholder=$(awk' "$SSH_CAPTURE" &&
   grep -Fq -- 'companion_src_placeholder=$(awk' "$SSH_CAPTURE"; then
  pass "remote unit selection rechecks primary and present companion sources"
else
  fail "remote install must retain the install-ready source guard"
fi
if grep -Fq -- "sudo systemctl enable 'heimdall-boot-check.timer'" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl restart 'heimdall-boot-check.timer'" "$SSH_CAPTURE"; then
  pass "existing recurring system timer is enabled and restarted"
else
  fail "existing recurring system timer must be enabled and restarted"
fi
if grep -Fq -- "sudo systemctl enable 'alpha-once.timer'" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl restart 'alpha-once.timer'" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl is-active --quiet 'alpha-once.timer'" "$SSH_CAPTURE"; then
  pass "synthetic one-shot timer is enabled, restarted, and active-gated"
else
  fail "synthetic one-shot timer must be enabled, restarted, and active-gated"
fi
if grep -Fq -- "systemctl --user enable 'alpha-user-recurring.timer'" "$SSH_CAPTURE" &&
   grep -Fq -- "systemctl --user restart 'alpha-user-recurring.timer'" "$SSH_CAPTURE"; then
  pass "existing user timer is enabled and restarted"
else
  fail "existing user timer must be enabled and restarted"
fi
if grep -Fq -- "is-active --quiet 'heimdall-boot-check.timer'" "$SSH_CAPTURE"; then
  pass "boot-check timer is health-gated before the marker"
else
  fail "boot-check timer must be health-gated"
fi
if grep -Fq -- "systemctl --user show 'alpha-user-recurring.timer' --property=NextElapseUSecRealtime --property=NextElapseUSecMonotonic" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl show 'alpha-recurring.timer' --property=NextElapseUSecRealtime --property=NextElapseUSecMonotonic" "$SSH_CAPTURE" &&
   grep -Fq -- "sudo systemctl show 'heimdall-boot-check.timer' --property=NextElapseUSecRealtime --property=NextElapseUSecMonotonic" "$SSH_CAPTURE"; then
  pass "recurring timers, including Heimdall boot-check, require a concrete next trigger"
else
  fail "recurring timers in both scopes, including Heimdall boot-check, must require a concrete next trigger"
fi
# shellcheck disable=SC2016 # literal remote-shell fragments expected in capture
if grep -Fq -- 'timer_attempt=1; while [ "$timer_attempt" -le 30 ]' "$SSH_CAPTURE" &&
   grep -Fq -- 'sleep 1; timer_attempt=$((timer_attempt + 1))' "$SSH_CAPTURE"; then
  pass "recurring timer acceptance polling is bounded to 30 one-second attempts"
else
  fail "recurring timer acceptance polling must be bounded to 30 one-second attempts"
fi
if grep -Fq -- "systemctl show 'alpha-once.timer'" "$SSH_CAPTURE"; then
  fail "synthetic one-shot timer must not require a recurring next trigger"
else
  pass "synthetic one-shot timer may legitimately become active and elapsed"
fi
# shellcheck disable=SC2016 # literal remote-shell fragment expected in capture
if grep -Fq -- 'http://${target}:3033${path}' "$SSH_CAPTURE"; then
  pass "declared HTTP endpoint is health-gated before the marker"
else
  fail "declared HTTP endpoint must be health-gated"
fi
final_call="$(grep -F 'DEPLOY_OK' "$SSH_CAPTURE" | tail -1)"
# shellcheck disable=SC2016 # literal remote-shell fragment expected in capture
case "$final_call" in
  *'http://${target}:3033${path}'*"> .deployed-commit"*)
    pass "health gate precedes deployment marker repair"
    ;;
  *)
    fail "deployment marker must be written only after health succeeds"
    ;;
esac
case "$final_call" in
  *"systemctl --user daemon-reload"*"systemctl --user enable 'alpha-user-recurring.timer'"*"systemctl --user restart 'alpha-user-recurring.timer'"*"systemctl --user is-active --quiet 'alpha-user-recurring.timer'"*"systemctl --user show 'alpha-user-recurring.timer'"*"ERROR: recurring timer has no concrete next trigger: %s"*"> .deployed-commit"*)
    pass "user timer reload, enable, restart, acceptance, and marker ordering is strict"
    ;;
  *)
    fail "user timer controller ordering must precede marker acceptance"
    ;;
esac
case "$final_call" in
  *"sudo systemctl daemon-reload"*"sudo systemctl enable 'heimdall-boot-check.timer'"*"sudo systemctl restart 'heimdall-boot-check.timer'"*"sudo systemctl is-active --quiet 'heimdall-boot-check.timer'"*"sudo systemctl show 'heimdall-boot-check.timer'"*"ERROR: recurring timer has no concrete next trigger: %s"*"> .deployed-commit"*)
    pass "system timer reload, enable, restart, acceptance, and marker ordering is strict"
    ;;
  *)
    fail "system timer controller ordering must precede marker acceptance"
    ;;
esac

assert_markerless_failure() {
  local desc=$1 ssh_fail=${2:-} rsync_fail=${3:-}
  rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
  printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
  rc=0
  SSH_FAIL_MODE="$ssh_fail" RSYNC_FAIL_MODE="$rsync_fail" \
    REGISTRY_PATH="$TMP_DIR/safe.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/failure.out" 2>&1 || rc=$?
  if [[ "$rc" == 1 && ! -e "$REMOTE_MARKER_STATE" ]] &&
     grep -Fq "markerless/unknown" "$TMP_DIR/failure.out"; then
    pass "$desc leaves the deployment markerless"
  else
    fail "$desc must leave the deployment markerless"
  fi
}

assert_markerless_failure "failed rsync" "" fail
assert_markerless_failure "failed npm install" npm ""
assert_markerless_failure "failed unit/health gate" gates ""

# If invalidation transport is uncertain, deployment stops before rsync.
rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
rc=0
SSH_FAIL_MODE=invalidate REGISTRY_PATH="$TMP_DIR/safe.json" \
  LOCAL_REPOS_ROOT="$TMP_DIR/repos" PATH="$TMP_DIR/bin:$PATH" \
  bash "$DEPLOY" "$ALPHA_REQUEST" >"$TMP_DIR/invalidation-fail.out" 2>&1 || rc=$?
if [[ "$rc" == 1 && ! -e "$RSYNC_CAPTURE" ]] &&
   [[ "$(tr '\n' ' ' < "$ORDER_CAPTURE")" == "invalidate " ]]; then
  pass "uncertain marker invalidation stops before code mutation"
else
  fail "uncertain marker invalidation must stop before code mutation"
fi

# Dirty content must be rejected before either SSH or rsync can mutate a host.
echo stray > "$TMP_DIR/repos/alpha/untracked.txt"
rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
if REGISTRY_PATH="$TMP_DIR/safe.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/dirty.out" 2>&1; then
  fail "dirty source must fail"
else
  pass "dirty source fails"
fi
if [[ -e "$SSH_CAPTURE" || -e "$RSYNC_CAPTURE" ]]; then
  fail "dirty source must be rejected before remote mutation"
else
  pass "dirty source invokes neither ssh nor rsync"
fi

# Git-pull mode operates on a real checkout and must never remove its .git.
cat > "$TMP_DIR/git-pull.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false, "deploy_mode": "git-pull",
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF
rm -f "$TMP_DIR/repos/alpha/untracked.txt" "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
git init -q --bare "$TMP_DIR/alpha-origin.git"
git -C "$TMP_DIR/repos/alpha" remote add origin "$TMP_DIR/alpha-origin.git"
git -C "$TMP_DIR/repos/alpha" push -q -u origin main
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
if REGISTRY_PATH="$TMP_DIR/git-pull.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
      >"$TMP_DIR/git-pull.out" 2>&1; then
  pass "git-pull deployment completes with mocked remote"
else
  fail "git-pull deployment completes with mocked remote"
fi
git_pull_final_call="$(grep -F 'DEPLOY_OK' "$SSH_CAPTURE" | tail -1)"
case "$git_pull_final_call" in
  *"unit_src_placeholder="*"unit source is not install-ready"*"sudo install -D -m644"*)
    pass "git-pull source is guarded immediately before unit install"
    ;;
  *)
    fail "git-pull source must be guarded immediately before unit install"
    ;;
esac
if grep -Fq -- "rm -rf -- '/srv/alpha'/.git" "$SSH_CAPTURE"; then
  fail "git-pull deployment must preserve remote Git metadata"
else
  pass "git-pull deployment preserves remote Git metadata"
fi
if [[ -e "$RSYNC_CAPTURE" ]]; then
  fail "git-pull deployment must not invoke rsync"
else
  pass "git-pull deployment does not invoke rsync"
fi
invalidate_line=$(grep -n '^invalidate$' "$ORDER_CAPTURE" | head -1 | cut -d: -f1)
pull_line=$(grep -n '^pull$' "$ORDER_CAPTURE" | head -1 | cut -d: -f1)
if [[ -n "$invalidate_line" && -n "$pull_line" && "$invalidate_line" -lt "$pull_line" ]]; then
  pass "accepted marker is invalidated before git pull mutation"
else
  fail "accepted marker must be invalidated before git pull mutation"
fi

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
rc=0
SSH_FAIL_MODE=pull REGISTRY_PATH="$TMP_DIR/git-pull.json" \
  LOCAL_REPOS_ROOT="$TMP_DIR/repos" PATH="$TMP_DIR/bin:$PATH" \
  bash "$DEPLOY" "$ALPHA_REQUEST" >"$TMP_DIR/pull-fail.out" 2>&1 || rc=$?
if [[ "$rc" == 1 && ! -e "$REMOTE_MARKER_STATE" ]] &&
   grep -Fq "markerless/unknown" "$TMP_DIR/pull-fail.out"; then
  pass "failed git pull leaves the deployment markerless"
else
  fail "failed git pull must leave the deployment markerless"
fi

# The source remote is read before accepted-marker invalidation. If main has
# advanced past the explicitly expected revision, fail with the marker intact
# and make no SSH deployment call.
git clone -q -b main "$TMP_DIR/alpha-origin.git" "$TMP_DIR/origin-updater"
printf '%s\n' advanced > "$TMP_DIR/origin-updater/advanced.txt"
git -C "$TMP_DIR/origin-updater" add advanced.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/origin-updater" commit -q -m advanced
git -C "$TMP_DIR/origin-updater" push -q origin main
ADVANCED_SHA=$(git -C "$TMP_DIR/origin-updater" rev-parse HEAD)
rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$ORDER_CAPTURE"
printf '%s\n' "$PRIOR_SHA" > "$REMOTE_MARKER_STATE"
rc=0
REGISTRY_PATH="$TMP_DIR/git-pull.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
  PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "$ALPHA_REQUEST" \
  >"$TMP_DIR/upstream-mismatch.out" 2>&1 || rc=$?
if [[ "$rc" == 1 && "$(cat "$REMOTE_MARKER_STATE")" == "$PRIOR_SHA" ]] &&
   [[ ! -e "$SSH_CAPTURE" && ! -e "$RSYNC_CAPTURE" ]]; then
  pass "git-pull upstream mismatch fails before marker invalidation or pull"
else
  fail "git-pull upstream mismatch must fail before marker invalidation or pull"
fi
if grep -Fq "Expected remote source: origin/refs/heads/main @ $ALPHA_SHA" \
    "$TMP_DIR/upstream-mismatch.out" &&
   grep -Fq "Actual remote source: origin/refs/heads/main @ $ADVANCED_SHA" \
    "$TMP_DIR/upstream-mismatch.out"; then
  pass "git-pull upstream mismatch reports expected and actual revisions"
else
  fail "git-pull upstream mismatch must report expected and actual revisions"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
