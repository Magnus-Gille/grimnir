#!/usr/bin/env bash
# Regression tests for grimnir#206: security-scan.sh must honour MUNIN_TOKEN
# from the environment (the systemd unit supplies it via EnvironmentFile=)
# instead of discarding it, while --munin-token still takes precedence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/../security-scan.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Run only the CLI-argument block of the scanner and print the resolved token.
resolve_token() {
  local block
  block="$(sed -n '/^# ─── CLI args/,/^done$/p' "$SCANNER")"
  bash -c "set -euo pipefail; $block"$'\n''printf "%s" "$MUNIN_TOKEN"' resolve-token "$@"
}

echo "security scan environment token tests"
echo "====================================="

if [[ "$(grep -c '^# ─── CLI args' "$SCANNER")" -ne 1 ]]; then
  fail "scanner has exactly one CLI args block to exercise"
else
  pass "scanner has exactly one CLI args block to exercise"
fi

got="$(MUNIN_TOKEN=from-environment resolve_token)"
if [[ "$got" == "from-environment" ]]; then
  pass "MUNIN_TOKEN from the environment is kept"
else
  fail "MUNIN_TOKEN from the environment is kept (got: '${got}')"
fi

got="$(MUNIN_TOKEN=from-environment resolve_token --munin-token from-flag)"
if [[ "$got" == "from-flag" ]]; then
  pass "--munin-token overrides the environment"
else
  fail "--munin-token overrides the environment (got: '${got}')"
fi

got="$(env -u MUNIN_TOKEN bash -c "$(declare -f resolve_token); SCANNER='$SCANNER'; resolve_token")"
if [[ -z "$got" ]]; then
  pass "no token when neither environment nor flag provides one"
else
  fail "no token when neither environment nor flag provides one (got: '${got}')"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
