#!/usr/bin/env bash
# End-to-end regression coverage for GRIM-233's committed secret allowlist.
#
# This deliberately invokes the real scanner. The fixture is a throwaway
# committed repository and npm is a local deterministic stub; no network,
# credentials, or real checkout is involved.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/../../scripts/security-scan.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_output() {
  local description=$1 pattern=$2 output=$3
  if grep -Fq -- "$pattern" "$output"; then pass "$description"; else fail "$description"; fi
}

assert_not_output() {
  local description=$1 pattern=$2 output=$3
  if grep -Fq -- "$pattern" "$output"; then fail "$description"; else pass "$description"; fi
}

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/repos/alpha/src" "$TMP_DIR/repos/alpha/tests"

cat > "$TMP_DIR/bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"auditReportVersion":2,"vulnerabilities":{},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}}}'
EOF
chmod +x "$TMP_DIR/bin/npm"

cat > "$TMP_DIR/registry.json" <<'EOF'
{
  "repository_authority": {"default_owner":"Magnus-Gille"},
  "components": [
    {"name":"alpha","repo":"alpha","host":null,"port":null,"deploy":false,"scan":true,"needs_build":false,"systemd_units":[]}
  ]
}
EOF

cat > "$TMP_DIR/repos/alpha/package-lock.json" <<'EOF'
{"name":"alpha","lockfileVersion":3,"packages":{}}
EOF

cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[[allowlists]]
description = "Synthetic fixture values only"
regexTarget = "secret"
regexes = ["sk-ant-ALLOWEDTOKEN1234567890"]

[[allowlists]]
description = "Path-bound fixture value"
regexTarget = "secret"
regexes = ["sk-ant-PATHALLOWEDTOKEN1234567"]
condition = "AND"
paths = ["^src/path-allowed\\.ts$"]
EOF

# The exact allowlisted candidate is present in source and tests. Both are
# scanned; neither is an excuse to skip test files.
cat > "$TMP_DIR/repos/alpha/src/allowed.ts" <<'EOF'
export const fixture = "sk-ant-ALLOWEDTOKEN1234567890";
EOF
cat > "$TMP_DIR/repos/alpha/tests/allowed.test.ts" <<'EOF'
const fixture = "sk-ant-ALLOWEDTOKEN1234567890";
EOF

# Every value below must remain a finding: new test token, same-line mixed
# content, and prefix/suffix mutations of an otherwise allowed candidate.
cat > "$TMP_DIR/repos/alpha/tests/new.test.ts" <<'EOF'
const newToken = "sk-ant-NEWUNALLOWLISTEDTOKEN123456";
EOF
cat > "$TMP_DIR/repos/alpha/src/same-line.ts" <<'EOF'
const mixed = "sk-ant-ALLOWEDTOKEN1234567890" + " sk-ant-NEWUNALLOWLISTEDTOKEN123456";
EOF
cat > "$TMP_DIR/repos/alpha/src/mutations.ts" <<'EOF'
const prefixMutation = "sk-ant-XALLOWEDTOKEN1234567890";
const suffixMutation = "sk-ant-ALLOWEDTOKEN1234567890X";
EOF
cat > "$TMP_DIR/repos/alpha/src/path-allowed.ts" <<'EOF'
export const fixture = "sk-ant-PATHALLOWEDTOKEN1234567";
EOF
cat > "$TMP_DIR/repos/alpha/tests/path-denied.test.ts" <<'EOF'
const fixture = "sk-ant-PATHALLOWEDTOKEN1234567";
EOF

git -C "$TMP_DIR/repos/alpha" init -q -b main
git -C "$TMP_DIR/repos/alpha" config user.email test@example.invalid
git -C "$TMP_DIR/repos/alpha" config user.name GrimnirTest
git -C "$TMP_DIR/repos/alpha" add .
GIT_AUTHOR_NAME=GrimnirTest GIT_AUTHOR_EMAIL=test@example.invalid \
GIT_COMMITTER_NAME=GrimnirTest GIT_COMMITTER_EMAIL=test@example.invalid \
  git -C "$TMP_DIR/repos/alpha" commit -q -m fixture
git -C "$TMP_DIR/repos/alpha" remote add origin https://github.com/Magnus-Gille/alpha.git

run_scan() {
  local output=$1 rc=0
  REPOS_DIR="$TMP_DIR/repos" REGISTRY_PATH="$TMP_DIR/registry.json" \
    PATH="$TMP_DIR/bin:$PATH" bash "$SCANNER" --dry-run --verbose >"$output" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

echo "security scan integration tests"
echo "=============================="

output="$TMP_DIR/findings.out"
rc="$(run_scan "$output")"
if [[ "$rc" == "0" ]]; then pass "scanner completes with findings"; else fail "scanner completes with findings (exit $rc)"; fi
assert_output "findings make overall status critical" "Overall status: critical" "$output"
assert_output "findings retain complete coverage" "COVERAGE: complete=true" "$output"

# These are all real scanner metadata locations. If the old blanket test
# exclusion returns, new.test.ts and path-denied.test.ts disappear.
assert_output "unallowlisted token in tests is detected" "tests/new.test.ts:1" "$output"
assert_output "same-line allowed plus new token is detected" "src/same-line.ts:1" "$output"
assert_output "prefix mutation is detected" "src/mutations.ts:1" "$output"
assert_output "suffix mutation is detected" "src/mutations.ts:2" "$output"
assert_output "path-restricted exception does not apply in tests" "tests/path-denied.test.ts:1" "$output"
assert_not_output "metadata does not print the allowlisted token" "ALLOWEDTOKEN1234567890" "$output"
assert_not_output "metadata does not print the unallowlisted token" "NEWUNALLOWLISTEDTOKEN123456" "$output"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
