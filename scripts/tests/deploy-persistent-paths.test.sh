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
      "name": "alpha", "repo": "alpha", "host": "h1", "port": 3033,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": ["/srv/alpha/data"], "rsync_excludes": ["/data/"],
      "needs_build": false,
      "systemd_units": [
        { "name": "alpha", "type": "service" },
        { "name": "heimdall-boot-check", "type": "timer" }
      ]
    }
  ]
}
EOF

# A deploy source must be an addressable, clean commit so its marker and
# rollback recipe are meaningful.
printf '%s\n' '{"name":"alpha","lockfileVersion":3,"packages":{}}' > "$TMP_DIR/repos/alpha/package-lock.json"
git init -q -b main "$TMP_DIR/repos/alpha"
git -C "$TMP_DIR/repos/alpha" add package-lock.json
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/repos/alpha" commit -q -m seed

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
if grep -Fq -- "enable --now 'heimdall-boot-check.timer'" "$SSH_CAPTURE"; then
  pass "boot-check timer is enabled and started"
else
  fail "boot-check timer must be enabled and started"
fi
if grep -Fq -- "is-active --quiet 'heimdall-boot-check.timer'" "$SSH_CAPTURE"; then
  pass "boot-check timer is health-gated before the marker"
else
  fail "boot-check timer must be health-gated"
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

# Dirty content must be rejected before either SSH or rsync can mutate a host.
echo stray > "$TMP_DIR/repos/alpha/untracked.txt"
rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE"
if REGISTRY_PATH="$TMP_DIR/safe.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" alpha >"$TMP_DIR/dirty.out" 2>&1; then
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
rm -f "$TMP_DIR/repos/alpha/untracked.txt" "$SSH_CAPTURE" "$RSYNC_CAPTURE"
if REGISTRY_PATH="$TMP_DIR/git-pull.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" alpha >"$TMP_DIR/git-pull.out" 2>&1; then
  pass "git-pull deployment completes with mocked remote"
else
  fail "git-pull deployment completes with mocked remote"
fi
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

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
