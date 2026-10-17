#!/usr/bin/env bash
# Keep manual Munin token overrides out of process arguments.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

run_parser() {
  local script=$1 env_token=$2 input_file=$3 output_file=$4
  shift 4
  local harness="$TMP_DIR/parser.sh"
  local block
  block="$(sed -n '/^# ─── CLI args/,/^done$/p' "$script")"
  if [[ -z "$block" ]]; then
    echo "ERROR: parser block not found" > "$output_file"
    return 99
  fi
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' "source '$ROOT_DIR/scripts/lib/munin-rpc.sh'"
    # shellcheck disable=SC2016 # These strings are emitted into the temporary parser harness.
    printf '%s\n' 'MUNIN_TOKEN="${MUNIN_TOKEN:-}"' 'DRY_RUN=false' 'VERBOSE=false' 'FILTER_REPO=""' 'VALIDATE_MODE=false'
    printf '%s\n' "$block"
    # shellcheck disable=SC2016 # This literal is emitted into the temporary parser harness.
    printf '%s\n' 'printf "%s" "$MUNIN_TOKEN"'
  } > "$harness"
  if [[ "$input_file" == "CLOSED_STDIN" ]]; then
    if MUNIN_TOKEN="$env_token" bash "$harness" "$@" 0<&- > "$output_file" 2>&1; then
      return 0
    else
      return $?
    fi
  fi
  if MUNIN_TOKEN="$env_token" bash "$harness" "$@" < "$input_file" > "$output_file" 2>&1; then
    return 0
  else
    return $?
  fi
}

assert_token() {
  local label=$1 script=$2 env_token=$3 input=$4 expected=$5
  shift 5
  local input_file="$TMP_DIR/input" output_file="$TMP_DIR/output" rc=0
  printf '%b' "$input" > "$input_file"
  run_parser "$script" "$env_token" "$input_file" "$output_file" "$@" || rc=$?
  if [[ "$rc" -eq 0 && "$(cat "$output_file")" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (exit=$rc)"
  fi
}

assert_rejected_without_echo() {
  local label=$1 script=$2 argument=$3 expected_message=$4
  local input_file="$TMP_DIR/input" output_file="$TMP_DIR/output" marker='synthetic-secret-marker-42' rc=0
  : > "$input_file"
  run_parser "$script" environment-token "$input_file" "$output_file" "$argument" "$marker" || rc=$?
  if [[ "$rc" -ne 0 ]] && ! grep -Fq "$marker" "$output_file" &&
     grep -Fq "$expected_message" "$output_file"; then
    pass "$label"
  else
    fail "$label (exit=$rc; rejected value may have been echoed)"
  fi
}

echo "Munin token CLI tests"
echo "====================="
for script in "$ROOT_DIR/scripts/security-scan.sh" "$ROOT_DIR/scripts/generate-architecture.sh"; do
  name="$(basename "$script")"
  assert_token "$name keeps MUNIN_TOKEN from the environment" "$script" environment-token '' environment-token
  assert_token "$name accepts stdin token without a trailing newline" "$script" environment-token 'stdin-token' 'stdin-token' --munin-token-stdin
  assert_token "$name stdin override takes precedence over MUNIN_TOKEN" "$script" environment-token 'stdin-token\n' 'stdin-token' --munin-token-stdin

  assert_rejected_without_echo "$name rejects legacy token option safely" "$script" --munin-token 'ERROR: pass the token through --munin-token-stdin'
  assert_rejected_without_echo "$name hides unknown option values" "$script" --synthetic-secret-marker-42 'ERROR: unknown option'

  input_file="$TMP_DIR/input"
  output_file="$TMP_DIR/output"
  : > "$input_file"
  rc=0
  run_parser "$script" environment-token "$input_file" "$output_file" --munin-token-stdin || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -Fq 'ERROR: --munin-token-stdin requires a non-empty line on stdin' "$output_file"; then
    pass "$name rejects empty stdin safely"
  else
    fail "$name rejects empty stdin safely (exit=$rc)"
  fi

  rc=0
  run_parser "$script" environment-token CLOSED_STDIN "$output_file" --munin-token-stdin || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -Fq 'ERROR: --munin-token-stdin requires a non-empty line on stdin' "$output_file"; then
    pass "$name rejects closed stdin safely"
  else
    fail "$name rejects closed stdin safely (exit=$rc)"
  fi
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
