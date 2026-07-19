#!/usr/bin/env bash
# Structural contract regression for grimnir#86. This checks durable concepts,
# not prose style; producer/consumer implementation tests live in the owning repos.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACT="$REPO_ROOT/docs/learning-task-contract.md"
ADR="$REPO_ROOT/docs/adr-006-learning-improvement-scope.md"
OBS="$REPO_ROOT/docs/observability-and-improvement.md"
README="$REPO_ROOT/README.md"
SCHEMA="$REPO_ROOT/docs/learning-task-contract-v1.schema.json"

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
assert_contains "$CONTRACT" "six immutable record kinds" 'experiment-product-rating'
assert_contains "$CONTRACT" "late quality does not mutate outcomes" '`product_quality` scalar'
assert_contains "$CONTRACT" "late experiment rating does not mutate observation" 'experiment-observation.*MUST NOT acquire.*product_outcome'
assert_contains "$CONTRACT" "multiple review records are valid" 'Multiple receipts or ratings MAY target one binding'
assert_contains "$CONTRACT" "review disagreements fail closed" 'is `conflicted` and cannot support'
assert_contains "$CONTRACT" "full source tuple includes principal" 'component.*,.*system.*,.*id.*,.*created_at.*,.*accepted_at.*source `principal`'
assert_contains "$CONTRACT" "source and transport principals are separate" 'transport caller are separate identities'
assert_contains "$CONTRACT" "raw canonicalization is exact" 'trim-utf8-sha256-v1.*String\.trim'
assert_contains "$CONTRACT" "multi-turn exposure is per user turn" 'per user turn'
assert_contains "$CONTRACT" "three prompt stages are separate" 'runtime_chat_template_render'
assert_contains "$CONTRACT" "origin and effective configs are split" 'effective_gateway_config'
assert_contains "$CONTRACT" "llama-swap serving is named" '"llama-swap"'
assert_contains "$CONTRACT" "serving digests are reproducible" 'JCS RFC 8785.*UTF-8.*SHA-256'
assert_contains "$CONTRACT" "computed fixture hashes are required" 'Fixtures calculate their raw and prompt hashes'
assert_contains "$CONTRACT" "commit hash width is explicit" '40–64 characters'
assert_contains "$CONTRACT" "correction binding is explicit" 'correction reference MUST name a correction artifact'
assert_contains "$CONTRACT" "review pair is atomic" 'Reviewer identity and review time are known together'
assert_contains "$CONTRACT" "Hugin request stamp has full identity" 'full Hugin-owned source tuple'
assert_contains "$CONTRACT" "gateway independently authenticates caller" 'authenticates the actual caller independently'
assert_contains "$CONTRACT" "gateway echo is exact" 'echo is byte-for-byte equal'
assert_contains "$CONTRACT" "transport retries reuse identity" 'Transient request transport retry.*all reused'
assert_contains "$CONTRACT" "delivery retry cannot run model" 'never buys another model run'
assert_contains "$CONTRACT" "direct origin cannot invent Hugin stamp" 'Direct gateway records.*not-applicable'
assert_contains "$CONTRACT" "transport state includes non-M5 attempts" '`not-m5`'
assert_contains "$CONTRACT" "transport state includes M5 pre-admission failures" '`m5-not-admitted`'
assert_contains "$CONTRACT" "transport state includes admitted M5 attempts" '`m5-admitted`'
assert_contains "$CONTRACT" "transport state includes direct gateway attempts" '`direct-gateway`'
assert_contains "$CONTRACT" "macro route names target and service" 'explicit `target` and `service`'
assert_contains "$CONTRACT" "pre-admission keeps request stamp but lacks echo" 'Hugin request stamp is known; echo is absent'
assert_contains "$CONTRACT" "request-side contract negotiation is explicit" '`contract_request`'
assert_contains "$CONTRACT" "delivery attempt counters are producer local" '`record_delivery_attempt` is producer-owned'
assert_contains "$CONTRACT" "outcome and failure pairs are closed" 'Outcome/failure pairs are closed'
assert_contains "$CONTRACT" "admissible evidence has exact routing effect" 'Admissible evidence uses routing effect'
assert_contains "$CONTRACT" "exposure projections are split" 'two mutually exclusive projections'
assert_contains "$CONTRACT" "negative coverage has exact lanes" 'chat.*,.*mcp-ask.*,.*delegate.*,.*delegate-disagreement.*,.*delegate-shadow.*,.*code-loop'
assert_contains "$CONTRACT" "exact hash is not contamination proof" 'cannot detect Unicode-normalized'
assert_contains "$CONTRACT" "raw loopback invalidates complete holdout coverage" 'Raw loopback traffic sent'
assert_contains "$CONTRACT" "coverage restarts mint epochs" 'restart.*mints a new `coverage_epoch_id`'
assert_contains "$CONTRACT" "candidate starvation is measured" 'candidate-starvation rate'
assert_contains "$CONTRACT" "admission requires independent calibrated pass" 'verifier is independent'
assert_contains "$CONTRACT" "advisory judge stays shadow" 'advisory judge is always `none-shadow`'
assert_contains "$CONTRACT" "policy unavailable fails closed" 'policy-unavailable.*allows no use.*never evaluation-eligible'
assert_contains "$CONTRACT" "governance subjects are exact and typed" 'one exact typed policy'
assert_contains "$CONTRACT" "no-expiry policy remains usable" 'not-applicable.*explicit owner policy with no expiry'
assert_contains "$CONTRACT" "unresolved expiry fails closed" 'requires the whole governance projection'
assert_contains "$CONTRACT" "governance eligibility alone is not candidate eligibility" 'means governance eligibility at emission time only'
assert_contains "$CONTRACT" "selection uses an explicit decision clock" 'Candidate selection re-evaluates expiry against an explicit'
assert_contains "$CONTRACT" "direct owner lookup has SLO" '99% within 250 ms'
assert_contains "$CONTRACT" "erasure covers all stores" 'code-loop store'
assert_contains "$CONTRACT" "erasure covers external artifact stores" 'for every referenced Mimir'
assert_contains "$CONTRACT" "external artifact receipts have unique inventory identities" 'unique opaque `inventory_entry_id`'
assert_contains "$CONTRACT" "pending erasure is not success" '`pending` is deliberately invalid'
assert_contains "$CONTRACT" "backup expiry is confirmed" 'Backup expiry uses'
assert_contains "$CONTRACT" "backup completion clock order is exact" 'requested_at.*deadline.*verified_at.*effective_at'
assert_contains "$CONTRACT" "counter retention is aggregate only" 'survives in the aggregate'
assert_contains "$CONTRACT" "producer-scoped tombstone uniqueness" 'scoped by producer plus superseded id'
assert_contains "$CONTRACT" "conflict keys include reviews" 'Quality receipt.*quality_receipt\.receipt_id'
assert_contains "$CONTRACT" "extensions are producer namespaced" 'extensions\.<producer\.component>'
assert_contains "$CONTRACT" "major-version evolution rules" 'requires `v2` and a parallel migration'
assert_contains "$CONTRACT" "rollout has dual-read phase" 'Phase.*Hugin write.*Gateway read'
assert_contains "$CONTRACT" "rollout has credible measurable duration" '100 real eligible attempts'
assert_contains "$CONTRACT" "legacy retirement has gate" '30 complete green days.*no legacy traffic for 14 days'
assert_contains "$CONTRACT" "capability advertisement names features" 'hugin-request-stamp-v1.*gateway-echo-v1'
assert_contains "$CONTRACT" "cross-repo fixture tests" 'canonical schema ships with dependency-free positive and adversarial fixtures'
assert_contains "$CONTRACT" "standard validator is optional" 'optional `jsonschema` Draft 2020-12 check'
assert_contains "$CONTRACT" "disjoint monthly windows" 'disjoint complete UTC calendar months'
assert_contains "$CONTRACT" "continuous capture target" 'at least 95%.*within 24 hours'
assert_contains "$CONTRACT" "direct M5 capture target" 'Continuous direct-M5 capture'
assert_contains "$CONTRACT" "continuous evaluation target" 'at least ten unique eligible candidates'
assert_contains "$CONTRACT" "Hugin denominator resists gaming" 'Failed, timed-out, cancelled-after-start, private, no-op'
assert_contains "$CONTRACT" "direct denominator is explicit" 'eligible direct-owner request'
assert_contains "$CONTRACT" "omission failures cannot become exclusions" 'transport-auth-failed'
assert_contains "$CONTRACT" "component reviews remain pending" 'Hugin owner — pending.*gille-inference.*pending'
assert_contains "$README" "README names all six v1 record kinds" 'six v1 record kinds'
assert_contains "$SCHEMA" "echoed Hugin request remains Hugin-owned" 'echoed_request.*hugin, copied byte-for-byte by gille-inference'
assert_contains "$SCHEMA" "gateway admission and authentication remain gateway-owned" 'gateway_request_id.*admission_id.*gille-inference'
assert_contains "$ADR" "model-weight training excluded from v1" 'Model-weight training is not in v1'
assert_contains "$ADR" "ADR acceptance is review gated" 'Status:.*proposed.*review evidence.*recorded'
assert_contains "$ADR" "future privacy gate" 'Privacy and lifecycle'
assert_contains "$ADR" "future dataset split gate" 'Splits and leakage'
assert_contains "$ADR" "future rollback gate" 'Deployment and rollback'
assert_contains "$OBS" "three-plane architecture" 'three evidence planes'
assert_contains "$OBS" "manual promotion boundary" 'Promotion is reviewed and reversible'
assert_contains "$OBS" "first-receipt CAS gap remains" 'current\?\.updated_at.*undefined.*unconditional Munin writes'
assert_contains "$OBS" "current unstamped transport gap is explicit" 'currently sends one unstamped request'
assert_contains "$OBS" "immutable late reviews are roadmap facts" 'Late reviews append; they do not patch observations'

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
  exit 0
fi

echo "$FAIL of $((PASS+FAIL)) assertion(s) FAILED."
exit 1
