#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/claude-capacity-preflight.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# shellcheck disable=SC2016 # write literal stub variables for the child process
assert_eq() { if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }
stub() {
  # shellcheck disable=SC2016 # emit literal child-process variables
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$CLAUDE_STUB_OUT"\nprintf "%%s\\n" "$CLAUDE_STUB_ERR" >&2\nif [[ -n "${CLAUDE_STUB_ARGS:-}" ]]; then printf "%%s\\n" "$*" >"$CLAUDE_STUB_ARGS"; fi\nif [[ -n "${CLAUDE_STUB_CALLS:-}" ]]; then printf "x\\n" >>"$CLAUDE_STUB_CALLS"; fi\nexit "${CLAUDE_STUB_CODE:-0}"\n' >"$TMP/claude"
  chmod +x "$TMP/claude"
}
stub

set +e
args="$TMP/args"
calls="$TMP/calls"
ready="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_ARGS="$args" CLAUDE_STUB_CALLS="$calls" CLAUDE_STUB_OUT=READY "$SCRIPT" probe --model sonnet)"; ready_code=$?
capacity="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_CODE=1 CLAUDE_STUB_ERR="You've hit your monthly spend limit" "$SCRIPT" probe --model sonnet)"; capacity_code=$?
auth="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_CODE=1 CLAUDE_STUB_ERR=unauthorized "$SCRIPT" probe --model sonnet)"; auth_code=$?
network="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_CODE=1 CLAUDE_STUB_ERR=ECONNREFUSED "$SCRIPT" probe --model sonnet)"; network_code=$?
model="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_CODE=1 CLAUDE_STUB_ERR='Requested model is not available' "$SCRIPT" probe --model unavailable-model)"; model_code=$?
selected_model="$(CLAUDE_BIN="$TMP/claude" CLAUDE_STUB_CODE=1 CLAUDE_STUB_ERR="There's an issue with the selected model (definitely-not-a-real-claude-model). It may not exist or you may not have access to it." "$SCRIPT" probe --model definitely-not-a-real-claude-model)"; selected_model_code=$?
set -e
assert_eq "ready status" 0 "$ready_code"; [[ "$ready" == *$'status=ready'* ]] || FAIL=$((FAIL+1))
[[ "$ready" == *'attempted_model=sonnet'* ]] || FAIL=$((FAIL+1))
[[ "$(cat "$args")" == *'--print'* && "$(cat "$args")" == *'--no-session-persistence'* && "$(cat "$args")" == *'--safe-mode'* && "$(cat "$args")" == *'--tools '* && "$(cat "$args")" == *'--max-budget-usd 0.01'* ]] || FAIL=$((FAIL+1))
assert_eq "one ready invocation" 1 "$(wc -l <"$calls" | tr -d '[:space:]')"
assert_eq "capacity exit" 10 "$capacity_code"; [[ "$capacity" == *$'class=capacity'* && "$capacity" == *'retry=suppressed'* ]] || FAIL=$((FAIL+1))
assert_eq "auth exit" 11 "$auth_code"; [[ "$auth" == *$'class=auth'* ]] || FAIL=$((FAIL+1))
assert_eq "network exit" 13 "$network_code"; [[ "$network" == *$'class=network'* ]] || FAIL=$((FAIL+1))
assert_eq "model exit" 12 "$model_code"; [[ "$model" == *$'class=model_unavailable'* && "$model" == *'attempted_model=unavailable-model'* ]] || FAIL=$((FAIL+1))
assert_eq "selected-model exit" 12 "$selected_model_code"; [[ "$selected_model" == *$'class=model_unavailable'* && "$selected_model" == *'attempted_model=definitely-not-a-real-claude-model'* ]] || FAIL=$((FAIL+1))
fallback="$(CLAUDE_FALLBACK_AGENT=codex "$SCRIPT" fallback --task-ref grimnir-136)"
[[ "$fallback" == *'preserve_worktree=yes'* && "$fallback" == *'branch_ahead='* && "$fallback" == *'dirty='* && "$fallback" == *'next_agent=codex'* && "$fallback" == *'retry=suppressed'* ]] || FAIL=$((FAIL+1))
echo "Results: $PASS passed, $FAIL failed"; [[ "$FAIL" -eq 0 ]]
