#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/github-project-preflight.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1"; fi; }
assert_code() { if [[ "$2" -eq "$3" ]]; then pass "$1"; else fail "$1 (got $3, expected $2)"; fi; }
assert_equals() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got '$3', expected '$2')"; fi; }

# tix stub: records its argv (joined with "|") and answers per TIX_SCENARIO. Messages mirror the
# real tix (gateway/src/tix-lib.ts). A gh stub proves the script no longer touches GitHub.
cat >"$TMP/tix" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|' "$@" >"${TIX_ARGS_FILE:?}"
projects_table() {
  printf 'PROJECT  REPO     OPEN    CLOSED\nGRIM     grimnir  3 open  1 closed\nBROKKR   brokkr   2 open  9 closed\n'
}
case "${TIX_SCENARIO:?}" in
  ready)
    if [[ "$1" == projects ]]; then projects_table;
    elif [[ "$1" == new ]]; then printf 'BROKKR-99  https://tickets.gille.ai/gille/browse/BROKKR-99/\n';
    else printf 'unexpected tix invocation: %s\n' "$1" >&2; exit 1; fi ;;
  missing-token)
    printf 'tix: no token: set TIX_TOKEN or put one in /home/x/.config/tix/token (mint with: ticket-gateway token create <label>)\n' >&2; exit 2 ;;
  unknown-project)
    if [[ "$1" == projects ]]; then projects_table;
    else printf 'tix: ticket_create failed (HTTP 400): Unknown project "nosuch". Use a Plane identifier or repo name.\n' >&2; exit 1; fi ;;
  network)
    printf 'tix: cannot reach https://tickets-mcp.gille.ai: fetch failed\n' >&2; exit 1 ;;
  api)
    printf 'tix: ticket_create failed (HTTP 401): invalid_token (check TIX_TOKEN; it may be revoked)\n' >&2; exit 1 ;;
  bad-output)
    printf 'created something\n' ;;
esac
STUB
cat >"$TMP/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh invoked\n' >>"${GH_CALLS_FILE:?}"
exit 1
STUB
chmod +x "$TMP/tix" "$TMP/gh"
export TIX_ARGS_FILE="$TMP/tix.args" GH_CALLS_FILE="$TMP/gh.calls"
: >"$GH_CALLS_FILE"
printf 'body\n' >"$TMP/body.md"
SECRET='s3cret-token-value'

# run SCENARIO ARGS... -> RESULT (stdout), ERR (stderr), CODE, ARGS (what the tix stub received).
run() {
  local scenario="$1"; shift
  rm -f "$TIX_ARGS_FILE"
  set +e
  RESULT="$(PATH="$TMP:$PATH" TIX_TOKEN="$SECRET" TIX_SCENARIO="$scenario" "$SCRIPT" "$@" 2>"$TMP/stderr")"; CODE=$?
  set -e
  ERR="$(cat "$TMP/stderr")"
  ARGS=''; if [[ -f "$TIX_ARGS_FILE" ]]; then ARGS="$(cat "$TIX_ARGS_FILE")"; fi
}

# ---- preflight
run ready preflight; assert_code 'preflight ready exits zero' 0 "$CODE"
assert_contains 'preflight ready is usable' "$RESULT" 'status=ready'
assert_contains 'preflight reports the roadmap label' "$RESULT" 'board_label=board:grimnir-roadmap'
assert_equals 'preflight is read-only (projects only)' 'projects|' "$ARGS"
run ready preflight --repo Magnus-Gille/grimnir; assert_code 'preflight accepts OWNER/REPO' 0 "$CODE"
run ready preflight --repo GRIM; assert_code 'preflight accepts a Plane identifier' 0 "$CODE"
run ready preflight --repo Grimnir; assert_code 'preflight matches the repo name case-insensitively' 0 "$CODE"
run ready preflight --owner Magnus-Gille --number 1 --require-write
assert_code 'preflight accepts the retired GitHub Project options' 0 "$CODE"
assert_contains 'retired options are reported as ignored' "$ERR" 'ignored'
run ready preflight --repo nosuch; assert_code 'unknown project exits 12' 12 "$CODE"
assert_contains 'unknown project is explicit' "$RESULT" 'class=missing_project'
run missing-token preflight; assert_code 'missing token exits 10' 10 "$CODE"
assert_contains 'missing token is explicit' "$RESULT" 'class=missing_token'
assert_contains 'tix diagnostic is preserved on stderr' "$ERR" 'tix: no token'
run network preflight; assert_code 'network failure exits 13' 13 "$CODE"
assert_contains 'network failure is explicit' "$RESULT" 'class=network_api_failure'
run api preflight; assert_code 'API rejection exits 14' 14 "$CODE"
assert_contains 'API rejection is explicit' "$RESULT" 'class=api_failure'
assert_not_contains 'preflight never prints the token' "$RESULT$ERR" "$SECRET"
set +e
RESULT="$(PATH="$TMP:$PATH" TIX_BIN=/nonexistent/tix TIX_SCENARIO=ready "$SCRIPT" preflight 2>/dev/null)"; CODE=$?
set -e
assert_code 'missing tix exits 11' 11 "$CODE"
assert_contains 'missing tix is explicit' "$RESULT" 'class=missing_tix'

# ---- ticket
run ready ticket --repo Magnus-Gille/brokkr --title Example --body-file "$TMP/body.md" \
  --component Hugin --priority Critical --label from:grimnir --label bug
