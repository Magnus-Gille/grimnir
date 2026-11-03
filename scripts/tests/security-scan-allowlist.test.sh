#!/usr/bin/env bash
# Integration coverage for the scanner's committed .gitleaks.toml contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/../security-scan.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/repos/alpha/src" "$TMP_DIR/repos/alpha/tests"
cat > "$TMP_DIR/bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"auditReportVersion":2,"vulnerabilities":{},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}}}'
EOF
chmod +x "$TMP_DIR/bin/npm"
cat > "$TMP_DIR/registry.json" <<'EOF'
{"repository_authority":{"default_owner":"Magnus-Gille"},"components":[{"name":"alpha","repo":"alpha","host":null,"port":null,"deploy":false,"scan":true,"needs_build":false,"systemd_units":[]}]}
EOF
cat > "$TMP_DIR/repos/alpha/package-lock.json" <<'EOF'
{"name":"alpha","lockfileVersion":3,"packages":{}}
EOF
git -C "$TMP_DIR/repos/alpha" init -q -b main
git -C "$TMP_DIR/repos/alpha" config user.email test@example.invalid
git -C "$TMP_DIR/repos/alpha" config user.name GrimnirTest
git -C "$TMP_DIR/repos/alpha" remote add origin https://github.com/Magnus-Gille/alpha.git

write_token_files() {
  local token=$1
  printf 'export const token = "%s";\n' "$token" > "$TMP_DIR/repos/alpha/src/app.ts"
  printf 'const token = "%s";\n' "$token" > "$TMP_DIR/repos/alpha/tests/app.test.ts"
}

commit_fixture() {
  git -C "$TMP_DIR/repos/alpha" add -A
  GIT_AUTHOR_NAME=GrimnirTest GIT_AUTHOR_EMAIL=test@example.invalid \
  GIT_COMMITTER_NAME=GrimnirTest GIT_COMMITTER_EMAIL=test@example.invalid \
    git -C "$TMP_DIR/repos/alpha" commit -q --allow-empty -m fixture
}

run_scan() {
  local output=$1 rc=0
  REPOS_DIR="$TMP_DIR/repos" REGISTRY_PATH="$TMP_DIR/registry.json" \
    PATH="$TMP_DIR/bin:$PATH" bash "$SCANNER" --dry-run --verbose >"$output" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

assert_scan() {
  local name=$1 expected_rc=$2 expected_status=$3 expected_complete=$4 output=$5 rc
  rc="$(run_scan "$output")"
  if [[ "$rc" == "$expected_rc" ]]; then pass "$name: exit $expected_rc"; else fail "$name: expected exit $expected_rc, got $rc"; fi
  if grep -Fq "Overall status: $expected_status" "$output"; then pass "$name: status $expected_status"; else fail "$name: missing status $expected_status"; fi
  if grep -Fq "COVERAGE: complete=$expected_complete" "$output"; then pass "$name: complete=$expected_complete"; else fail "$name: missing completeness"; fi
}

echo "security scan allowlist tests"
echo "============================"

# A committed exact exception applies in both source and tests. A working-tree
# edit cannot change the immutable policy used by the scan.
write_token_files "sk-ant-WORKTREEPOLICYTOKEN123456"
cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[[allowlists]]
regexTarget = "secret"
regexes = ["sk-ant-COMMITTEDONLYTOKEN123456"]
EOF
commit_fixture
cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[[allowlists]]
regexTarget = "secret"
regexes = ["sk-ant-WORKTREEPOLICYTOKEN123456"]
EOF
output="$TMP_DIR/worktree-policy.out"
assert_scan "working-tree-only policy is ignored" 0 critical true "$output"
if grep -Fq "WORKTREEPOLICYTOKEN123456" "$output"; then fail "working-tree policy output leaks synthetic value"; else pass "working-tree policy output is content-free"; fi

# Finite alternations and character classes are accepted, but equality is to
# the complete candidate: an extra suffix is not an exception.
write_token_files "sk-ant-OTHERTOKEN0000000200"
cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[[allowlists]]
regexTarget = "secret"
regexes = ["sk-ant-(?:ALLOWED|OTHER)TOKEN[01][01][01][01][01][01][01]200"]
EOF
commit_fixture
output="$TMP_DIR/finite-regex.out"
assert_scan "finite regex exception is accepted" 0 clean true "$output"
write_token_files "sk-ant-OTHERTOKEN0000000200X"
commit_fixture
output="$TMP_DIR/finite-mutation.out"
assert_scan "finite regex suffix mutation is detected" 0 critical true "$output"

# For target=secret, a Bearer prefix is stripped before exact comparison.
write_token_files "Bearer bearerfixturetoken1234567890"
cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[[allowlists]]
regexTarget = "secret"
regexes = ["bearerfixturetoken1234567890"]
EOF
commit_fixture
output="$TMP_DIR/bearer-secret.out"
assert_scan "Bearer prefix is stripped for secret equality" 0 clean true "$output"

# target=match compares the complete scanner match, including Bearer.
write_token_files "Bearer bearerfixturematch1234567890"
cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[[allowlists]]
regexTarget = "match"
regexes = ["Bearer bearerfixturematch1234567890"]
EOF
commit_fixture
output="$TMP_DIR/bearer-match.out"
assert_scan "match target compares the complete Bearer match" 0 clean true "$output"

# Missing configuration is a normal scan with no exceptions, not incomplete.
write_token_files "sk-ant-NOCONFIGTOKEN1234567"
rm -f "$TMP_DIR/repos/alpha/.gitleaks.toml"
commit_fixture
output="$TMP_DIR/missing-config.out"
assert_scan "missing config keeps normal scanning" 0 critical true "$output"

# Invalid TOML and unsupported broad regexes fail visibly incomplete rather
# than silently falling back to an unsafe policy.
write_token_files "sk-ant-INVALIDCONFIGTOKEN123456"
cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[[allowlists]
regexTarget = "secret"
EOF
commit_fixture
output="$TMP_DIR/invalid-toml.out"
assert_scan "invalid TOML fails closed" 1 incomplete false "$output"

cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[[allowlists]]
regexTarget = "secret"
regexes = [".*"]
EOF
commit_fixture
output="$TMP_DIR/broad-regex.out"
assert_scan "unsupported broad regex fails closed" 1 incomplete false "$output"

# TOML integers must not be accepted as Boolean extension settings.
cat > "$TMP_DIR/repos/alpha/.gitleaks.toml" <<'EOF'
[extend]
useDefault = 1
EOF
commit_fixture
output="$TMP_DIR/extension-type.out"
assert_scan "non-Boolean extension setting fails closed" 1 incomplete false "$output"

# A configuration that cannot be decoded is a read failure, not a reason to
# continue with an implicit exception policy.
printf '\377\377\n' > "$TMP_DIR/repos/alpha/.gitleaks.toml"
commit_fixture
output="$TMP_DIR/config-read-error.out"
assert_scan "configuration read failure fails closed" 1 incomplete false "$output"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
