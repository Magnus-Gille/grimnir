#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/../security-scan.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/repos/alpha"
cat > "$TMP_DIR/bin/npm" << 'EOF'
#!/usr/bin/env bash
if [[ -n "${NPM_AUDIT_MUTATE_FILE:-}" ]]; then
  printf '%s\n' 'const later = "sk-abcdefghijklmnopqrstuvwxyz123456";' >> "$NPM_AUDIT_MUTATE_FILE"
fi
if [[ "${NPM_AUDIT_MUTATE_PWD:-}" == "true" ]]; then
  printf '%s\n' 'const later = "sk-abcdefghijklmnopqrstuvwxyz123456";' >> package-lock.json
fi
if [[ "${NPM_AUDIT_MUTATE_BACKGROUND:-}" == "true" ]]; then
  ( sleep 0.05; printf '%s\n' 'const later = "sk-abcdefghijklmnopqrstuvwxyz123456";' >> package-lock.json ) &
fi
case "$NPM_AUDIT_FIXTURE" in
  clean)
    printf '%s\n' '{"auditReportVersion":2,"vulnerabilities":{},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}}}'
    ;;
  vulnerable)
    printf '%s\n' '{"auditReportVersion":2,"vulnerabilities":{"dep":{"severity":"high"}},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":1,"critical":0,"total":1}}}'
    exit 1
    ;;
  error-json)
    printf '%s\n' '{"error":{"code":"ENETUNREACH","summary":"registry unavailable"}}'
    exit 1
    ;;
  no-output) exit 1 ;;
esac
EOF
chmod +x "$TMP_DIR/bin/npm"

cat > "$TMP_DIR/bin/grep" << 'EOF'
#!/usr/bin/env bash
/usr/bin/grep "$@"
rc=$?
if [[ "${SCAN_TEST_SLOW_GREP:-}" == "true" ]]; then
  sleep 0.02
fi
exit "$rc"
EOF
chmod +x "$TMP_DIR/bin/grep"

cat > "$TMP_DIR/bin/partial-ls-tree" << 'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == "ls-tree" ]]; then
    printf 'package-lock.json\0'
    exit 1
  fi
done
exec git "$@"
EOF
chmod +x "$TMP_DIR/bin/partial-ls-tree"

cat > "$TMP_DIR/bin/failing-chmod" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMP_DIR/bin/failing-chmod"

cat > "$TMP_DIR/registry.json" << 'EOF'
{
  "repository_authority": {"default_owner":"Magnus-Gille"},
  "components": [
    {"name":"alpha","repo":"alpha","host":null,"port":null,"deploy":false,"scan":true,"needs_build":false,"systemd_units":[]}
  ]
}
EOF
printf '%s\n' '{"name":"alpha","lockfileVersion":3,"packages":{}}' > "$TMP_DIR/repos/alpha/package-lock.json"
git init -q -b main "$TMP_DIR/repos/alpha"
git -C "$TMP_DIR/repos/alpha" add package-lock.json
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/repos/alpha" commit -q -m seed
git -C "$TMP_DIR/repos/alpha" remote add origin https://github.com/Magnus-Gille/alpha.git

