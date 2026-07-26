#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/github-actions-zero-step-preflight.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_code() { if [[ "$2" -eq "$3" ]]; then pass "$1"; else fail "$1 (got $3, expected $2)"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1"; fi; }
assert_once() { local count; count="$(grep -c "^$3=" <<<"$2" || true)"; if [[ "$count" -eq 1 ]]; then pass "$1"; else fail "$1 (found $count)"; fi; }

cat >"$TMP/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
endpoint="${2:-}"
if [[ -n "${GH_STUB_CALLS:-}" ]]; then printf '%s\n' "$endpoint" >>"$GH_STUB_CALLS"; fi
case "${GH_SCENARIO:?}:$endpoint" in
  zero:repos/Magnus-Gille/skuld/actions/runs/30180932068)
    printf '%s\n' '{"status":"completed","conclusion":"failure","pull_requests":[{"number":15}]}' ;;
  zero:repos/Magnus-Gille/skuld/actions/jobs/89737176794)
    printf '%s\n' '{"run_id":30180932068,"status":"completed","conclusion":"failure","steps":[],"runner_id":0,"runner_name":""}' ;;
  test:repos/Magnus-Gille/skuld/actions/runs/30180932068)
    printf '%s\n' '{"status":"completed","conclusion":"failure","pull_requests":[{"number":15}]}' ;;
  test:repos/Magnus-Gille/skuld/actions/jobs/89737176794)
    printf '%s\n' '{"run_id":30180932068,"status":"completed","conclusion":"failure","steps":[{"name":"Run tests","conclusion":"failure"}],"runner_id":7,"runner_name":"GitHub Actions 1"}' ;;
  pending:repos/Magnus-Gille/skuld/actions/runs/30180932068)
    printf '%s\n' '{"status":"in_progress","conclusion":null,"pull_requests":[{"number":15}]}' ;;
  pending:repos/Magnus-Gille/skuld/actions/jobs/89737176794)
    printf '%s\n' '{"run_id":30180932068,"status":"in_progress","conclusion":null,"steps":[]}' ;;
  mismatch:repos/Magnus-Gille/skuld/actions/runs/30180932068)
    printf '%s\n' '{"status":"completed","conclusion":"failure","pull_requests":[]}' ;;
  mismatch:repos/Magnus-Gille/skuld/actions/jobs/89737176794)
    printf '%s\n' '{"run_id":123,"status":"completed","conclusion":"failure","steps":[]}' ;;
  api:*) printf 'error connecting to api.github.com\n' >&2; exit 1 ;;
  *) printf 'unexpected endpoint: %s\n' "$endpoint" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/gh"

run() {
  set +e
  RESULT="$(GH_BIN="$TMP/gh" GH_SCENARIO="$1" GH_STUB_CALLS="$TMP/calls-$1" "$SCRIPT" diagnose --repo Magnus-Gille/skuld --run 30180932068 --job 89737176794)"
  CODE=$?
  set -e
}

run zero
assert_code 'zero-step runner failure exits 10' 10 "$CODE"
assert_contains 'zero-step class is explicit' "$RESULT" 'class=zero_step_runner_startup_or_capacity'
assert_contains 'zero-step says test did not run' "$RESULT" 'test_failure=no'
assert_contains 'zero-step requires owner recovery' "$RESULT" 'action=owner_recovery_required'
assert_contains 'zero-step suppresses retries' "$RESULT" 'retry=suppressed'
assert_contains 'zero-step carries affected PR' "$RESULT" 'affected_pr=Magnus-Gille/skuld#15'
assert_once 'zero-step reports run exactly once' "$RESULT" run_id
assert_once 'zero-step reports job exactly once' "$RESULT" job_id
assert_once 'zero-step reports affected PR exactly once' "$RESULT" affected_pr

run test
assert_code 'test failure exits 20' 20 "$CODE"
assert_contains 'test failure is distinct' "$RESULT" 'class=workflow_step_failure'
assert_contains 'test failure says tests ran' "$RESULT" 'test_failure=yes'

run pending
assert_code 'in-progress run exits 11' 11 "$CODE"
assert_contains 'in-progress run is distinct' "$RESULT" 'class=run_not_completed'

run mismatch
assert_code 'mismatched job exits 14' 14 "$CODE"
assert_contains 'mismatched job is invalid evidence' "$RESULT" 'class=evidence_mismatch'

run api
assert_code 'API failure exits 13' 13 "$CODE"
assert_contains 'API failure is distinct' "$RESULT" 'class=github_api_unavailable'
assert_contains 'first API failure reports one attempted request' "$RESULT" 'api_attempts=1'
assert_code 'first API failure makes one request' 1 "$(wc -l <"$TMP/calls-api" | tr -d '[:space:]')"

echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
