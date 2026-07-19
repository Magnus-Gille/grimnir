#!/usr/bin/env bash
# Structural contract regression for grimnir#86. This checks durable concepts,
# not prose style; producer/consumer implementation tests live in the owning repos.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACT="$REPO_ROOT/docs/learning-task-contract.md"
ARCH="$REPO_ROOT/docs/architecture.md"
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
assert_contains "$CONTRACT" "seven immutable record kinds" '`pipeline-accounting`.*`pipeline_accounting`'
assert_contains "$CONTRACT" "late quality does not mutate outcomes" '`product_quality` scalar'
assert_contains "$CONTRACT" "late experiment rating does not mutate observation" 'experiment-observation.*MUST NOT acquire.*product_outcome'
assert_contains "$CONTRACT" "multiple review records are valid" 'Multiple receipts or ratings MAY target one binding'
assert_contains "$CONTRACT" "review disagreements fail closed" 'is `conflicted` and cannot support'
assert_contains "$CONTRACT" "full source tuple includes principal" 'source transport `principal`'
assert_contains "$CONTRACT" "content owner is distinct from transport identity" 'separate `content_owner`'
assert_contains "$CONTRACT" "source and transport principals are separate" 'three separate identities'
assert_contains "$CONTRACT" "raw canonicalization is exact" 'trim-utf8-sha256-v1.*String\.trim'
assert_contains "$CONTRACT" "raw input stage is exact" 'prompt \*\*before\*\* injected context'
assert_contains "$CONTRACT" "multi-turn exposure is per user turn" 'per user turn'
assert_contains "$CONTRACT" "three prompt stages are separate" 'runtime_chat_template_render'
assert_contains "$CONTRACT" "origin and effective configs are split" 'effective_gateway_config'
assert_contains "$CONTRACT" "serving fixtures are synthetic" 'fixture-model-v1'
assert_contains "$CONTRACT" "prompt stages bind exact bytes" 'exact ordered UTF-8 text, byte length, byte SHA-256'
assert_contains "$CONTRACT" "serving digests are reproducible" 'Every reproducibility claim binds an immutable'
assert_contains "$CONTRACT" "typed source documents are executable fixtures" '`source-documents\.json` fixture contains typed source documents'
assert_contains "$CONTRACT" "JCS vectors cover Unicode and numbers" 'non-ASCII, numeric-boundary, exponent, and negative-zero vectors'
assert_contains "$CONTRACT" "commit hash width is explicit" '40–64 characters'
assert_contains "$CONTRACT" "correction binding is explicit" 'correction reference MUST name a correction artifact'
assert_contains "$CONTRACT" "review pair is atomic" 'Reviewer identity and review time are known together'
assert_contains "$CONTRACT" "Hugin request stamp has full identity" 'full Hugin-owned source tuple'
assert_contains "$CONTRACT" "gateway independently authenticates caller" 'authenticates the actual caller independently'
assert_contains "$CONTRACT" "gateway echo is exact" 'echo is byte-for-byte equal'
assert_contains "$CONTRACT" "transport retries reuse identity" 'identical stamp/key/attempt/request replayed'
assert_contains "$CONTRACT" "delivery retry cannot run model" 'never buys another model run'
assert_contains "$CONTRACT" "direct origin cannot invent Hugin stamp" 'Direct gateway records.*not-applicable'
assert_contains "$CONTRACT" "transport state includes non-M5 attempts" '`not-m5`'
assert_contains "$CONTRACT" "transport state includes M5 pre-admission failures" '`m5-not-admitted`'
assert_contains "$CONTRACT" "transport state includes admitted M5 attempts" '`m5-admitted`'
assert_contains "$CONTRACT" "transport state includes direct gateway attempts" '`direct-gateway`'
assert_contains "$CONTRACT" "macro route names target and service" 'explicit `target` and `service`'
assert_contains "$CONTRACT" "pre-admission keeps request stamp but lacks echo" 'Hugin request stamp is known; echo is absent'
assert_contains "$CONTRACT" "request-side contract negotiation is explicit" '`contract_request`'
assert_contains "$CONTRACT" "authenticated preflight endpoint is explicit" 'GET /v1/capabilities/learning-task'
assert_contains "$CONTRACT" "preflight freshness is bounded" 'at most 15 minutes'
assert_contains "$CONTRACT" "stamp follows attempt start" 'attempt start.*stamp'
assert_contains "$CONTRACT" "stamp cannot be post-hoc" 'non-admitted attempt.*bounded above'
assert_contains "$CONTRACT" "schema revision is pinned" 'pinned schema revision 1'
assert_contains "$CONTRACT" "retry accounting is separate and immutable" 'append-only `pipeline-accounting` events'
assert_contains "$CONTRACT" "outcome and failure pairs are closed" 'Outcome/failure pairs are closed'
assert_contains "$CONTRACT" "admissible evidence has exact routing effect" 'Admissible evidence uses routing effect'
assert_contains "$CONTRACT" "exposure projections are split" 'two mutually exclusive projections'
assert_contains "$CONTRACT" "observed exposure carries full raw fingerprint" 'authoritative raw fingerprint equal'
assert_contains "$CONTRACT" "negative coverage has exact lanes" 'chat.*,.*mcp-ask.*,.*delegate.*,.*delegate-disagreement.*,.*delegate-shadow.*,.*code-loop'
assert_contains "$CONTRACT" "exact hash is not contamination proof" 'cannot detect Unicode-normalized'
assert_contains "$CONTRACT" "raw loopback invalidates complete holdout coverage" 'Raw loopback traffic sent'
assert_contains "$CONTRACT" "coverage restarts mint epochs" 'restart.*mints a new `coverage_epoch_id`'
assert_contains "$CONTRACT" "candidate starvation is measured" 'candidate-starvation rate'
assert_contains "$CONTRACT" "admission requires independent calibrated pass" 'verifier is independent'
assert_contains "$CONTRACT" "advisory judge stays shadow" 'advisory judge is always `none-shadow`'
assert_contains "$CONTRACT" "policy unavailable fails closed" 'policy-unavailable.*allows no use.*never evaluation-eligible'
assert_contains "$CONTRACT" "governance subjects are exact and typed" 'one exact typed policy'
assert_contains "$CONTRACT" "owner authorization is explicit" 'one owner attestation per distinct policy'
assert_contains "$CONTRACT" "owner evidence is verified out of band" 'trusted validation'
assert_contains "$CONTRACT" "owner approval binds exact policy" 'exact sorted policy subset plus manifest identity'
assert_contains "$CONTRACT" "body digest is not authentication" 'integrity, not authentication'
assert_contains "$CONTRACT" "manifest digest includes attestations" 'complete owner-attestation set'
assert_contains "$CONTRACT" "no-expiry policy remains usable" 'not-applicable.*explicit owner policy with no expiry'
assert_contains "$CONTRACT" "unresolved expiry fails closed" 'requires the whole governance projection'
assert_contains "$CONTRACT" "governance eligibility alone is not candidate eligibility" 'means governance eligibility at emission time only'
assert_contains "$CONTRACT" "selection uses an explicit decision clock" 'Candidate selection re-evaluates expiry against an explicit'
assert_contains "$CONTRACT" "direct owner lookup has SLO" '99% within 250 ms'
assert_contains "$CONTRACT" "erasure covers all stores" 'code-loop store'
assert_contains "$CONTRACT" "erasure covers external artifact stores" 'for every referenced Mimir'
assert_contains "$CONTRACT" "external artifact receipts have unique inventory identities" 'unique opaque `inventory_entry_id`'
assert_contains "$CONTRACT" "pending erasure is not success" 'deliberately invalid success states'
assert_contains "$CONTRACT" "backup expiry is confirmed" 'Backup expiry uses'
assert_contains "$CONTRACT" "backup completion clock order is exact" 'requested_at.*deadline.*verified_at.*effective_at'
assert_contains "$CONTRACT" "counter retention is aggregate only" 'denominator survives only in the aggregate'
assert_contains "$CONTRACT" "occurrence-month erasure preserves denominator idempotently" 'original occurrence-month membership'
assert_contains "$CONTRACT" "cross-owner erasure uses issuer token" 'Hugin-issued token'
assert_contains "$CONTRACT" "denominator basis is trusted" 'authoritative basis proof'
assert_contains "$CONTRACT" "erasure tokens have issue clocks" 'valid issue clock no later than'
assert_contains "$CONTRACT" "erasure counter set is exact" 'exact required counter set is derived from `denominator_basis`'
assert_contains "$CONTRACT" "producer-scoped tombstone uniqueness" 'scoped by producer plus superseded id'
assert_contains "$CONTRACT" "conflict keys include reviews" 'Quality receipt identity.*quality_receipt\.native_receipt\.receipt_id'
assert_contains "$CONTRACT" "quality corrections group across ids" 'quality_receipt\.correction_group_key'
assert_contains "$CONTRACT" "gille inference cannot claim repository facts" 'MUST use a qualified unknown repository projection'
assert_contains "$CONTRACT" "corrections preserve owner kind and domain" 'same-kind fact domain'
assert_contains "$CONTRACT" "corrections select unique effective leaf" 'unsuperseded leaf'
assert_contains "$CONTRACT" "pipeline failures remain countable" 'failure remains countable when no valid learning record exists'
assert_contains "$CONTRACT" "accounting natural keys are explicit" 'Natural keys are stricter than random event ids'
assert_contains "$CONTRACT" "denominator month derives from occurrence clock" 'occurrence_month_utc.*derived from'
assert_contains "$CONTRACT" "aggregate close digest is verifiable" 'pipeline-event-set-jcs-v1'
assert_contains "$CONTRACT" "aggregate completeness needs ledger proof" 'partition/high-water proof'
assert_contains "$CONTRACT" "partition proof issuer owns counter" 'proof issuer must equal the counter-owning'
assert_contains "$CONTRACT" "certified zero-event periods are valid" 'legitimate zero-event month'
assert_contains "$CONTRACT" "unproven empty periods fail closed" 'unproven empty load'
assert_contains "$CONTRACT" "partial aggregate verification is deferred" 'partial-dataset-deferred'
assert_contains "$CONTRACT" "extensions are producer namespaced" 'extensions\.<producer\.component>'
assert_contains "$CONTRACT" "major-version evolution rules" 'requires `v2` and a parallel migration'
assert_contains "$CONTRACT" "rollout has dual-read phase" 'Phase.*Hugin write.*Gateway read'
assert_contains "$CONTRACT" "rollout has credible measurable duration" '100 real eligible attempts'
assert_contains "$CONTRACT" "legacy retirement has gate" '30 complete green days.*no legacy traffic for 14 days'
assert_contains "$CONTRACT" "capability advertisement names features" 'hugin-request-stamp-v1.*gateway-echo-v1'
assert_contains "$CONTRACT" "cross-repo fixture tests" 'canonical schema ships with dependency-free positive and adversarial fixtures'
assert_contains "$CONTRACT" "Draft validator stays authoritative" 'Draft 2020-12 remains the authoritative schema semantics'
assert_contains "$CONTRACT" "structural and semantic validators are both required" 'authoritative for structural JSON Schema semantics'
assert_contains "$CONTRACT" "impossible calendar dates fail semantics" 'dates such as February 30'
assert_contains "$CONTRACT" "unsupported schema keywords fail" 'rejects schema keywords it does not implement'
assert_contains "$CONTRACT" "unsupported schema shapes fail" 'rejects malformed shapes for every supported'
assert_contains "$CONTRACT" "disjoint monthly windows" 'disjoint complete UTC calendar months'
assert_contains "$CONTRACT" "continuous capture target" 'at least 95%.*within 24 hours'
assert_contains "$CONTRACT" "direct M5 capture target" 'Continuous direct-M5 capture'
assert_contains "$CONTRACT" "continuous evaluation target" 'at least ten unique eligible candidates'
assert_contains "$CONTRACT" "Hugin denominator resists gaming" 'Failed, timed-out, cancelled-after-start, private, no-op'
assert_contains "$CONTRACT" "direct denominator is explicit" 'eligible direct-owner request'
assert_contains "$CONTRACT" "omission failures cannot become exclusions" 'transport-auth-failed'
assert_contains "$CONTRACT" "evaluation admission binds full bundle" 'full joined evidence bundle'
assert_contains "$CONTRACT" "empty quality cohort is unrated" 'empty quality cohort is explicitly `unrated`'
assert_contains "$CONTRACT" "present quality cohort is admissible" 'independent and their summary must be non-conflicted'
assert_contains "$CONTRACT" "quality cohort cannot be cherry-picked" 'must contain every effective correction leaf'
assert_contains "$CONTRACT" "unrated quality is truthful" 'empty list truthfully means `unrated`'
assert_contains "$CONTRACT" "evaluation evidence is available by decision" 'loaded from the trusted dataset no later than the exact decision'
assert_contains "$CONTRACT" "evaluation uses correction leaves" 'effective same-natural-key correction leaf as of the decision'
assert_contains "$CONTRACT" "native quality hashes remain opaque" 'native task/result hashes remain'
assert_contains "$CONTRACT" "negative exposure binds Hugin attempt" 'trusted Hugin-issued attempt proof'
assert_contains "$CONTRACT" "synthetic exclusion requires evidence" 'trusted owner declaration made no later than occurrence'
assert_contains "$CONTRACT" "migration exclusion requires window" 'trusted, predeclared compatibility window'
assert_contains "$CONTRACT" "boundary issuer is accounting owner" 'proof issuer must equal the accounting event'
assert_contains "$CONTRACT" "native v1 receipt shape is honest" 'Native v1 does \*\*not\*\* contain attempt or rubric fields'
assert_contains "$CONTRACT" "quality correction support is future" 'future v2 adoption dependency'
assert_contains "$CONTRACT" "taxonomy changes coordinate revision" 'task-taxonomy enum requires a coordinated schema revision'
assert_contains "$CONTRACT" "gille rollout tickets are mapped" '#2 preflight.*gille-inference/issues/2'
assert_contains "$CONTRACT" "Hugin rollout tickets are mapped" '#240 requester.*hugin/issues/240'
assert_contains "$CONTRACT" "Hugin accounting owner ticket is mapped" '#241 Hugin-owned capture/join/evaluation accounting.*hugin/issues/241'
assert_contains "$ARCH" "accounting trust architecture is target state" 'LearningTaskContract target requires both components'
assert_contains "$CONTRACT" "component reviews remain pending" 'Hugin owner — pending.*gille-inference.*pending'
assert_contains "$README" "README names all seven v1 record kinds" 'seven v1 evidence/accounting record kinds'
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
