#!/usr/bin/env bash
# Tenant-contract validation run (grimnir#58): drive the Codex CLI as a
# non-Claude tenant through the four substrate seams.
#
# The M5 gateway bearer token is resolved at runtime from the macOS Keychain
# via `m5-auth` and passed only through the child process environment — it is
# never written to disk and never appears in this repo.
set -euo pipefail
cd "$(dirname "$0")/../.."

# Fail fast if the Keychain lookup fails — a prefix assignment on `exec` would
# silently proceed with an empty key even under `set -e`.
M5_API_KEY="$(m5-auth)"
test -n "$M5_API_KEY"
export M5_API_KEY

# Filter the tenant's shell environment to an allowlist: the gateway key plus
# baseline shell vars. Without this, inherit=all would hand the tenant every
# secret in the parent environment.
exec codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  -c shell_environment_policy.inherit=all \
  -c 'shell_environment_policy.include_only=["M5_API_KEY","PATH","HOME","USER","SHELL","TMPDIR","LANG","TERM"]' \
  - < scripts/tenant-validation/codex-tenant-prompt-2026-07-04.md
