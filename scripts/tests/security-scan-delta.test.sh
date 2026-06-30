#!/usr/bin/env bash
# security-scan-delta.test.sh — unit tests for the scan_escalated helper.
# Tests the pure escalation logic in isolation (no Munin, no network, no node).
#
# The function definition below MUST match scan_escalated() in security-scan.sh.
# Compatible with bash 3.2+ (macOS default).

set -euo pipefail

PASS=0
FAIL=0

# ── Pure escalation function (must match security-scan.sh) ──────────────────
# Returns "yes" if current findings exceed the previous snapshot on any
# tracked dimension (critical vulns, high vulns, secret count); "no" otherwise.
scan_escalated() {
  local prev_c="$1" prev_h="$2" prev_s="$3" cur_c="$4" cur_h="$5" cur_s="$6"
  if [[ "$cur_c" -gt "$prev_c" ]] || [[ "$cur_h" -gt "$prev_h" ]] || [[ "$cur_s" -gt "$prev_s" ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

# ── Test harness ─────────────────────────────────────────────────────────────
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

echo "security-scan delta escalation tests"
echo "======================================"

# no-change scenarios -> no
assert_eq "no-change (all zeros)"           "no"  "$(scan_escalated 0 0 0 0 0 0)"
assert_eq "no-change (non-zero same)"       "no"  "$(scan_escalated 1 2 3 1 2 3)"

# counts decreased -> no
assert_eq "counts decreased (all)"         "no"  "$(scan_escalated 5 5 5 3 3 3)"
assert_eq "critical decreased"             "no"  "$(scan_escalated 2 0 0 1 0 0)"
assert_eq "high decreased"                 "no"  "$(scan_escalated 0 3 0 0 2 0)"
assert_eq "secrets decreased"              "no"  "$(scan_escalated 0 0 4 0 0 2)"

# escalation scenarios -> yes
assert_eq "high increased"                 "yes" "$(scan_escalated 0 1 0 0 2 0)"
assert_eq "new critical (from zero)"       "yes" "$(scan_escalated 0 0 0 1 0 0)"
assert_eq "new secret (from zero)"         "yes" "$(scan_escalated 0 0 0 0 0 1)"
assert_eq "critical increased (non-zero)"  "yes" "$(scan_escalated 1 0 0 2 0 0)"
assert_eq "secrets increased (non-zero)"   "yes" "$(scan_escalated 0 0 2 0 0 4)"

# first-run: prev all zero, cur > 0 -> yes
assert_eq "first-run critical"             "yes" "$(scan_escalated 0 0 0 3 0 0)"
assert_eq "first-run high"                 "yes" "$(scan_escalated 0 0 0 0 5 0)"
assert_eq "first-run secrets"              "yes" "$(scan_escalated 0 0 0 0 0 2)"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