run_scan() {
  local mode=$1 output=$2 rc=0
  NPM_AUDIT_FIXTURE="$mode" REPOS_DIR="$TMP_DIR/repos" REGISTRY_PATH="$TMP_DIR/registry.json" \
    PATH="$TMP_DIR/bin:$PATH" bash "$SCANNER" --dry-run > "$output" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

assert_run() {
  local desc=$1 mode=$2 expected_rc=$3 expected_status=$4 expected_complete=$5
  local output="$TMP_DIR/${mode}.out" rc
  rc="$(run_scan "$mode" "$output")"
  if [[ "$rc" == "$expected_rc" ]]; then
    pass "$desc: exit $expected_rc"
  else
    fail "$desc: expected exit $expected_rc, got $rc"
  fi
  if grep -Fq "Overall status: $expected_status" "$output"; then
    pass "$desc: status $expected_status"
  else
    fail "$desc: missing status $expected_status"
  fi
  if grep -Fq "COVERAGE: complete=$expected_complete" "$output"; then
    pass "$desc: complete=$expected_complete"
  else
    fail "$desc: missing completeness"
  fi
}

echo "security scan completeness tests"
echo "================================"
assert_run "valid clean audit" clean 0 clean true
assert_run "valid vulnerability audit" vulnerable 0 high true
assert_run "npm error JSON" error-json 1 incomplete false
assert_run "npm no output" no-output 1 incomplete false

# The scanner must inspect the immutable commit snapshot it prepared before
# npm runs, not reread a mutable checkout during the later secret phase.
rc=0
NPM_AUDIT_FIXTURE=clean NPM_AUDIT_MUTATE_FILE="$TMP_DIR/repos/alpha/package-lock.json" \
  REPOS_DIR="$TMP_DIR/repos" REGISTRY_PATH="$TMP_DIR/registry.json" PATH="$TMP_DIR/bin:$PATH" \
  bash "$SCANNER" --dry-run > "$TMP_DIR/snapshot.out" 2>&1 || rc=$?
if [[ "$rc" == 0 ]] && grep -Fq 'alpha: OK (no secrets found)' "$TMP_DIR/snapshot.out"; then
  pass "source snapshot remains bound when checkout mutates during audit"
else
  fail "source snapshot must prevent a mutable checkout from altering coverage"
fi

rc=0
NPM_AUDIT_FIXTURE=clean NPM_AUDIT_MUTATE_PWD=true REPOS_DIR="$TMP_DIR/repos" \
  REGISTRY_PATH="$TMP_DIR/registry.json" PATH="$TMP_DIR/bin:$PATH" \
  bash "$SCANNER" --dry-run > "$TMP_DIR/snapshot-mutated.out" 2>&1 || rc=$?
if [[ "$rc" == 0 ]] && grep -Fq 'alpha: OK (no secrets found)' "$TMP_DIR/snapshot-mutated.out"; then
  pass "read-only snapshot blocks mutation during audit"
else
  fail "read-only snapshot must block mutation during audit"
fi

rc=0
NPM_AUDIT_FIXTURE=clean NPM_AUDIT_MUTATE_BACKGROUND=true SCAN_TEST_SLOW_GREP=true REPOS_DIR="$TMP_DIR/repos" \
  REGISTRY_PATH="$TMP_DIR/registry.json" PATH="$TMP_DIR/bin:$PATH" \
  bash "$SCANNER" --dry-run > "$TMP_DIR/snapshot-delayed.out" 2>&1 || rc=$?
if [[ "$rc" == 0 ]] && grep -Fq 'alpha: OK (no secrets found)' "$TMP_DIR/snapshot-delayed.out"; then
  pass "read-only snapshot blocks delayed mutation during secret scan"
else
  fail "read-only snapshot must block delayed mutation during secret scan"
fi

rc=0
REPOS_DIR="$TMP_DIR/missing-repos" REGISTRY_PATH="$TMP_DIR/registry.json" PATH="$TMP_DIR/bin:$PATH" \
  bash "$SCANNER" --dry-run > "$TMP_DIR/missing-checkout.out" 2>&1 || rc=$?
if [[ "$rc" == 1 ]] && grep -Fq 'COVERAGE: complete=false' "$TMP_DIR/missing-checkout.out" && \
   grep -Fq 'error:source-snapshot' "$TMP_DIR/missing-checkout.out"; then
  pass "missing authoritative source checkout fails closed"
else
  fail "missing authoritative source checkout must fail coverage"
fi

rc=0
NPM_AUDIT_FIXTURE=clean GIT_LS_TREE_BIN="$TMP_DIR/bin/partial-ls-tree" REPOS_DIR="$TMP_DIR/repos" \
  REGISTRY_PATH="$TMP_DIR/registry.json" PATH="$TMP_DIR/bin:$PATH" \
  bash "$SCANNER" --dry-run > "$TMP_DIR/partial-list.out" 2>&1 || rc=$?
if [[ "$rc" == 1 ]] && grep -Fq 'error:source-snapshot' "$TMP_DIR/partial-list.out"; then
  pass "partial source enumeration fails coverage"
else
  fail "partial source enumeration must not claim coverage"
fi

rc=0
NPM_AUDIT_FIXTURE=clean CHMOD_BIN="$TMP_DIR/bin/failing-chmod" REPOS_DIR="$TMP_DIR/repos" \
  REGISTRY_PATH="$TMP_DIR/registry.json" PATH="$TMP_DIR/bin:$PATH" \
  bash "$SCANNER" --dry-run > "$TMP_DIR/chmod-failure.out" 2>&1 || rc=$?
if [[ "$rc" == 1 ]] && grep -Fq 'error:source-snapshot' "$TMP_DIR/chmod-failure.out"; then
  pass "snapshot permission failure fails coverage"
else
  fail "snapshot permission failure must not claim coverage"
fi

mkdir -p "$TMP_DIR/wrong-root/other/subdir"
cp "$TMP_DIR/repos/alpha/package-lock.json" "$TMP_DIR/wrong-root/other/package-lock.json"
git init -q -b main "$TMP_DIR/wrong-root/other"
git -C "$TMP_DIR/wrong-root/other" add package-lock.json
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/wrong-root/other" commit -q -m seed
git -C "$TMP_DIR/wrong-root/other" remote add origin https://github.com/Magnus-Gille/alpha.git
ln -s "$TMP_DIR/wrong-root/other/subdir" "$TMP_DIR/wrong-root/alpha"
rc=0
REPOS_DIR="$TMP_DIR/wrong-root" REGISTRY_PATH="$TMP_DIR/registry.json" PATH="$TMP_DIR/bin:$PATH" \
  bash "$SCANNER" --dry-run > "$TMP_DIR/nested-checkout.out" 2>&1 || rc=$?
if [[ "$rc" == 1 ]] && grep -Fq 'error:source-snapshot' "$TMP_DIR/nested-checkout.out"; then
  pass "nested path is not accepted as a repository checkout"
else
  fail "nested path must not claim source authority"
fi

mkdir -p "$TMP_DIR/symlink-root"
ln -s "$TMP_DIR/repos/alpha" "$TMP_DIR/symlink-root/alpha"
rc=0
REPOS_DIR="$TMP_DIR/symlink-root" REGISTRY_PATH="$TMP_DIR/registry.json" PATH="$TMP_DIR/bin:$PATH" \
  bash "$SCANNER" --dry-run > "$TMP_DIR/symlink-checkout.out" 2>&1 || rc=$?
if [[ "$rc" == 1 ]] && grep -Fq 'error:source-snapshot' "$TMP_DIR/symlink-checkout.out"; then
  pass "symlinked repository root is not accepted as source authority"
else
  fail "symlinked repository root must not claim source authority"
fi

rc=0
NPM_AUDIT_FIXTURE=clean REPOS_DIR="$TMP_DIR/repos" REGISTRY_PATH="$TMP_DIR/registry.json" \
  PATH="$TMP_DIR/bin:$PATH" bash "$SCANNER" --dry-run --repo not-registered \
  > "$TMP_DIR/filter.out" 2>&1 || rc=$?
if [[ "$rc" == 1 ]] && grep -Fq -- '--repo must name a scan-enabled component' "$TMP_DIR/filter.out"; then
  pass "unknown --repo is rejected before scanning"
else
  fail "unknown --repo must be rejected"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
