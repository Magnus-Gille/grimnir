#!/usr/bin/env bash
# security-scan-delta.test.sh — unit tests for the scan_escalated helper.
# Tests the pure escalation logic in isolation (no Munin, no network, no node).
#
# Sources the REAL scan_escalated from lib/escalation.sh (no duplicated copy)
# so the test can never silently drift from the production logic.
# Compatible with bash 3.2+ (macOS default).

set -euo pipefail

PASS=0
FAIL=0

# Source the production function under test.
# shellcheck source=scripts/lib/escalation.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/escalation.sh"

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

# ── Robustness: non-numeric inputs (e.g. a poisoned multi-writer Munin record)
# must be treated as 0, never reach the `[[ -gt ]]` arithmetic context, and must
# not abort the function under `set -euo pipefail`. A bare name like `a[...]`
# would otherwise trip nounset ("a: unbound variable") and kill the whole scan.
rm -f /tmp/sce_inject_marker
assert_eq "non-numeric prev -> treated as 0" "no" "$(scan_escalated abc 0 0 0 0 0)"
assert_eq "non-numeric cur  -> treated as 0" "no" "$(scan_escalated 0 0 0 xyz 0 0)"
# Single quotes are intentional: pass the literal payload so coercion (not the
# test harness) decides its fate. Coerced to 0, cur also 0 -> "no".
# shellcheck disable=SC2016
assert_eq "arith-injection prev is inert"    "no" "$(scan_escalated 'a[$(touch /tmp/sce_inject_marker)]' 0 0 0 0 0)"
if [[ -e /tmp/sce_inject_marker ]]; then
  echo "  FAIL: arithmetic injection executed (marker created)"; FAIL=$((FAIL + 1))
  rm -f /tmp/sce_inject_marker
else
  echo "  PASS: arithmetic injection inert (no marker)"; PASS=$((PASS + 1))
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
