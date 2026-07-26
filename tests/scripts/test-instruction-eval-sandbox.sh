#!/usr/bin/env bash
# Static regression guard for the instruction A/B evaluator's Claude sandbox.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$SCRIPT_DIR/../../scripts/tests/ab-instructions-eval.sh"
fail=0

err() { echo "FAIL: $*" >&2; fail=1; }

rg -q -- '--setting-sources project' "$HARNESS" || \
  err "evaluator must ignore user settings while retaining project instructions"
rg -q -- '--strict-mcp-config' "$HARNESS" || \
  err "evaluator must use strict MCP configuration"
rg -q -F -- '--mcp-config '\''{"mcpServers":{}}'\''' "$HARNESS" || \
  err "evaluator must supply an explicitly empty MCP configuration"
rg -q -- '--allowedTools .*Read.*Grep.*Glob' "$HARNESS" || \
  err "evaluator must retain only the read-only tools needed for doc-hit scoring"

disallowed_line=$(rg -- '--disallowedTools' "$HARNESS" || true)
for tool in Bash Edit Write NotebookEdit WebFetch WebSearch Agent Task; do
  [[ "$disallowed_line" == *"$tool"* ]] || err "evaluator no longer disallows $tool"
done

rg -q -- 'MODEL="sonnet"' "$HARNESS" || err "default evaluator model is no longer documented as sonnet"
rg -q -- '--model "\$MODEL"' "$HARNESS" || err "evaluator no longer passes its documented model explicitly"

if (( fail )); then
  echo "instruction evaluator sandbox checks failed" >&2
  exit 1
fi

echo "PASS: instruction evaluator uses project-only settings, empty MCP, and a read-only tool surface"
