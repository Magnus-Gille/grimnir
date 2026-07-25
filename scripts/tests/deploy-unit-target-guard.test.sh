#!/usr/bin/env bash
# Regression coverage for issue #146: a deploy that rsyncs code to the
# registry's deploy_path but installs a systemd unit whose WorkingDirectory /
# EnvironmentFile point somewhere else must abort BEFORE any service is
# stopped -- never restart into a broken unit. This is the exact shape that
# took munin-memory down for ~10 minutes on 2026-07-25: services.json said
# deploy_path=/home/magnus/munin-memory, the owning repo's byte-for-byte unit
# said WorkingDirectory=/srv/grimnir/munin-memory, and nothing reconciled the
# two before systemd was told to restart into a path that did not exist.
#
# Also covers the companion remote preflight (declared User= exists,
# EnvironmentFile is present) and the pre-overwrite unit backup, both of
# which must sit strictly before the install/reload/restart chain.

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
  echo "DEPLOY_MARKER_INVALIDATED:unknown"
elif [[ "$command" == *"DEPLOY_OK"* ]]; then
  echo "DEPLOY_OK"
fi
exit 0
EOF

cat > "$TMP_DIR/bin/rsync" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RSYNC_CAPTURE"
exit 0
EOF

cat > "$TMP_DIR/bin/npm" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/rsync" "$TMP_DIR/bin/npm"

SSH_CAPTURE="$TMP_DIR/ssh.calls"
RSYNC_CAPTURE="$TMP_DIR/rsync.args"
export SSH_CAPTURE RSYNC_CAPTURE

# ---------------------------------------------------------------------------
# Part 1: the exact munin-memory case. Registry deploy_path is a "pre-
# relocation" host path; the owning repo's unit is "post-relocation". The
# deploy must refuse before any remote call at all.
# ---------------------------------------------------------------------------

mkdir -p "$TMP_DIR/repos/munin-memory/systemd"
cat > "$TMP_DIR/repos/munin-memory/systemd/munin-memory.service" << 'EOF'
[Unit]
Description=Munin Memory MCP Server

[Service]
Type=simple
User=grimnir
WorkingDirectory=/srv/grimnir/munin-memory
ExecStart=/usr/bin/node dist/index.js
EnvironmentFile=/srv/grimnir/munin-memory/.env

[Install]
WantedBy=multi-user.target
EOF
printf '%s\n' '{"name":"munin-memory"}' > "$TMP_DIR/repos/munin-memory/package.json"
commit_fixture_repo "$TMP_DIR/repos/munin-memory"
MUNIN_SHA=$(git -C "$TMP_DIR/repos/munin-memory" rev-parse HEAD)

cat > "$TMP_DIR/munin-registry.json" << 'EOF'
{
  "components": [
    {
      "name": "munin-memory", "repo": "munin-memory", "host": "h1", "port": 3030,
      "deploy": true, "scan": false, "deploy_path": "/home/magnus/munin-memory",
      "persistent_paths": [], "needs_build": true,
      "systemd_units": [{ "name": "munin-memory", "type": "service" }]
    }
  ]
}
EOF

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE"
rc=0
REGISTRY_PATH="$TMP_DIR/munin-registry.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
  PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "munin-memory=$TMP_DIR/repos/munin-memory@$MUNIN_SHA" \
    >"$TMP_DIR/munin-reject.out" 2>&1 || rc=$?

if [[ "$rc" != 0 ]]; then
  pass "munin-memory-shaped WorkingDirectory/deploy_path contradiction: deploy fails"
else
  fail "munin-memory-shaped WorkingDirectory/deploy_path contradiction: deploy must fail"
fi
if [[ ! -e "$SSH_CAPTURE" && ! -e "$RSYNC_CAPTURE" ]]; then
  pass "munin-memory-shaped contradiction: invokes neither ssh nor rsync (no service was ever touched)"
else
  fail "munin-memory-shaped contradiction: must invoke neither ssh nor rsync -- a live service must never be stopped on the way to discovering this"
  sed -n '1,80p' "$TMP_DIR/munin-reject.out"
fi
if grep -Fq -- "WorkingDirectory=/srv/grimnir/munin-memory" "$TMP_DIR/munin-reject.out" &&
   grep -Fq -- "/home/magnus/munin-memory" "$TMP_DIR/munin-reject.out"; then
  pass "munin-memory-shaped contradiction: diagnostic names both the unit path and the registry deploy_path"
else
  fail "munin-memory-shaped contradiction: diagnostic must name both the unit's WorkingDirectory and the registry deploy_path"
  sed -n '1,80p' "$TMP_DIR/munin-reject.out"
