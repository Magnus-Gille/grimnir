#!/usr/bin/env bash
# Proves every centrally orchestrated deploy is bound to an explicit immutable
# source commit before any build or remote mutation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy.sh"
GUARDED_DEPLOY="$SCRIPT_DIR/../guarded-deploy.sh"
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

assert_no_mutation() {
  local desc=$1
  if [[ -e "$MUTATION_CAPTURE" ]]; then
    fail "$desc: must not invoke build, ssh, or rsync"
  else
    pass "$desc: invokes neither build, ssh, nor rsync"
  fi
}

run_rejected() {
  local desc=$1 output=$2
  shift 2
  rm -f "$MUTATION_CAPTURE"
  if REGISTRY_PATH="$REGISTRY" PATH="$TMP_DIR/bin:$PATH" \
      bash "$DEPLOY" "$@" >"$output" 2>&1; then
    fail "$desc: deploy must fail"
  else
    pass "$desc: deploy fails"
  fi
  assert_no_mutation "$desc"
}

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/source/systemd" "$TMP_DIR/source/subdir"

cat > "$TMP_DIR/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'ssh:%s\n' "$*" >> "$MUTATION_CAPTURE"
command=${*: -1}
if [[ "$command" == *"DEPLOY_MARKER_INVALIDATED"* ]]; then
  printf '%s\n' DEPLOY_MARKER_INVALIDATED:unknown
elif [[ "$command" == *"DEPLOY_OK"* ]]; then
  printf '%s\n' DEPLOY_OK
fi
EOF

cat > "$TMP_DIR/bin/rsync" <<'EOF'
#!/usr/bin/env bash
printf 'rsync:%s\n' "$*" >> "$MUTATION_CAPTURE"
EOF

cat > "$TMP_DIR/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf 'npm:%s\n' "$*" >> "$MUTATION_CAPTURE"
EOF

cat > "$TMP_DIR/bin/local-deploy" <<'EOF'
#!/usr/bin/env bash
printf 'local-deploy:%s\n' "$*" >> "$GUARDED_CAPTURE"
EOF

chmod +x "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/rsync" "$TMP_DIR/bin/npm" \
  "$TMP_DIR/bin/local-deploy"
MUTATION_CAPTURE="$TMP_DIR/mutations"
GUARDED_CAPTURE="$TMP_DIR/guarded-command"
export MUTATION_CAPTURE GUARDED_CAPTURE

cat > "$TMP_DIR/source/systemd/alpha.service" <<'EOF'
[Service]
ExecStart=/bin/true
EOF
cat > "$TMP_DIR/source/systemd/beta.service" <<'EOF'
[Service]
ExecStart=/bin/true
EOF
printf '%s\n' '{"name":"source"}' > "$TMP_DIR/source/package.json"
printf '%s\n' keep > "$TMP_DIR/source/subdir/keep.txt"

git init -q -b main "$TMP_DIR/source"
git -C "$TMP_DIR/source" add .
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/source" commit -q -m stale
STALE_SHA=$(git -C "$TMP_DIR/source" rev-parse HEAD)

printf '%s\n' current > "$TMP_DIR/source/current.txt"
git -C "$TMP_DIR/source" add current.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/source" commit -q -m current
EXPECTED_SHA=$(git -C "$TMP_DIR/source" rev-parse HEAD)

CORRECT_WORKTREE="$TMP_DIR/correct-detached"
STALE_WORKTREE="$TMP_DIR/stale-detached"
git -C "$TMP_DIR/source" worktree add -q --detach "$CORRECT_WORKTREE" "$EXPECTED_SHA"
git -C "$TMP_DIR/source" worktree add -q --detach "$STALE_WORKTREE" "$STALE_SHA"
CORRECT_WORKTREE=$(cd "$CORRECT_WORKTREE" && pwd -P)
STALE_WORKTREE=$(cd "$STALE_WORKTREE" && pwd -P)

if git -C "$CORRECT_WORKTREE" symbolic-ref -q HEAD >/dev/null; then
  fail "correct fixture must be a detached worktree"
else
  pass "correct fixture is a detached worktree"
fi
if [[ -x "$GUARDED_DEPLOY" ]]; then
  pass "generic deploy guard is executable"
else
  fail "generic deploy guard must be executable"
fi

# The generic wrapper is the orchestration path for owning-repository deploy
# commands outside services.json's centrally deployable component set.
rm -f "$GUARDED_CAPTURE"
if (
  cd "$STALE_WORKTREE"
  PATH="$TMP_DIR/bin:$PATH" "$GUARDED_DEPLOY" \
    "$CORRECT_WORKTREE" "$EXPECTED_SHA" -- local-deploy wrong-cwd
) >"$TMP_DIR/guard-wrong-cwd.out" 2>&1; then
  fail "generic guard must reject a deploy command run from the wrong cwd"
else
  pass "generic guard rejects a deploy command run from the wrong cwd"
fi
if [[ ! -e "$GUARDED_CAPTURE" ]] &&
   grep -Fq "Expected source: $CORRECT_WORKTREE @ $EXPECTED_SHA" \
    "$TMP_DIR/guard-wrong-cwd.out" &&
   grep -Fq "Actual source: $STALE_WORKTREE @ $STALE_SHA" \
    "$TMP_DIR/guard-wrong-cwd.out"; then
  pass "generic wrong-cwd failure precedes command execution with diagnostics"
