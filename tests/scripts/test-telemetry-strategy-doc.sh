#!/usr/bin/env bash
# Regression guard for grimnir#6: operational health, learning evidence, and
# legacy LLM journal prose have distinct roles and owners.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OBS="$ROOT/docs/observability-and-improvement.md"
SCHEDULE="$ROOT/docs/scheduled-tasks.md"
REGISTRY="$ROOT/services.json"
RETIRED_TIER_CLAIM_RE="$(< "$ROOT/tests/fixtures/retired-autonomy-claims.regex")"

require() {
  local file="$1" needle="$2"
  local flat
  flat="$(tr '\n' ' ' < "$file")"
  grep -Fq "$needle" <<< "$flat" || {
    echo "missing telemetry strategy statement in ${file#"$ROOT"/}: $needle" >&2
    exit 1
  }
}

paragraph() {
  local file="$1" heading="$2"
  awk -v heading="$heading" '
    $0 ~ heading { capture=1 }
    capture && /^[[:space:]]*$/ { exit }
    capture { print }
  ' "$file"
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
require "$OBS" "core Hugin↔gateway join is live-smoked"
require "$OBS" "authenticated preflight/stamp/echo | Implemented and exercised"
require "$OBS" "Immutable pipeline accounting | Implemented on both owners"
require "$OBS" "Routing lifecycle, watchdog, and autonomy controller | Implemented; globally disarmed"
require "$OBS" "External Codex App/CLI and Pi producers | Partial"
require "$OBS" "claude-config#11"
require "$OBS" "gille-inference#11"
require "$OBS" "gille-inference#13"
CURRENT_GAPS_PARAGRAPH="$(paragraph "$OBS" '^[*][*]Current gaps:[*][*]' | tr '\n' ' ')"
grep -qiE 'Current gaps:.*gille-inference#11.*gille-inference#13.*are closed.*full-path' <<< "$CURRENT_GAPS_PARAGRAPH" || {
  echo "Current gaps must identify #11/#13 as closed context and the residual full-path gap" >&2
  exit 1
}
require "$OBS" "Heimdall may visualize these planes; it does not create their verdicts."
require "$OBS" "The owner ceremony must precede an exact ADR-008 \`armed-canary\` class"
require "$OBS" "real canary/watch/recovery evidence must then precede promotion beyond it"

while IFS= read -r relative; do
  if grep -qiE "$RETIRED_TIER_CLAIM_RE" <<< "$(tr '\n' ' ' < "$ROOT/$relative")"; then
    echo "retired autonomy/current-truth claim remains in $relative" >&2
    exit 1
  fi
done < <(git -C "$ROOT" ls-files 'README.md' 'STATUS.md' 'docs/*.md')
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
[[ "$HUGIN_UNITS" == '[{"name":"hugin","type":"service","scope":"user"},{"name":"hugin-daily-exam-factory","type":"timer","scope":"user"},{"name":"hugin-experiment-cadence","type":"timer","scope":"user"}]' ]] || {
  echo "services.json does not declare the authoritative Hugin user-unit contract: $HUGIN_UNITS" >&2
  exit 1
}

echo "telemetry strategy documentation checks passed"