fi

# ---------------------------------------------------------------------------
# Part 2: EnvironmentFile-only contradiction (WorkingDirectory correct, but
# EnvironmentFile resolves outside deploy_path) must also be caught.
# ---------------------------------------------------------------------------

mkdir -p "$TMP_DIR/repos/env-mismatch/systemd"
cat > "$TMP_DIR/repos/env-mismatch/systemd/alpha.service" << 'EOF'
[Service]
Type=simple
WorkingDirectory=/srv/alpha
ExecStart=/usr/bin/node dist/index.js
EnvironmentFile=/etc/alpha/.env
EOF
printf '%s\n' '{"name":"alpha"}' > "$TMP_DIR/repos/env-mismatch/package.json"
commit_fixture_repo "$TMP_DIR/repos/env-mismatch"
ENV_SHA=$(git -C "$TMP_DIR/repos/env-mismatch" rev-parse HEAD)

cat > "$TMP_DIR/env-mismatch-registry.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "env-mismatch", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE"
rc=0
REGISTRY_PATH="$TMP_DIR/env-mismatch-registry.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
  PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "alpha=$TMP_DIR/repos/env-mismatch@$ENV_SHA" \
    >"$TMP_DIR/env-reject.out" 2>&1 || rc=$?

if [[ "$rc" != 0 && ! -e "$SSH_CAPTURE" && ! -e "$RSYNC_CAPTURE" ]]; then
  pass "EnvironmentFile-only contradiction fails before any remote call"
else
  fail "EnvironmentFile-only contradiction must fail before any remote call"
fi
if grep -Fq -- "EnvironmentFile=/etc/alpha/.env" "$TMP_DIR/env-reject.out" &&
   grep -Fq -- "/srv/alpha" "$TMP_DIR/env-reject.out"; then
  pass "EnvironmentFile-only contradiction names both the unit path and the registry deploy_path"
else
  fail "EnvironmentFile-only contradiction must name both paths"
  sed -n '1,80p' "$TMP_DIR/env-reject.out"
fi

# ---------------------------------------------------------------------------
# Part 3: a consistent unit (WorkingDirectory/EnvironmentFile genuinely under
# deploy_path) must not be rejected by the new guard.
# ---------------------------------------------------------------------------

mkdir -p "$TMP_DIR/repos/consistent/systemd"
cat > "$TMP_DIR/repos/consistent/systemd/alpha.service" << 'EOF'
[Service]
Type=simple
User=magnus
WorkingDirectory=/srv/alpha
ExecStart=/usr/bin/node dist/index.js
EnvironmentFile=/srv/alpha/.env
EOF
printf '%s\n' '{"name":"alpha"}' > "$TMP_DIR/repos/consistent/package.json"
commit_fixture_repo "$TMP_DIR/repos/consistent"
CONSISTENT_SHA=$(git -C "$TMP_DIR/repos/consistent" rev-parse HEAD)

cat > "$TMP_DIR/consistent-registry.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "consistent", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF

rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE"
rc=0
REGISTRY_PATH="$TMP_DIR/consistent-registry.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
  PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" "alpha=$TMP_DIR/repos/consistent@$CONSISTENT_SHA" \
    >"$TMP_DIR/consistent.out" 2>&1 || rc=$?

if [[ "$rc" == 0 ]]; then
  pass "consistent WorkingDirectory/EnvironmentFile under deploy_path is not rejected by the new guard"
else
  fail "consistent WorkingDirectory/EnvironmentFile under deploy_path must not be rejected"
  sed -n '1,120p' "$TMP_DIR/consistent.out"
fi

# The remote install/backup/restart chain for the consistent case must place
# the User/EnvironmentFile preflight and the pre-overwrite backup strictly
# before install, and install strictly before daemon-reload/restart.
final_call="$(grep -F 'DEPLOY_OK' "$SSH_CAPTURE" | tail -1)"
case "$final_call" in
  *"getent passwd 'magnus'"*"install -D -m644"*"daemon-reload"*"restart"*)
    pass "remote User= preflight precedes install, which precedes reload/restart"
    ;;
  *)
    fail "remote User= preflight must precede install, which must precede reload/restart"
    printf '%s\n' "$final_call"
    ;;
esac
case "$final_call" in
  *"test -f \"\$dest\""*"install -D -m644"*)
    pass "pre-overwrite backup check precedes install"
    ;;
  *)
    fail "pre-overwrite backup check must precede install"
    printf '%s\n' "$final_call"
    ;;
