#!/usr/bin/env bash
# tests/scripts/test-failure-recovery-doc.sh
#
# Regression test for issue #46: docs/failure-recovery.md must exist and
# define the minimal failure-recovery convention referenced by
# the public failure-recovery contract — every autonomous mutation leaves an
# audit record plus exactly one explicit reversal recipe.
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

# The public reversal recipe kinds.
assert_contains "documents a git-revert reversal recipe" "git revert"
assert_contains "documents a pre-state snapshot reversal recipe" "pre-state snapshot|snapshot"
assert_contains "documents a compensating-action reversal recipe" "compensating.action"
assert_contains "documents an explicit irreversible flag" "irreversible"

# Must tie every mutation to a deployment-selected audit sink without making
# an optional repository a hidden dependency.
assert_contains "requires an audit record per mutation" "audit record"
assert_contains "keeps Verdandi optional" "verdandi.*optional|optional.*verdandi"

# Must explain central deployment recovery behavior.
assert_contains "covers partial deployment state" "rsync is not transactional"
assert_contains "invalidates acceptance before mutation" "removes the acceptance marker"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
  exit 0
else
  echo "$FAIL of $((PASS+FAIL)) assertion(s) FAILED."
  exit 1
fi
