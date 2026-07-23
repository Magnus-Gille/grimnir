#!/usr/bin/env bash
# Regression tests for the Munin namespaces written by security-scan.sh (#98).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/../security-scan.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_contains() {
  local description=$1 expected=$2
  if grep -Fq "$expected" "$SCANNER"; then
    pass "$description"
  else
    fail "$description (missing: $expected)"
  fi
}

assert_not_contains() {
  local description=$1 unexpected=$2
  if grep -Fq "$unexpected" "$SCANNER"; then
    fail "$description (found: $unexpected)"
  else
    pass "$description"
  fi
}

echo "security scan namespace tests"
echo "============================="

# shellcheck disable=SC2016 # Assertions intentionally match literal shell syntax.
assert_contains "scan summaries use one stable namespace" 'NAMESPACE_VAL="security/scans" KEY_VAL="${SCAN_DATE}"'
# shellcheck disable=SC2016 # Assertions intentionally match literal shell syntax.
assert_not_contains "scan dates are not namespace segments" 'NAMESPACE_VAL="security/scans/${SCAN_DATE}" KEY_VAL="summary"'
# shellcheck disable=SC2016 # Assertions intentionally match literal shell syntax.
assert_contains "scan log uses canonical security namespace" 'NAMESPACE_VAL="security" CONTENT_VAL="$log_content"'
# shellcheck disable=SC2016 # Assertions intentionally match literal shell syntax.
assert_not_contains "scan log has no trailing namespace slash" 'NAMESPACE_VAL="security/" CONTENT_VAL="$log_content"'

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
