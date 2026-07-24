#!/usr/bin/env bash
# Regression test for the maintenance-policy v1 contract adopted by grimnir#134.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$REPO_ROOT/docs/maintenance-policy-contract.md"
AGENTS="$REPO_ROOT/AGENTS.md"
# The document index moved out of AGENTS.md into docs/index.md (progressive
# disclosure). Discoverability assertions target the index; test-doc-index.sh
# separately asserts that AGENTS.md still reaches the index in one hop.
INDEX="$REPO_ROOT/docs/index.md"
AUTHORITY="$REPO_ROOT/docs/authority.md"
PASS=0
FAIL=0

assert_contains() {
  local file="$1" desc="$2" pattern="$3"
  if [[ -f "$file" ]] && grep -qiE "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — pattern not found: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo "Running maintenance-policy contract documentation assertions..."
assert_contains "$DOC" "contract doc exists with a title" '^# Maintenance-policy contract v1'
assert_contains "$DOC" "records accepted status" '^> \*\*Status:\*\* accepted v1\.$'
assert_contains "$DOC" "states intent-only boundary" 'This document expresses intent only'
assert_contains "$DOC" "states the schema neither proves eligibility nor authorizes mutation" 'proves eligibility nor authorizes mutation'
assert_contains "$DOC" "requires the executor to hold fresh Brokkr observations" 'MUST additionally hold fresh Brokkr observations'
assert_contains "$DOC" "requires the execution controller.s own safety gates" 'own safety gates \(drain/verify hooks'
assert_contains "$DOC" "excludes private locators by example" 'a private locator \(hostname, IP, path, Wi-Fi identity\)'
assert_contains "$DOC" "excludes configuration contents" 'configuration contents'
assert_contains "$DOC" "distinguishes intent, observation, and evidence" 'Intent vs\. observation vs\. evidence'
assert_contains "$DOC" "defines the deterministic digest algorithm name" 'maintenance-policy-digest-jcs-v1'
assert_contains "$DOC" "specifies SHA-256 over canonical JSON" 'SHA-256 over those bytes'
assert_contains "$DOC" "specifies UTF-16 code unit key ordering" 'UTF-16 code unit order'
assert_contains "$DOC" "specifies array order is preserved, not sorted" 'preserving element.*order|array order is semantic'
assert_contains "$DOC" "requires digest recomputation across key reordering" 'deep-reordering every fixture policy.s keys'
assert_contains "$DOC" "defines the nonexistent local-time case" 'Nonexistent \(spring-forward gap\)'
assert_contains "$DOC" "defines the ambiguous local-time case" 'Ambiguous \(fall-back repeat\)'
assert_contains "$DOC" "cites a verified 2026 spring-forward transition" '2026-03-29'
assert_contains "$DOC" "cites a verified 2026 fall-back transition" '2026-10-25'
assert_contains "$DOC" "requires an unresolvable timezone to fail closed" 'unresolvable timezone \*\*MUST\*\* fail closed'
assert_contains "$DOC" "defines missed-window/overdue/maximum-deferral precedence" 'Missed-window, overdue, and maximum-deferral decision rules'
assert_contains "$DOC" "states maximum deferral is an absolute ceiling" 'absolute ceiling'
assert_contains "$DOC" "keeps update classes and sources closed" 'closed for safety'
assert_contains "$DOC" "keeps additionalProperties closed everywhere" 'additionalProperties: false.*every object level|closed record'
assert_contains "$DOC" "confirms node-substrate compatibility without modifying it" 'byte-for-byte untouched'
assert_contains "$DOC" "confirms node-substrate tests still pass" 'passes unmodified \(10/10 existing hermetic fixture scenarios\)'
assert_contains "$DOC" "declares out-of-scope execution" 'Out of scope for v1'
assert_contains "$AGENTS" "instruction file reaches the document index in one hop" 'docs/index\.md'
assert_contains "$INDEX" "index references the maintenance-policy contract doc" 'maintenance-policy-contract\.md'
assert_contains "$INDEX" "index references the maintenance-policy schema" 'maintenance-policy-v1\.schema\.json'
assert_contains "$AUTHORITY" "maps maintenance-policy authority" 'maintenance.policy'

if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
else
  echo "$FAIL of $((PASS + FAIL)) assertion(s) failed."
  exit 1
fi