esac
# shellcheck disable=SC2016 # literal remote-shell fragment expected in capture
if grep -Fq -- '.bak.$(date -u +%Y%m%dT%H%M%SZ)' "$SSH_CAPTURE"; then
  pass "backup path is timestamped and predictable"
else
  fail "backup path must be timestamped and predictable"
fi

# ---------------------------------------------------------------------------
# Part 4: direct behavioral proof of the remote User/EnvironmentFile preflight
# and backup fragment -- executed for real via sh -c against a fixture
# filesystem and a faked getent/date, independent of deploy.sh's mocked ssh.
# ---------------------------------------------------------------------------

FIXTURE="$TMP_DIR/target-guard-fixture"
mkdir -p "$FIXTURE/etc/systemd/system"
printf '%s\n' 'old unit' > "$FIXTURE/etc/systemd/system/alpha.service"

cat > "$TMP_DIR/bin/getent" << 'EOF'
#!/usr/bin/env bash
[[ "$1" == "passwd" ]] || exit 2
case "$2" in
  realuser) exit 0 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TMP_DIR/bin/getent"

# Part 4 runs the generated fragment for real with privileged=true (the
# system-scope shape). Provide a no-op passthrough so "sudo test"/"sudo cp"
# run directly as the current user against the fixture filesystem rather than
# prompting for a real password.
cat > "$TMP_DIR/bin/sudo" << 'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
chmod +x "$TMP_DIR/bin/sudo"

frag=$(prepare_unit_target_preflight_and_backup_command true alpha.service realuser \
  "$FIXTURE/etc/systemd/system/alpha.env")
printf '%s\n' present > "$FIXTURE/etc/systemd/system/alpha.env"

rc=0
PATH="$TMP_DIR/bin:$PATH" dest="$FIXTURE/etc/systemd/system/alpha.service" \
  sh -c "$frag echo GUARD_OK" >"$TMP_DIR/guard.out" 2>&1 || rc=$?
if [[ "$rc" == 0 ]] && grep -Fq "GUARD_OK" "$TMP_DIR/guard.out"; then
  pass "target guard passes when User exists and EnvironmentFile is present"
else
  fail "target guard must pass when User exists and EnvironmentFile is present"
  cat "$TMP_DIR/guard.out"
fi
backup_path=$(find "$FIXTURE/etc/systemd/system" -name 'alpha.service.bak.*')
if [[ -n "$backup_path" ]] && grep -Fq "old unit" "$backup_path"; then
  pass "existing unit is backed up to a predictable timestamped path before overwrite"
else
  fail "existing unit must be backed up to a predictable timestamped path before overwrite"
fi
if grep -Fq "Backed up prior unit: $FIXTURE/etc/systemd/system/alpha.service -> " "$TMP_DIR/guard.out"; then
  pass "backup path is printed"
else
  fail "backup path must be printed"
fi

rc=0
frag=$(prepare_unit_target_preflight_and_backup_command true alpha.service missinguser)
PATH="$TMP_DIR/bin:$PATH" dest="$FIXTURE/etc/systemd/system/alpha.service" \
  sh -c "$frag echo GUARD_OK" >"$TMP_DIR/guard-baduser.out" 2>&1 || rc=$?
if [[ "$rc" != 0 ]] && ! grep -Fq "GUARD_OK" "$TMP_DIR/guard-baduser.out" &&
   grep -Fq "User=missinguser" "$TMP_DIR/guard-baduser.out"; then
  pass "target guard fails closed when the declared User does not exist on the target"
else
  fail "target guard must fail closed when the declared User does not exist on the target"
  cat "$TMP_DIR/guard-baduser.out"
fi

rc=0
frag=$(prepare_unit_target_preflight_and_backup_command true alpha.service realuser \
  "$FIXTURE/etc/systemd/system/absent.env")
PATH="$TMP_DIR/bin:$PATH" dest="$FIXTURE/etc/systemd/system/alpha.service" \
  sh -c "$frag echo GUARD_OK" >"$TMP_DIR/guard-badenv.out" 2>&1 || rc=$?
if [[ "$rc" != 0 ]] && ! grep -Fq "GUARD_OK" "$TMP_DIR/guard-badenv.out" &&
   grep -Fq "EnvironmentFile=$FIXTURE/etc/systemd/system/absent.env" "$TMP_DIR/guard-badenv.out"; then
  pass "target guard fails closed when the declared EnvironmentFile is absent from the target"
else
  fail "target guard must fail closed when the declared EnvironmentFile is absent from the target"
  cat "$TMP_DIR/guard-badenv.out"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