else
  fail "generic wrong-cwd failure must precede command execution with diagnostics"
fi

rm -f "$GUARDED_CAPTURE"
if (
  cd "$STALE_WORKTREE"
  PATH="$TMP_DIR/bin:$PATH" "$GUARDED_DEPLOY" \
    "$STALE_WORKTREE" "$EXPECTED_SHA" -- local-deploy stale
) >"$TMP_DIR/guard-stale.out" 2>&1; then
  fail "generic guard must reject a stale clean checkout"
else
  pass "generic guard rejects a stale clean checkout"
fi
if [[ ! -e "$GUARDED_CAPTURE" ]] &&
   grep -Fq "Actual source: $STALE_WORKTREE @ $STALE_SHA" \
    "$TMP_DIR/guard-stale.out"; then
  pass "generic stale-checkout failure precedes command execution"
else
  fail "generic stale-checkout failure must precede command execution"
fi

rm -f "$GUARDED_CAPTURE"
if (
  cd "$CORRECT_WORKTREE"
  PATH="$TMP_DIR/bin:$PATH" "$GUARDED_DEPLOY" \
    "$CORRECT_WORKTREE" "$EXPECTED_SHA" -- local-deploy detached
) >"$TMP_DIR/guard-correct.out" 2>&1; then
  pass "generic guard executes from the correct detached worktree"
else
  fail "generic guard must execute from the correct detached worktree"
fi
if grep -Fxq "local-deploy:detached" "$GUARDED_CAPTURE"; then
  pass "generic guard reaches the owning-repository deploy entry point"
else
  fail "generic guard must reach the owning-repository deploy entry point"
fi

REGISTRY="$TMP_DIR/services.json"
cat > "$REGISTRY" <<'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "source", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    },
    {
      "name": "beta", "repo": "source", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/beta",
      "persistent_paths": [], "needs_build": false,
      "systemd_units": [{ "name": "beta", "type": "service" }]
    }
  ]
}
EOF

run_rejected "no-argument deploy" "$TMP_DIR/no-arguments.out"
if grep -Fq "requires at least one service bound to an explicit full commit SHA" \
    "$TMP_DIR/no-arguments.out"; then
  pass "no-argument deploy reports the bound-source requirement"
else
  fail "no-argument deploy must report the bound-source requirement"
fi

run_rejected "missing expected revision" "$TMP_DIR/missing.out" \
  "alpha=$CORRECT_WORKTREE"
if grep -Fq "requires an explicit full commit SHA" "$TMP_DIR/missing.out"; then
  pass "missing revision reports the immutable revision requirement"
else
  fail "missing revision must report the immutable revision requirement"
fi

run_rejected "wrong directory" "$TMP_DIR/wrong-directory.out" \
  "alpha=$CORRECT_WORKTREE/subdir@$EXPECTED_SHA"
if grep -Fq "Expected source: $CORRECT_WORKTREE/subdir @ $EXPECTED_SHA" \
    "$TMP_DIR/wrong-directory.out" &&
   grep -Fq "Actual source: $CORRECT_WORKTREE @ $EXPECTED_SHA" \
    "$TMP_DIR/wrong-directory.out"; then
  pass "wrong directory reports expected and actual source identity"
else
  fail "wrong directory must report expected and actual source identity"
fi

run_rejected "stale clean checkout" "$TMP_DIR/stale.out" \
  "alpha=$STALE_WORKTREE@$EXPECTED_SHA"
if [[ -z "$(git -C "$STALE_WORKTREE" status --porcelain)" ]] &&
   grep -Fq "Expected source: $STALE_WORKTREE @ $EXPECTED_SHA" "$TMP_DIR/stale.out" &&
   grep -Fq "Actual source: $STALE_WORKTREE @ $STALE_SHA" "$TMP_DIR/stale.out"; then
  pass "stale clean checkout reports expected and actual revisions"
else
  fail "stale clean checkout must fail with expected/actual diagnostics"
fi

# All selected sources must pass before the first service mutates anything.
run_rejected "multi-service source preflight" "$TMP_DIR/multi.out" \
  "alpha=$CORRECT_WORKTREE@$EXPECTED_SHA" \
  "beta=$STALE_WORKTREE@$EXPECTED_SHA"

rm -f "$MUTATION_CAPTURE"
if REGISTRY_PATH="$REGISTRY" PATH="$TMP_DIR/bin:$PATH" \
    bash "$DEPLOY" "alpha=$CORRECT_WORKTREE@$EXPECTED_SHA" \
      >"$TMP_DIR/correct.out" 2>&1; then
  pass "correct detached worktree completes mocked deploy"
else
  fail "correct detached worktree must complete mocked deploy"
  sed -n '1,160p' "$TMP_DIR/correct.out"
fi
if grep -Fq "Expected source: $CORRECT_WORKTREE @ $EXPECTED_SHA" \
    "$TMP_DIR/correct.out" &&
   grep -Fq "Actual source: $CORRECT_WORKTREE @ $EXPECTED_SHA" \
    "$TMP_DIR/correct.out"; then
  pass "correct detached worktree reports bound source identity"
else
  fail "correct detached worktree must report bound source identity"
fi
if grep -Fq "ssh:" "$MUTATION_CAPTURE" &&
   grep -Fq "rsync:" "$MUTATION_CAPTURE"; then
  pass "correct detached worktree reaches mocked remote mutation"
else
  fail "correct detached worktree must reach mocked remote mutation"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
