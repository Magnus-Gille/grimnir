#!/usr/bin/env bash
# Regression guard for the deliberate NAS Wi-Fi and Tailscale observability policy
# established by grimnir#12.  This is a documentation contract, so validate the
# required operational claims rather than attempting to inspect a live network in CI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$ROOT/docs/network-operating-model.md"

if [[ ! -f "$DOC" ]]; then
  echo "FAIL: missing docs/network-operating-model.md" >&2
  exit 1
fi

require_text() {
  local expected="$1"
  if ! grep -Fq -- "$expected" "$DOC"; then
    echo "FAIL: network operating model is missing: $expected" >&2
    exit 1
  fi
}

require_text "NAS Wi-Fi is the current intentional primary LAN path"
require_text "Tailscale is the required transport for NAS-to-control observability"
require_text "MagicDNS name or Tailnet"
require_text "Do not disable, reprioritize, or restart either host's network interfaces"
require_text "control host's Ethernet remains the preferred default route"

echo "PASS: network operating model preserves #12 safety invariants"
