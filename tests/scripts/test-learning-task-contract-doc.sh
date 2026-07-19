#!/usr/bin/env bash
# Structural contract regression for grimnir#86. This checks durable concepts,
# not prose style; producer/consumer implementation tests live in the owning repos.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACT="$REPO_ROOT/docs/learning-task-contract.md"
ADR="$REPO_ROOT/docs/adr-006-learning-improvement-scope.md"
OBS="$REPO_ROOT/docs/observability-and-improvement.md"

PASS=0
FAIL=0

assert_contains() {
  local file="$1" desc="$2" pattern="$3"
  if [[ -f "$file" ]] && grep -qiE "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — pattern not found in ${file#"$REPO_ROOT"/}: $pattern"
    FAIL=$((FAIL+1))
  fi
}

echo "Checking LearningTaskContract documentation ..."

node "$REPO_ROOT/tests/scripts/validate-learning-task-contract.mjs"

assert_contains "$CONTRACT" "versioned contract id" 'grimnir\.learning-task/v1'
assert_contains "$CONTRACT" "Hugin field ownership" 'Hugin-origin identity.*Hugin'
assert_contains "$CONTRACT" "gille-inference field ownership" 'exposure.*gille-inference|gille-inference.*exposure'
assert_contains "$CONTRACT" "raw, Hugin, and gateway prompts are distinct facts" 'Raw, Hugin-rendered, and gateway-rendered'
assert_contains "$CONTRACT" "macro and micro routing are distinct facts" 'Macro and micro routing have separate'
assert_contains "$CONTRACT" "task taxonomy is versioned" 'taxonomy_version'
assert_contains "$CONTRACT" "model artifact identity is bound" 'artifact_digest'
assert_contains "$CONTRACT" "model config epoch is bound" 'config_epoch'
assert_contains "$CONTRACT" "prompt/harness/tool/sampling versions are bound" 'prompt_version.*harness_version|sampling_version'
assert_contains "$CONTRACT" "separate outcome planes" 'outcomes\.execution.*Hugin|outcomes\.product_quality'
assert_contains "$CONTRACT" "correction lineage" 'lineage\.correction_ref'
assert_contains "$CONTRACT" "successor lineage" 'lineage\.successor_task_ids'
assert_contains "$CONTRACT" "retention and erasure governance" 'retention.*erasure|erasure.*retention'
assert_contains "$CONTRACT" "cross-repo fixture tests" 'canonical schema ships with dependency-free positive and adversarial fixtures'
assert_contains "$CONTRACT" "major-version evolution rules" 'requires .v2. and a parallel'
assert_contains "$CONTRACT" "direct gateway origin is governed by gille-inference" 'gille-inference.*enforces.*direct gateway'
assert_contains "$CONTRACT" "qualified unknown shape" 'unknown_reason'
assert_contains "$CONTRACT" "reduced content-removal tombstone" 'content-removed-tombstone.*deliberately smaller'
assert_contains "$CONTRACT" "active record and tombstone cannot coexist" 'NOT coexist in a conforming dataset'
assert_contains "$CONTRACT" "tombstone preserves denominators only as aggregates" 'preserved monthly denominator survives in the aggregate'
assert_contains "$CONTRACT" "tombstone excludes serving classifications and locators" 'model, prompt, route, artifact, classification, locator'
assert_contains "$CONTRACT" "capability identifiers and policy epoch have an owner" 'capability\.evidence_id.*policy_epoch.*gille-inference'
assert_contains "$CONTRACT" "all experiment leaves have an owner" 'experiment\.experiment_id.*configuration_fingerprint.*product_outcome.*Hugin'
assert_contains "$CONTRACT" "exposure coverage leaves have an owner" 'exposure\.event_key.*coverage\.complete.*coverage\.lanes.*gille-inference'
assert_contains "$CONTRACT" "extensions are producer namespaced" 'extensions\.<producer\.component>'
assert_contains "$CONTRACT" "gateway admission is an anti-gaming failure" 'gateway-not-admitted.*producer-error'
assert_contains "$CONTRACT" "other omission failures cannot become exclusions" 'consumer-error.*schema-rejected.*join-mismatch.*late-over-24h'
assert_contains "$CONTRACT" "disjoint monthly windows" 'disjoint complete UTC calendar months'
assert_contains "$CONTRACT" "component owner review remains pending" 'Hugin owner — pending.*gille-inference.*pending'
assert_contains "$CONTRACT" "implemented stage" '\*\*Implemented\*\*'
assert_contains "$CONTRACT" "shadow stage" '\*\*Shadow\*\*'
assert_contains "$CONTRACT" "manual stage" '\*\*Manual\*\*'
assert_contains "$CONTRACT" "future stage" '\*\*Future\*\*'
assert_contains "$CONTRACT" "continuous capture target" 'at least 95%.*within 24 hours'
assert_contains "$CONTRACT" "continuous evaluation target" 'at least ten unique eligible candidates'
assert_contains "$ADR" "model-weight training excluded from v1" 'Model-weight training is not in v1'
assert_contains "$ADR" "ADR acceptance is review gated" 'Status:.*proposed.*review evidence.*recorded'
assert_contains "$ADR" "future privacy gate" 'Privacy and lifecycle'
assert_contains "$ADR" "future dataset split gate" 'Splits and leakage'
assert_contains "$ADR" "future rollback gate" 'Deployment and rollback'
assert_contains "$OBS" "three-plane architecture" 'three evidence planes'
assert_contains "$OBS" "manual promotion boundary" 'Promotion is reviewed and reversible'
assert_contains "$OBS" "first-receipt CAS gap remains" 'current\?\.updated_at.*undefined.*unconditional Munin writes'

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
  exit 0
fi

echo "$FAIL of $((PASS+FAIL)) assertion(s) FAILED."
exit 1
