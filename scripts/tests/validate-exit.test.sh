#!/usr/bin/env bash
# validate-exit.test.sh — unit tests for the audit exit-status contract
# (owner directive, 2026-07-25: "exit status must describe whether the AUDIT
# WORKED, not whether the fleet is clean").
#
# grimnir-validate's live incident: it found exactly what it exists to find
# (a stale worktree entry, a dirty verdandi checkout) and exited 1 because of
# those findings, indistinguishable from a genuine crash. Meanwhile the real
# reporting channel — appending the validation event to Munin — was silently
# broken, so findings never reached the owner through any channel except the
# systemd "failed" state.
#
# audit_exit_code/audit_status_line in lib/validate-exit.sh are the pure
# decision functions extracted from scripts/generate-architecture.sh's
# --validate mode so this contract is unit-testable without live
# infrastructure (SSH, Munin, systemd). Deliberately narrow inputs: a finding
# count is NEVER accepted as an argument, so a future call site cannot
# accidentally wire findings back into the exit decision.
#
# Usage: bash scripts/tests/validate-exit.test.sh
# Exit codes: 0 = all assertions passed, 1 = at least one failed.
# Compatible with bash 3.2+ (macOS default).

set -euo pipefail

PASS=0
FAIL=0

# shellcheck source=scripts/lib/validate-exit.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/validate-exit.sh"

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

echo "validate-exit contract tests"
echo "============================="

# ── audit_exit_code: findings alone must NEVER cause a non-zero exit ───────
assert_eq "clean audit, reported -> 0" \
  "0" "$(audit_exit_code '' true)"
assert_eq "findings present, reported -> 0 (findings are data, not audit failure)" \
  "0" "$(audit_exit_code '' true)"

# ── audit_exit_code: reporting-channel failure IS an audit failure ─────────
assert_eq "clean audit, NOT reported -> 1" \
  "1" "$(audit_exit_code '' false)"
assert_eq "no Munin token available -> 1" \
  "1" "$(audit_exit_code '' unknown)"

# ── audit_exit_code: structural audit failures win regardless of reporting ─
assert_eq "registry unreadable -> 1 even if reporting is ok" \
  "1" "$(audit_exit_code 'registry unreadable' true)"
assert_eq "worktree enumeration failed -> 1" \
  "1" "$(audit_exit_code 'cannot enumerate worktrees' true)"

# ── audit_exit_code: strict-mode contract, must not crash on missing args ──
assert_eq "no-arg call -> 1 (fail closed)" \
  "1" "$(audit_exit_code)"

# ── audit_status_line: human-readable line distinguishes findings from failure ─
assert_eq "ok line names the finding/warning counts, not pass/fail language" \
  "AUDIT OK: ran to completion — 2 finding(s), 0 warning(s)" \
  "$(audit_status_line 2 0 '' true)"
assert_eq "ok line with warnings too" \
  "AUDIT OK: ran to completion — 0 finding(s), 1 warning(s)" \
  "$(audit_status_line 0 1 '' true)"
assert_eq "reporting-channel failure line is explicit, not a finding count" \
  "AUDIT FAILED: findings could not be durably reported" \
  "$(audit_status_line 2 0 '' false)"
assert_eq "structural failure line carries the reason" \
  "AUDIT FAILED: registry unreadable" \
  "$(audit_status_line 0 0 'registry unreadable' true)"
assert_eq "structural failure wins over reporting status in the message" \
  "AUDIT FAILED: registry unreadable" \
  "$(audit_status_line 0 0 'registry unreadable' false)"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
