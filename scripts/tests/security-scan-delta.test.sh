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

# ── Leading-zero / octal inputs: `[[ -gt ]]` would treat 08/09 as invalid octal
# and error → silent miss. Must be canonicalized base-10, not rejected to 0.
assert_eq "octal-looking escalation (08->09)"  "yes" "$(scan_escalated 08 0 0 09 0 0)"
assert_eq "octal-looking no-change (09 vs 08)" "no"  "$(scan_escalated 09 0 0 08 0 0)"
assert_eq "octal high 08->09"                  "yes" "$(scan_escalated 0 08 0 0 09 0)"
assert_eq "overlong digit string -> 0"         "no"  "$(scan_escalated 0 0 0 99999999999 0 0)"

echo ""
echo "parse_prev_counts tests"
echo "======================================="

# Build a realistic Munin memory_read response wrapping the scanner's stored
# per-repo content (a markdown body with an embedded ```json block).
mk_munin() {  # $1 = inner json block content
  local block="$1"
  REPO_TEXT="## repo — Security State
\`\`\`json
${block}
\`\`\`" node --input-type=commonjs -e \
    'console.log(JSON.stringify({result:{content:[{type:"text",text:process.env.REPO_TEXT}]}}))'
}

assert_eq "valid baseline -> counts + ok" "2	3	1	ok" \
  "$(mk_munin '{"audit":{"critical":2,"high":3},"secrets":[{"file":"a"}]}' | parse_prev_counts)"
assert_eq "first run (envelope, no block) -> 0 0 0 ok" "0	0	0	ok" \
  "$(node --input-type=commonjs -e 'console.log(JSON.stringify({result:{content:[{type:"text",text:"no scans yet"}]}}))' | parse_prev_counts)"
assert_eq "rpc failure sentinel {} -> unavailable" "0	0	0	unavailable" \
  "$(printf '%s' '{}' | parse_prev_counts)"
assert_eq "malformed json block -> unavailable" "0	0	0	unavailable" \
  "$(mk_munin '{not valid json' | parse_prev_counts)"
assert_eq "poisoned partial-numeric (999junk) -> unavailable" "0	0	0	unavailable" \
  "$(mk_munin '{"audit":{"critical":"999junk","high":0},"secrets":[]}' | parse_prev_counts)"
assert_eq "poisoned fake-array secrets {length:999} -> unavailable" "0	0	0	unavailable" \
  "$(mk_munin '{"audit":{"critical":0,"high":0},"secrets":{"length":999}}' | parse_prev_counts)"
assert_eq "garbage (not json at all) -> unavailable" "0	0	0	unavailable" \
  "$(printf '%s' 'totally not json' | parse_prev_counts)"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
