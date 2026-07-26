#!/usr/bin/env bash
# Regression coverage for the architecture overview guard's fail-closed input
# handling. A broken services.json must never be reported as a clean overview.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$REPO_ROOT/tests/scripts/test-architecture-component-table.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

printf '{ not valid JSON\n' > "$TMP_DIR/services.json"

if REGISTRY="$TMP_DIR/services.json" bash "$GUARD" >/dev/null 2>&1; then
  echo "FAIL: malformed registry was accepted by architecture component table guard" >&2
  exit 1
fi

cp "$REPO_ROOT/docs/architecture.md" "$TMP_DIR/architecture.md"
# shellcheck disable=SC2016 # Markdown backticks are literal table syntax.
printf '%s\n' '| **Verdandi** | Tamper-evident audit log | 3036 | Pi 1 | `verdandi` |' >> "$TMP_DIR/architecture.md"

if ARCHITECTURE="$TMP_DIR/architecture.md" bash "$GUARD" >/dev/null 2>&1; then
  echo "FAIL: duplicate registry-derived overview row was accepted" >&2
  exit 1
fi

echo "PASS: malformed registry and duplicate registry-derived row fail the architecture component table guard"
