#!/usr/bin/env bash
# Regression guard for grimnir#6: operational health, learning evidence, and
# legacy LLM journal prose have distinct roles and owners.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OBS="$ROOT/docs/observability-and-improvement.md"
SCHEDULE="$ROOT/docs/scheduled-tasks.md"
REGISTRY="$ROOT/services.json"

require() {
  local file="$1" needle="$2"
  local flat
  flat="$(tr '\n' ' ' < "$file")"
  grep -Fq "$needle" <<< "$flat" || {
    echo "missing telemetry strategy statement in ${file#"$ROOT"/}: $needle" >&2
    exit 1
  }
}

require "$OBS" "## Telemetry strategy"
require "$OBS" "Operational telemetry"
require "$OBS" "Task and product evidence"
require "$OBS" "Capability evidence"
require "$OBS" "Consequential-mutation receipts"
require "$OBS" "Debug"
require "$OBS" "Monitor"
require "$OBS" "Governed improvement"
require "$OBS" "authoritative producer"
require "$OBS" "Structured calculation comes first"
require "$OBS" "opaque task, attempt, receipt, and trace identifiers"
require "$OBS" "do not copy prompts, outputs, documents, or raw error payloads"
require "$OBS" "data-lifecycle.md"
require "$OBS" "No new generic observability service"
require "$OBS" "Current gaps"
require "$OBS" "Future work"
require "$OBS" "core Hugin↔gateway join is live"
require "$OBS" "authenticated preflight/stamp/echo | Implemented and exercised"
require "$OBS" "Immutable pipeline accounting | Implemented on both owners"
require "$OBS" "Routing lifecycle, watchdog, and autonomy controller | Implemented; armed Tier 0"
require "$OBS" "External Codex App/CLI and Pi producers | Partial"
require "$OBS" "claude-config#11"
require "$OBS" "gille-inference#11/#13"
require "$OBS" "Heimdall may visualize these planes; it does not create their verdicts."
require "$OBS" "Tier 0 auto-adopts nothing"
require "$SCHEDULE" "hugin#325"
require "$SCHEDULE" "a782c6b"
require "$SCHEDULE" "not-found"
require "$SCHEDULE" "inactive"
require "$SCHEDULE" "timer file: absent"
require "$SCHEDULE" "service file: absent"
require "$SCHEDULE" "not a telemetry aggregation or self-improvement mechanism"

HUGIN_UNITS="$(
  node -e '
    const registry = require(process.argv[1]);
    const hugin = registry.components.find((component) => component.name === "hugin");
    process.stdout.write(JSON.stringify(hugin && hugin.systemd_units));
  ' "$REGISTRY"
)"
[[ "$HUGIN_UNITS" == '[{"name":"hugin","type":"service","scope":"user"}]' ]] || {
  echo "services.json still declares retired Hugin units: $HUGIN_UNITS" >&2
  exit 1
}

echo "telemetry strategy documentation checks passed"
