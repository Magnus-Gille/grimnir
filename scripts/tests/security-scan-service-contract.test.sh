#!/usr/bin/env bash
# Keep the scheduled scanner's credential boundary explicit and out of source.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
UNIT="$ROOT_DIR/systemd/grimnir-security-scan.service"

grep -Fqx 'EnvironmentFile=/home/magnus/.config/grimnir/security-scan.env' "$UNIT"
grep -Fqx 'ExecStart=/usr/bin/bash scripts/security-scan.sh' "$UNIT"
if grep -Eq '^(Environment=|ExecStart=.*--munin-token)' "$UNIT"; then
  echo "ERROR: security-scan unit must not embed a Munin credential" >&2
  exit 1
fi
