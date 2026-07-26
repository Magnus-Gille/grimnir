#!/usr/bin/env bash
# Keep authority-derived facts in the curated architecture overview aligned
# with services.json (grimnir#5). This deliberately covers only components
# with HTTP ports: their rows are the mechanical port/host/repository view.
# Roles, non-service components, and the M5 gateway remain curated content.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="${REGISTRY:-$REPO_ROOT/services.json}"
ARCHITECTURE="${ARCHITECTURE:-$REPO_ROOT/docs/architecture.md}"

[[ -f "$REGISTRY" ]] || { echo "FAIL: registry not found: $REGISTRY" >&2; exit 1; }
[[ -f "$ARCHITECTURE" ]] || { echo "FAIL: architecture document not found: $ARCHITECTURE" >&2; exit 1; }

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# The overview uses stable reader-facing labels, while services.json owns the
# actual host identifiers. Unknown registry hosts fail closed rather than being
# silently rendered as a plausible label.
host_label() {
  case "$1" in
    huginmunin.local) echo 'Pi 1' ;;
    nas.local) echo 'Pi 2 (NAS)' ;;
    *) return 1 ;;
  esac
}

# Capture the producer before iteration: a failing process substitution would
# otherwise close its stdout and let the loop report a misleading clean pass.
if ! component_rows="$(node -e '
  const registry = require(process.argv[1]);
  for (const component of registry.components) {
    if (Number.isInteger(component.port)) {
      console.log([component.repo, component.port, component.host].join("\t"));
    }
  }
' "$REGISTRY")"; then
  err "cannot read registry-backed component rows from $REGISTRY"
  exit 1
fi

while IFS=$'\t' read -r repo port host; do
  [[ -n "$repo" ]] || continue
  label="$(host_label "$host")" || {
    err "no architecture-table host label is declared for registry host $host ($repo)"
    continue
  }

  # Match the whole row's authority-derived columns. Role and display name are
  # intentionally free-form, but the registry repo, port, and host must agree.
  row_count="$(awk -F'|' -v repo="$repo" -v port="$port" -v host="$label" '
    $0 ~ /^\|/ {
      for (i = 1; i <= NF; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
      }
      if ($4 == port && $5 == host && $6 == "`" repo "`") matches += 1
    }
    END { print matches + 0 }
  ' "$ARCHITECTURE")"
  case "$row_count" in
    1) ;;
    0) err "$repo must have an architecture overview row with port $port and host $label" ;;
    *) err "$repo has $row_count duplicate architecture overview rows with port $port and host $label" ;;
  esac
done <<< "$component_rows"

if (( fail )); then
  exit 1
fi

echo "PASS: architecture component overview matches registry-backed port, host, and repo facts"
