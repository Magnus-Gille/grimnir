#!/usr/bin/env bash
# Ensure the issue #2 evidence note continues to prevent a stale-data cadence decision.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$ROOT/docs/validation-staleness-evidence-2026-07-26.md"

[[ -f "$DOC" ]] || { echo "missing validation-staleness evidence note" >&2; exit 1; }

require() {
  local needle="$1"
  grep -Fq "$needle" "$DOC" || {
    echo "evidence note missing required statement: $needle" >&2
    exit 1
  }
}

require "Do not add an unattended Git pull cadence"
require "115 expected days, 115"
require "zero missing dates"
require "not run"
require "\`git pull\`"
require "immutable record"
require "scheduled validation"
require "at least 28 consecutive scheduled runs"

echo "validation-staleness evidence note checks passed"
