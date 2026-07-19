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

assert_contains "$CONTRACT" "versioned contract id" 'grimnir\.learning-task/v1'
assert_contains "$CONTRACT" "Hugin field ownership" 'task\.instance_id.*Hugin'
assert_contains "$CONTRACT" "gille-inference field ownership" 'exposure.*gille-inference|gille-inference.*exposure'
assert_contains "$CONTRACT" "raw task and rendered prompt are distinct" 'raw.*fingerprint.*rendered|rendered.*distinct.*raw'
assert_contains "$CONTRACT" "task taxonomy is versioned" 'taxonomy_version'
assert_contains "$CONTRACT" "model artifact identity is bound" 'artifact_digest'
assert_contains "$CONTRACT" "model config epoch is bound" 'config_epoch'
assert_contains "$CONTRACT" "prompt/harness/tool/sampling versions are bound" 'prompt_version.*harness_version|sampling_version'
assert_contains "$CONTRACT" "separate outcome planes" 'outcomes\.execution.*Hugin|outcomes\.product_quality'
assert_contains "$CONTRACT" "correction lineage" 'lineage\.correction_ref'
assert_contains "$CONTRACT" "successor lineage" 'lineage\.successor_task_ids'
assert_contains "$CONTRACT" "retention and erasure governance" 'retention.*erasure|erasure.*retention'
assert_contains "$CONTRACT" "cross-repo fixture tests" 'frozen, synthetic, non-sensitive v1 fixture'
assert_contains "$CONTRACT" "major-version evolution rules" 'requires .v2. and a parallel migration period'
assert_contains "$CONTRACT" "implemented stage" '\*\*Implemented\*\*'
assert_contains "$CONTRACT" "shadow stage" '\*\*Shadow\*\*'
assert_contains "$CONTRACT" "manual stage" '\*\*Manual\*\*'
assert_contains "$CONTRACT" "future stage" '\*\*Future\*\*'
assert_contains "$CONTRACT" "continuous capture target" 'at least 95%.*within 24 hours'
assert_contains "$CONTRACT" "continuous evaluation target" 'every 30-day window.*at least ten eligible tasks'
assert_contains "$ADR" "model-weight training excluded from v1" 'Model-weight training is not in v1'
assert_contains "$ADR" "future privacy gate" 'Privacy and lifecycle'
assert_contains "$ADR" "future dataset split gate" 'Splits and leakage'
assert_contains "$ADR" "future rollback gate" 'Deployment and rollback'
assert_contains "$OBS" "three-plane architecture" 'three evidence planes'
assert_contains "$OBS" "manual promotion boundary" 'Promotion is reviewed and reversible'

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
  exit 0
fi

echo "$FAIL of $((PASS+FAIL)) assertion(s) FAILED."
exit 1
