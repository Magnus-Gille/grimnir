#!/usr/bin/env bash
# Regression test for the authority boundary adopted by grimnir#101.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ADR="$REPO_ROOT/docs/adr-007-node-substrate-contract.md"
AUTHORITY="$REPO_ROOT/docs/authority.md"
ARCHITECTURE="$REPO_ROOT/docs/architecture.md"
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

echo "Running Node/Substrate Contract documentation assertions..."
assert_contains "$ADR" "ADR exists" '^# ADR-007:'
assert_contains "$ADR" "assigns Grimnir desired-state authority" 'Grimnir.*desired'
assert_contains "$ADR" "assigns Brokkr observed-state authority" 'Brokkr.*observed'
assert_contains "$ADR" "keeps component hooks component-owned" 'Owning component.*hook|component owner.*hook'
assert_contains "$ADR" "keeps Heimdall out of topology authority" 'Heimdall.*Become topology authority'
assert_contains "$ADR" "has a state transition diagram" 'stateDiagram-v2'
assert_contains "$ADR" "defines stale and unknown semantics" 'stale.*unknown|unknown.*stale'
assert_contains "$ADR" "defines physical relocation" 'physical node relocation'
assert_contains "$ADR" "defines workload relocation" 'workload relocation'
assert_contains "$ADR" "assigns substrate rollback" 'Brokkr owns rollback'
assert_contains "$ADR" "assigns workload rollback" 'workload owner owns rollback'
assert_contains "$ADR" "defines unavailable-owner failure behavior" 'Availability failure behavior'
assert_contains "$ADR" "defines unavailable Brokkr" 'Brokkr is unavailable'
assert_contains "$ADR" "blocks an unavailable workload hook" 'workload hook is unavailable'
assert_contains "$AUTHORITY" "maps desired-topology authority" 'Desired node topology'
assert_contains "$AUTHORITY" "maps observed-capability authority" 'Observed node capability'
assert_contains "$ARCHITECTURE" "links the architecture to ADR-007" 'Node/substrate reconciliation boundary.*ADR-007'

if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
else
  echo "$FAIL of $((PASS + FAIL)) assertion(s) failed."
  exit 1
fi
