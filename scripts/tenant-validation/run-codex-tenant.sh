#!/usr/bin/env bash
# Tenant-contract validation run (grimnir#58): drive the Codex CLI as a
# non-Claude tenant through the four substrate seams.
#
# The M5 gateway bearer token is resolved at runtime from the macOS Keychain
# via `m5-auth` and passed only through the child process environment — it is
# never written to disk and never appears in this repo.
set -euo pipefail
cd "$(dirname "$0")/../.."

M5_API_KEY="$(m5-auth)" exec codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  -c shell_environment_policy.inherit=all \
  - < scripts/tenant-validation/codex-tenant-prompt-2026-07-04.md
