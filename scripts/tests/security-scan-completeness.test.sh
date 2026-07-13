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

cat > "$TMP_DIR/registry.json" << 'EOF'
{
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
