#!/usr/bin/env bash
# Regression test for the operational-observability v1 contract adopted by grimnir#183.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$REPO_ROOT/docs/operational-observability-contract.md"
OBS="$REPO_ROOT/docs/observability-and-improvement.md"
INDEX="$REPO_ROOT/docs/index.md"
AUTHORITY="$REPO_ROOT/docs/authority.md"
LIFECYCLE="$REPO_ROOT/docs/data-lifecycle.md"
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

echo "Running operational-observability contract documentation assertions..."
assert_contains "$DOC" "contract doc exists with a title" '^# Operational-observability contract v1'
assert_contains "$DOC" "records accepted status" '^> \*\*Status:\*\* accepted v1\.$'
assert_contains "$DOC" "lists the closed observation states" "ok\`, \`degraded\`, \`failed\`, \`stale\`, \`unknown\`, and \`not_applicable"
assert_contains "$DOC" "states missing or expired evidence can never become healthy" 'missing or expired evidence can never become healthy'
assert_contains "$DOC" "binds source service instance version attempt and timestamps" 'Every `service-observation` binds source, service/instance, producer version'
assert_contains "$DOC" "requires whole second UTC Z timestamps" 'whole-second UTC instant encoded as'
assert_contains "$DOC" "defines liveness readiness dependency semantics" "liveness\`, \`readiness\`, and \`dependency"
assert_contains "$DOC" "requires W3C trace context" 'W3C trace context'
assert_contains "$DOC" "requires deny-by-default serialization export" 'deny-by-default'
assert_contains "$DOC" "keeps automatic instrumentation disabled by default" 'Automatic instrumentation is disabled by default'
assert_contains "$DOC" "defines the aggregation truth table" 'Aggregation truth table'
assert_contains "$DOC" "defines authority kinds for expected inventory" 'The v1 authority kinds are closed'
assert_contains "$DOC" "defaults absent desired runtime state to active required slots" 'When `desired_runtime_state` is absent, consumers MUST treat'
assert_contains "$DOC" "defines consumer-owned max freshness" 'consumer-owned `max_freshness`'
assert_contains "$DOC" "defines stricter producer consumer effective freshness" 'consumer.s `max_freshness`'
assert_contains "$DOC" "binds producer and consumer refs through an external registry or derivation input" 'external authority registry or derivation input'
assert_contains "$DOC" "computes producer and consumer digests over the externally selected slot projection" 'externally selected slot projection'
assert_contains "$DOC" "rejects unknown producer and consumer refs or slot mismatches" 'Unknown refs or mismatched projections fail closed'
assert_contains "$DOC" "requires versioned external contract refs" 'versioned external contract'
assert_contains "$DOC" "defines canonical authority digest object fields" '"authority_kind": "services_json \| producer_contract \| consumer_contract"'
assert_contains "$DOC" "removes max freshness from digested authority objects" '`max_freshness` never appears inside the digested object'
assert_contains "$DOC" "defines canonical authority digest bytes" 'compute SHA-256 over those bytes'
assert_contains "$DOC" "defines locale free field based slot ordering" 'field-based and locale-free'
assert_contains "$DOC" "excludes not_applicable from aggregates" "\`not_applicable\` is excluded"
assert_contains "$DOC" "makes an empty expected aggregate unknown" "empty expected aggregate is \`unknown\`"
assert_contains "$DOC" "keeps absent producers distinct from not_applicable" "Absent producers are distinct from \`not_applicable\`"
assert_contains "$DOC" "requires complete services json registry slots for service aggregates" 'complete mechanically derived registry slot set'
assert_contains "$DOC" "caps aggregate freshness to the earliest effective child" 'earliest effective child `fresh_until`'
assert_contains "$DOC" "requires collector health meta slot" 'collector_health'
assert_contains "$DOC" "requires a bound trace policy for service overall aggregates" 'bind exactly one `trace-policy` record'
assert_contains "$DOC" "requires exporter health or explicit not_applicable under the bound trace policy" 'declare exactly one producer-owned `exporter_health` slot'
assert_contains "$DOC" "forbids extra slots on liveness and readiness aggregates" 'may not carry any additional producer or consumer slots'
assert_contains "$DOC" "forbids aggregate child clock backdating" 'greater than or equal to every referenced child'
assert_contains "$DOC" "requires render time aggregate expiry downgrade" 'Render-time expiry'
assert_contains "$DOC" "defines major minor rollout rules" 'unknown major versions fail visibly'
assert_contains "$DOC" "limits safe optional evolution to informational extensions" "informational \`extensions\`"
assert_contains "$DOC" "states extensions are marker only" 'marker-only descriptors'
assert_contains "$DOC" "keeps trace ids diagnostic only" 'Trace IDs are diagnostic joins only'
assert_contains "$DOC" "forbids lifecycle outcome on spans" '`lifecycle_outcome` or any equivalent field'
assert_contains "$DOC" "binds trace policy service identity" '`trace-policy` is bound to one service identity'
assert_contains "$DOC" "forbids spans when export disabled or sampling zero" 'instrumentation/export is disabled'
assert_contains "$DOC" "forbids self parenting traces" 'Self-parenting is forbidden'
assert_contains "$DOC" "forbids prompts outputs telegram accounting credentials and raw urls" 'No prompts, outputs, memory/file contents'
assert_contains "$DOC" "forbids private ipv4 and ipv6 literals" 'Private IPv4 and IPv6 literals'
assert_contains "$DOC" "covers expanded loopback ipv6 addresses" '0:0:0:0:0:0:0:1'
assert_contains "$DOC" "covers ipv4 mapped private ipv6 addresses" 'IPv4-mapped private IPv6'
assert_contains "$DOC" "covers cgnat and wildcard ipv4 addresses" '100\.64\.0\.0/10.*0\.0\.0\.0'
assert_contains "$DOC" "links the data lifecycle policy" 'data-lifecycle\.md'
assert_contains "$DOC" "states operational telemetry retention ownership" 'operational telemetry'
assert_contains "$DOC" "states emitted trace spans are always sampled true" '`trace-span` is `sampled: true`'
assert_contains "$DOC" "states consumer tests prove stale missing partial evidence never renders healthy" 'stale, missing, and partial evidence never renders healthy'
assert_contains "$DOC" "keeps observation trace links on the same service and instance" 'same `service_id` and `instance_id`'
assert_contains "$DOC" "allows cross service parent child spans separately from observation links" 'Cross-service trace structure is allowed only'
assert_contains "$LIFECYCLE" "data lifecycle keeps an operational telemetry row" '^\| Operational telemetry \|'
assert_contains "$LIFECYCLE" "operational telemetry row keeps the six month provisional default" 'Operational telemetry \| \*\*6 months\*\* from collection'
assert_contains "$INDEX" "index references the observability contract doc" 'operational-observability-contract\.md'
assert_contains "$INDEX" "index references the observability schema" 'operational-observability-v1\.schema\.json'
assert_contains "$AUTHORITY" "authority map references the observability contract" 'operational-observability-contract\.md'
assert_contains "$OBS" "observability strategy links to the new contract" 'operational-observability-contract\.md'

if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
else
  echo "$FAIL of $((PASS + FAIL)) assertion(s) failed."
  exit 1
fi