assert_code 'ticket creation succeeds' 0 "$CODE"
assert_contains 'ticket reports its key' "$RESULT" 'ticket_key=BROKKR-99'
assert_contains 'ticket reports its Plane URL' "$RESULT" 'ticket_url=https://tickets.gille.ai/gille/browse/BROKKR-99/'
assert_contains 'ticket reports the roadmap label' "$RESULT" 'board_label=board:grimnir-roadmap'
assert_equals 'ticket is one tix call with board, component, priority and sender' \
  "new|-p|brokkr|-t|Example|-f|$TMP/body.md|-l|board:grimnir-roadmap|-l|component:Hugin|-l|bug|--priority|urgent|--from|grimnir|" "$ARGS"

run ready ticket --repo Magnus-Gille/brokkr --title Example --body-file "$TMP/body.md" --owner Magnus-Gille --number 1
assert_code 'legacy ticket invocation still works' 0 "$CODE"
assert_equals 'legacy invocation adds the roadmap label only' \
  "new|-p|brokkr|-t|Example|-f|$TMP/body.md|-l|board:grimnir-roadmap|" "$ARGS"
assert_contains 'legacy invocation notes the ignored options' "$ERR" 'ignored'

run ready ticket --repo BROKKR --title Example --body-file "$TMP/body.md" --no-board --priority low --from grimnir
assert_equals 'identifier, --no-board, --from and priority pass through' \
  "new|-p|BROKKR|-t|Example|-f|$TMP/body.md|--priority|low|--from|grimnir|" "$ARGS"
assert_contains '--no-board reports no board label' "$RESULT" 'board_label=none'

run ready ticket --repo brokkr --title Example --body-file "$TMP/body.md" --label board:grimnir-roadmap
assert_equals 'an explicit roadmap label is not duplicated' \
  "new|-p|brokkr|-t|Example|-f|$TMP/body.md|-l|board:grimnir-roadmap|" "$ARGS"

# ---- ticket: usage errors never reach tix
usage_error() {
  local name="$1"; shift
  run ready "$@"
  assert_code "$name exits 2" 2 "$CODE"
  assert_equals "$name does not call tix" '' "$ARGS"
}
usage_error 'unknown priority' ticket --repo brokkr --title T --body-file "$TMP/body.md" --priority huge
usage_error 'option-like title' ticket --repo brokkr --title -x --body-file "$TMP/body.md"
usage_error 'missing title' ticket --repo brokkr --body-file "$TMP/body.md"
usage_error 'unreadable body file' ticket --repo brokkr --title T --body-file "$TMP/absent.md"
usage_error 'invalid component' ticket --repo brokkr --title T --body-file "$TMP/body.md" --component 'a/b'
usage_error 'invalid repo' ticket --repo 'a b' --title T --body-file "$TMP/body.md"
usage_error 'conflicting senders' ticket --repo brokkr --title T --body-file "$TMP/body.md" --from alice --label from:bob
usage_error 'no-board followed by roadmap label' ticket --repo brokkr --title T --body-file "$TMP/body.md" \
  --no-board --label board:grimnir-roadmap
usage_error 'roadmap label followed by no-board' ticket --repo brokkr --title T --body-file "$TMP/body.md" \
  --label board:grimnir-roadmap --no-board
usage_error 'repeated roadmap labels with no-board' ticket --repo brokkr --title T --body-file "$TMP/body.md" \
  --no-board --label board:grimnir-roadmap --label board:grimnir-roadmap
usage_error 'option without a value' ticket --repo brokkr --body-file "$TMP/body.md" --title
usage_error 'unknown option' ticket --repo brokkr --title T --body-file "$TMP/body.md" --bogus
usage_error 'unknown subcommand' bogus

# ---- ticket: failure classes
run missing-token ticket --repo brokkr --title T --body-file "$TMP/body.md"
assert_code 'ticket without token exits 10' 10 "$CODE"; assert_contains 'ticket without token is explicit' "$RESULT" 'class=missing_token'
run unknown-project ticket --repo nosuch --title T --body-file "$TMP/body.md"
assert_code 'ticket for unknown project exits 12' 12 "$CODE"; assert_contains 'unknown project is explicit' "$RESULT" 'class=missing_project'
assert_contains 'ticket failure keeps the tix diagnostic' "$ERR" 'Unknown project'
run network ticket --repo brokkr --title T --body-file "$TMP/body.md"
assert_code 'ticket network failure exits 13' 13 "$CODE"; assert_contains 'ticket network failure is explicit' "$RESULT" 'class=network_api_failure'
run api ticket --repo brokkr --title T --body-file "$TMP/body.md"
assert_code 'ticket API rejection exits 14' 14 "$CODE"; assert_not_contains 'failed ticket reports no key' "$RESULT" 'ticket_key='
run bad-output ticket --repo brokkr --title T --body-file "$TMP/body.md"
assert_code 'unparseable tix output exits 14' 14 "$CODE"; assert_contains 'unparseable output warns the ticket may exist' "$ERR" 'ticket may exist'
assert_not_contains 'ticket never prints the token' "$RESULT$ERR" "$SECRET"
set +e
RESULT="$(PATH="$TMP:$PATH" TIX_BIN=/nonexistent/tix TIX_SCENARIO=ready "$SCRIPT" ticket --repo brokkr --title T --body-file "$TMP/body.md" 2>/dev/null)"; CODE=$?
set -e
assert_code 'ticket without tix exits 11' 11 "$CODE"

if [[ ! -s "$GH_CALLS_FILE" ]]; then pass 'the script never invokes gh'; else fail 'the script never invokes gh'; fi

echo "Results: $PASS passed, $FAIL failed"; [[ "$FAIL" -eq 0 ]]
