#!/usr/bin/env bash
# Guard the evidence boundaries recorded for grimnir#79's bounded seam audit.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$REPO_ROOT/docs/fleet-seam-audit-2026-07-26.md"

for pattern in \
  '^# Fleet seam audit — 2026-07-26$' \
  'Ratatoskr.*Heimdall' \
  'consumer-contract test is absent' \
  'Verdandi.*no live emitter' \
  'not live-verified' \
  'Munin project status.*Heimdall' \
  'real-data evidence' \
  'grimnir#79'; do
  if ! grep -Eqi "$pattern" "$DOC"; then
    echo "FAIL: audit record is missing: $pattern" >&2
    exit 1
  fi
done

echo "PASS: fleet seam audit evidence guard"
