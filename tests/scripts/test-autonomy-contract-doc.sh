#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for path in docs/adr-008-autonomy-constitution.md docs/autonomous-improvement-design.md docs/failure-recovery.md docs/authority.md docs/autonomy-constitution-v2.schema.json docs/autonomous-mutation-journal-v2.schema.json docs/autonomy-coverage-registry-v2.schema.json docs/autonomy-owner-attestation-registry-v1.schema.json docs/autonomy-owner-attestation-registry-v1.json; do
  [[ -f "$ROOT/$path" ]] || { echo "missing $path" >&2; exit 1; }
done
grep -Fq 'R-exact' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'R-forward' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'W0.2 is disarmed' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq '300/3600/300/4200' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'V1 schemas, fixtures, and validator remain byte-stable' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'content-blind' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'micro-routing' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'served-model-roster' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'recovery-worker disarm' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'revert/reverted' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'recover/recovered' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'Historical recovery only' "$ROOT/docs/autonomy-journal-conformance-v1.md"
grep -Fq 'out-of-band watchdog heartbeat' "$ROOT/docs/autonomy-journal-conformance-v2.md"
grep -Fq 'Legacy actors retain mandatory Verdandi receipts and no automatic rollback' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'Heimdall is read-only' "$ROOT/docs/adr-008-autonomy-constitution.md"
echo "autonomy-contract documentation checks passed"
