#!/usr/bin/env bash
# tests/scripts/test-failure-recovery-doc.sh
#
# Regression test for issue #46: docs/failure-recovery.md must exist and
# define the minimal failure-recovery convention referenced by
# docs/vision.md's "Failure recovery" open question — every autonomous
# mutation leaves a reversal recipe (git revert ref, pre-state snapshot, or
# an explicit "irreversible" flag) plus a Verdandi audit event.
#
# This test asserts structural presence of the required concepts, not prose
# wording — it's a contract check, not a style check.
#
# Usage:
#   bash tests/scripts/test-failure-recovery-doc.sh
#
# Exit codes: 0 = all assertions passed, 1 = at least one assertion failed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$REPO_ROOT/docs/failure-recovery.md"

PASS=0
FAIL=0

assert_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — '$path' not found"
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  local desc="$1" pattern="$2"
  if [[ -f "$DOC" ]] && grep -qiE "$pattern" "$DOC"; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — pattern not found: $pattern"
    FAIL=$((FAIL+1))
  fi
}

echo "Running assertions against $DOC ..."

assert_exists "docs/failure-recovery.md exists" "$DOC"

# The three reversal recipe kinds named in issue #46.
assert_contains "documents a git-revert reversal recipe" "git revert"
assert_contains "documents a pre-state snapshot reversal recipe" "pre-state snapshot|snapshot"
assert_contains "documents an explicit irreversible flag" "irreversible"

# Must tie every mutation to a Verdandi audit event.
assert_contains "requires a Verdandi audit event per mutation" "verdandi"

# Must map the convention onto the three Phase-2 actors named in the issue.
assert_contains "covers auto dependency bumps" "dep(endency)?[ -]bump"
assert_contains "covers Hugin task-dispatched mutations" "hugin"
assert_contains "covers doc-fix mutations" "doc(umentation)? fix"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
  exit 0
else
  echo "$FAIL of $((PASS+FAIL)) assertion(s) FAILED."
  exit 1
fi
