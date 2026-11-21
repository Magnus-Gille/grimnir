#!/usr/bin/env bash
# Hermetic tests for scripts/cred-status.py (GRIM-249). Uses fixtures, not live data.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
run() { python3 -I "$ROOT/scripts/cred-status.py" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }
expect() { local want=$1 name=$2; shift 2; [[ "$(run "$@")" == "$want" ]] && ok "$name" || bad "$name"; }
mk() { printf '{"schema_version":"v1","credentials":[{"id":"a","issuer":"x","consumers":["c"],"rotate_runbook":"r","verify":"v","reversal":"z"%s}]}' "$1" >"$TMP/r.json"; }
R=(--registry "$TMP/r.json")

expect 0 "committed example is valid" --validate-only
mk ',"expires_at":"2030-01-01"';  expect 0 "far expiry passes" "${R[@]}" --today 2026-01-01
mk ',"expires_at":"2026-01-31"';  expect 1 "boundary days==warn flagged" "${R[@]}" --today 2026-01-01
mk ',"expires_at":"2026-01-01"';  expect 1 "days==0 flagged" "${R[@]}" --today 2026-01-01
mk ',"expires_at":"2026-01-01"';  expect 1 "expired flagged" "${R[@]}" --today 2026-02-01
mk ',"last_rotated_at":"2026-01-01","max_age_days":100'; expect 0 "max_age path ok" "${R[@]}" --today 2026-01-02
mk ',"last_rotated_at":"2026-01-01","max_age_days":10';  expect 1 "max_age overdue" "${R[@]}" --today 2026-03-01
mk '';                            expect 1 "no expiry is UNTRACKED not green" "${R[@]}"
mk ',"status":"no-rotation-path"'; expect 1 "flagged status" "${R[@]}"
mk ',"status":"reported_expired"'; expect 2 "status typo rejected" "${R[@]}"
mk ',"token":"abc"';              expect 2 "unknown field rejected" "${R[@]}"
mk ',"verify":{"t":"ghp_abcdefghijklmnop1234"}'; expect 2 "nested dict scanned" "${R[@]}"
mk ',"verify":"AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCd"'; expect 2 "value-shaped rejected" "${R[@]}"
mk ',"verify":"host 192.0.2.10"'; expect 2 "IP rejected" "${R[@]}"
mk ',"verify":"box.local"';       expect 2 "hostname rejected" "${R[@]}"
mk ',"verify":"see ~/secrets"';   expect 2 "home path rejected" "${R[@]}"
mk ',"expires_at":"2026-13-45"';  expect 2 "invalid calendar date rejected" "${R[@]}"
mk ',"max_age_days":"x","last_rotated_at":"2026-01-01"'; expect 2 "non-int max_age rejected" "${R[@]}"
mk ',"verify":"skald-mcp-service-health"'; expect 0 "house name not a false positive" "${R[@]}" --validate-only
printf '{"schema_version":"v1","extra":{"k":"v"},"credentials":[]}' >"$TMP/r.json"; expect 2 "top-level key rejected" "${R[@]}"
printf '[]' >"$TMP/r.json"; expect 2 "non-object root is exit 2 not traceback" "${R[@]}"
printf '{"schema_version":"v1","credentials":[{"id":"ghp_abcdefghijklmnop1234","issuer":"x","consumers":["c"],"rotate_runbook":"r","verify":"v","reversal":"z"}]}' >"$TMP/r.json"
run "${R[@]}" >/dev/null; grep -q ghp_ "$TMP/err" "$TMP/out" && bad "validator echoed rejected value" || ok "stderr never echoes rejected value"
expect 2 "bad --today rejected" --today nope
echo "Passed: $PASS Failed: $FAIL"; [[ $FAIL -eq 0 ]]
