#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for path in docs/adr-008-autonomy-constitution.md docs/autonomous-improvement-design.md docs/failure-recovery.md docs/authority.md; do
  [[ -f "$ROOT/$path" ]] || { echo "missing $path" >&2; exit 1; }
done
grep -Fq 'R-exact' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'R-forward' "$ROOT/docs/adr-008-autonomy-constitution.md"
grep -Fq 'W0 is disarmed' "$ROOT/docs/adr-008-autonomy-constitution.md"
echo "autonomy-contract documentation checks passed"
