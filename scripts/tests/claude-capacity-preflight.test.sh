#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/claude-capacity-preflight.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# shellcheck disable=SC2016 # write literal stub variables for the child process
assert_eq() { if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }
stub() { printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$CLAUDE_STUB_OUT"\nprintf "%%s\\n" "$CLAUDE_STUB_ERR" >&2\nexit "${CLAUDE_STUB_CODE:-0}"\n' >"$TMP/claude"; chmod +x "$TMP/claude"; }
stub

set +e
ready="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_OUT=READY "$SCRIPT" probe --model sonnet)"; ready_code=$?
capacity="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_CODE=1 CLAUDE_STUB_ERR="You've hit your monthly spend limit" "$SCRIPT" probe --model sonnet)"; capacity_code=$?
auth="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_CODE=1 CLAUDE_STUB_ERR=unauthorized "$SCRIPT" probe --model sonnet)"; auth_code=$?
network="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_CODE=1 CLAUDE_STUB_ERR=ECONNREFUSED "$SCRIPT" probe --model sonnet)"; network_code=$?
set -e
assert_eq "ready status" 0 "$ready_code"; [[ "$ready" == *$'status=ready'* ]] || FAIL=$((FAIL+1))
assert_eq "capacity exit" 10 "$capacity_code"; [[ "$capacity" == *$'class=capacity'* && "$capacity" == *'retry=suppressed'* ]] || FAIL=$((FAIL+1))
assert_eq "auth exit" 11 "$auth_code"; [[ "$auth" == *$'class=auth'* ]] || FAIL=$((FAIL+1))
assert_eq "network exit" 13 "$network_code"; [[ "$network" == *$'class=network'* ]] || FAIL=$((FAIL+1))
fallback="$(CLAUDE_FALLBACK_AGENT=codex "$SCRIPT" fallback --task-ref grimnir-136)"
[[ "$fallback" == *'preserve_worktree=yes'* && "$fallback" == *'next_agent=codex'* && "$fallback" == *'retry=suppressed'* ]] || FAIL=$((FAIL+1))
echo "Results: $PASS passed, $FAIL failed"; [[ "$FAIL" -eq 0 ]]
