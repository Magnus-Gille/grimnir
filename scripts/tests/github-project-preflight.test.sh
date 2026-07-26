#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/github-project-preflight.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1"; fi; }
assert_code() { if [[ "$2" -eq "$3" ]]; then pass "$1"; else fail "$1 (got $3, expected $2)"; fi; }

cat >"$TMP/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${GH_SCENARIO:?}" in
  ticket-pending)
    if [[ "$1 $2" == "issue create" ]]; then printf 'https://github.com/Magnus-Gille/brokkr/issues/99\n';
    elif [[ "$1 $2" == "auth status" ]]; then printf '{"hosts":{"github.com":[{"active":true,"scopes":"repo"}]}}\n';
    else printf 'unexpected gh invocation: %s %s\n' "$1" "$2" >&2; exit 1; fi ;;
  ticket-add-fails)
    if [[ "$1 $2" == "issue create" ]]; then printf 'https://github.com/Magnus-Gille/brokkr/issues/100\n';
    elif [[ "$1 $2" == "auth status" ]]; then printf '{"hosts":{"github.com":[{"active":true,"scopes":"repo, read:project, project"}]}}\n';
    elif [[ "$1 $2 $3" == "project view 1" ]]; then printf 'Roadmap\n';
    elif [[ "$1 $2 $3" == "project item-add 1" ]]; then printf 'error connecting to api.github.com\n' >&2; exit 1;
    else printf 'unexpected gh invocation: %s %s\n' "$1" "$2" >&2; exit 1; fi ;;
  ready)
    if [[ "$1 $2" == "auth status" ]]; then printf '{"hosts":{"github.com":[{"active":true,"scopes":"repo, read:project, project"}]}}\n'; else printf 'Roadmap\n'; fi ;;
  missing-read)
    if [[ "$1 $2" == "auth status" ]]; then printf '{"hosts":{"github.com":[{"active":true,"scopes":"repo"}]}}\n'; else printf 'error: your authentication token is missing required scopes [read:project]\n' >&2; exit 1; fi ;;
  missing-write)
    if [[ "$1 $2" == "auth status" ]]; then printf '{"hosts":{"github.com":[{"active":true,"scopes":"repo, read:project"}]}}\n'; else printf 'Roadmap\n'; fi ;;
  missing-project)
    if [[ "$1 $2" == "auth status" ]]; then printf '{"hosts":{"github.com":[{"active":true,"scopes":"repo, read:project, project"}]}}\n'; else printf 'project not found\n' >&2; exit 1; fi ;;
  network)
    if [[ "$1 $2" == "auth status" ]]; then printf '{"hosts":{"github.com":[{"active":true,"scopes":"repo, read:project, project"}]}}\n'; else printf 'error connecting to api.github.com\n' >&2; exit 1; fi ;;
esac
STUB
chmod +x "$TMP/gh"

run() {
  set +e
  if [[ -n "${2:-}" ]]; then
    RESULT="$(PATH="$TMP:$PATH" GH_SCENARIO="$1" "$SCRIPT" preflight --owner Magnus-Gille --number 1 "$2")"
  else
    RESULT="$(PATH="$TMP:$PATH" GH_SCENARIO="$1" "$SCRIPT" preflight --owner Magnus-Gille --number 1)"
  fi
  CODE=$?
  set -e
}
run ready --require-write; assert_code 'ready exits zero' 0 "$CODE"; assert_contains 'ready is usable' "$RESULT" 'status=ready'
run missing-read; assert_code 'missing read scope exits 10' 10 "$CODE"; assert_contains 'missing read scope is explicit' "$RESULT" 'class=missing_read_scope'
run missing-write --require-write; assert_code 'missing write scope exits 11' 11 "$CODE"; assert_contains 'missing write scope is explicit' "$RESULT" 'class=missing_write_scope'
run missing-project; assert_code 'missing project exits 12' 12 "$CODE"; assert_contains 'missing project is explicit' "$RESULT" 'class=missing_project'
run network; assert_code 'network failure exits 13' 13 "$CODE"; assert_contains 'network failure is explicit' "$RESULT" 'class=network_api_failure'

printf 'body\n' >"$TMP/body.md"
set +e
ticket_output="$(PATH="$TMP:$PATH" GH_SCENARIO=ticket-pending "$SCRIPT" ticket --repo Magnus-Gille/brokkr --title Example --body-file "$TMP/body.md" --owner Magnus-Gille --number 1)"; ticket_code=$?
set -e
assert_code 'ticket creation survives unavailable board' 0 "$ticket_code"
assert_contains 'ticket reports pending board addition' "$ticket_output" 'pending_board_addition=https://github.com/Magnus-Gille/brokkr/issues/99'

set +e
item_add_output="$(PATH="$TMP:$PATH" GH_SCENARIO=ticket-add-fails "$SCRIPT" ticket --repo Magnus-Gille/brokkr --title Example --body-file "$TMP/body.md" --owner Magnus-Gille --number 1 2>"$TMP/item-add.err")"; item_add_code=$?
set -e
assert_code 'ticket creation survives item-add failure' 0 "$item_add_code"
assert_contains 'item-add failure has a deterministic class' "$item_add_output" 'board_addition_class=network_api_failure'
assert_contains 'item-add failure reports pending board addition' "$item_add_output" 'pending_board_addition=https://github.com/Magnus-Gille/brokkr/issues/100'
if [[ ! -s "$TMP/item-add.err" ]]; then pass 'item-add failure does not leak stderr'; else fail 'item-add failure does not leak stderr'; fi

echo "Results: $PASS passed, $FAIL failed"; [[ "$FAIL" -eq 0 ]]
