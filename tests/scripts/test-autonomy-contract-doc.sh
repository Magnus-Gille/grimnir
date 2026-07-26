#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for path in docs/adr-008-autonomy-constitution.md docs/autonomous-improvement-design.md docs/failure-recovery.md docs/authority.md docs/autonomy-owner-attestation-registry-v1.schema.json docs/autonomy-owner-attestation-registry-v1.json; do
  [[ -f "$ROOT/$path" ]] || { echo "missing $path" >&2; exit 1; }
done
grep -Fq 'R-exact' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'R-forward' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'W0 is disarmed' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'content-blind' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'micro-routing' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'served-model-roster' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'recovery-worker disarm' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'revert/reverted' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'recover/recovered' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'Legacy actors retain mandatory Verdandi receipts and no automatic rollback' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'Heimdall is read-only' "$ROOT/docs/adr-008-autonomy-constitution.md"
echo "autonomy-contract documentation checks passed"
