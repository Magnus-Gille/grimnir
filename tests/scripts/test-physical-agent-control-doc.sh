#!/usr/bin/env bash
# Preserve the authority and safety boundary adopted by grimnir#179.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACT="$REPO_ROOT/docs/physical-agent-control-contract.md"
SCHEMA="$REPO_ROOT/docs/physical-agent-control-v1.schema.json"
PROFILE_SCHEMA="$REPO_ROOT/docs/physical-agent-control-profile-v1.schema.json"
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

echo "Checking physical agent control documentation ..."

assert_contains "$CONTRACT" "versioned contract id" 'grimnir\.physical-agent-control/v1'
assert_contains "$CONTRACT" "reuses rather than adds orchestration" 'local physical console.*, not a new agent orchestrator'
assert_contains "$CONTRACT" "keeps Hugin as consequential-task gate" 'Hugin remains the durable, policy-gated consequential-task plane'
assert_contains "$CONTRACT" "does not register a service" "There is no \`services\\.json\` entry"
assert_contains "$CONTRACT" "binds owner-reviewed profiles" 'owner-reviewed local profile'
assert_contains "$CONTRACT" "defines canonical profile digest bytes" 'profile-jcs-sha256-v1.*lowercase SHA-256'
assert_contains "$CONTRACT" "does not trust self-asserted profile digests" 'digest equality is not sufficient'
assert_contains "$CONTRACT" "bounds intent expiry" 'no more than five'
assert_contains "$CONTRACT" "uses a trusted evaluation clock" 'trusted current'
assert_contains "$CONTRACT" "expiry precedes replay lookup" 'Expired input is rejected before any replay lookup'
assert_contains "$CONTRACT" "requires monotonic sequence" "strictly increasing \`sequence\`"
assert_contains "$CONTRACT" "does not spool device events" 'never durably spooled'
assert_contains "$CONTRACT" "replay returns prior disposition" 'returns the prior disposition without another'
assert_contains "$CONTRACT" "conflicting replay is rejected" 'conflicting reuse is rejected'
assert_contains "$CONTRACT" "derived state is display-only" 'projection is display-only'
assert_contains "$CONTRACT" "idle is not completion" 'Idle never means done'
assert_contains "$CONTRACT" "done binds a native report" 'structured-report reference and digest'
assert_contains "$CONTRACT" "hardware never approves" 'Hardware never answers an'
assert_contains "$CONTRACT" "raw prompts are excluded" 'raw prompt or transcript text'
assert_contains "$CONTRACT" "authority increases are excluded" 'v1 may increase authority'
assert_contains "$CONTRACT" "TX-6 absolute range is exact" "absolute \`0\\.\\.127\`"
assert_contains "$CONTRACT" "TX-6 relative range is exact" "^\`-64\\.\\.63\` for encoder CC 31"
assert_contains "$CONTRACT" "TX-6 button range is exact" "button values \`0\\|127\`"
assert_contains "$CONTRACT" "continuous input cannot submit work" 'cannot submit a task, interrupt a turn'
assert_contains "$CONTRACT" "ADR-008 disarm is not overloaded" "no \`disarm\` action in v1"
assert_contains "$CONTRACT" "implementation visibility remains an owner choice" 'owner chooses its name and'
assert_contains "$SCHEMA" "schema permits no authority increase" '"authority_delta": \{ "enum": \["none", "reduce"\] \}'
assert_contains "$PROFILE_SCHEMA" "profile schema fixes canonical digest algorithm" '"digest_algorithm": \{ "const": "profile-jcs-sha256-v1" \}'
assert_contains "$PROFILE_SCHEMA" "profile schema stays closed" '"additionalProperties": false'
assert_contains "$AUTHORITY" "authority map names the shared seam" 'Physical control intent/state envelope'
assert_contains "$AUTHORITY" "authority map keeps profiles adapter-owned" 'Physical device mapping, local profile'
assert_contains "$AUTHORITY" "authority map keeps consequential work in Hugin" 'Physical-control consequential task admission'

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
  exit 0
fi

echo "$FAIL of $((PASS + FAIL)) assertion(s) FAILED."
exit 1
