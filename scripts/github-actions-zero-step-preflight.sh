#!/usr/bin/env bash
# shellcheck shell=bash
# github-actions-zero-step-preflight.sh — read-only Actions failure classifier (#138).
#
# `diagnose` performs at most one GET for the run and one GET for the nominated
# job. It never calls a rerun endpoint, polls, modifies GitHub state, or sends a
# notification. Its single stable alert record includes a deduplication key so a
# caller can emit it once without treating a local test as replacement green CI.
set -euo pipefail

GH_BIN="${GH_BIN:-gh}"

usage() {
  cat >&2 <<'USAGE'
Usage: github-actions-zero-step-preflight.sh diagnose --repo OWNER/REPO --run RUN_ID --job JOB_ID
USAGE
}

safe_repo() { [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; }
safe_id() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

json_value() {
  local json="$1" expression="$2"
  node -e '
    const value = JSON.parse(process.argv[1]);
    const expression = process.argv[2].split(".");
    let current = value;
    for (const key of expression) current = key === "length" ? current.length : current?.[key];
    if (current === undefined || current === null) process.exit(1);
    if (typeof current === "object") process.exit(1);
    process.stdout.write(String(current));
  ' "$json" "$expression"
}

api_get() {
  local endpoint="$1" out code
  set +e
  out="$($GH_BIN api "$endpoint" 2>&1)"; code=$?
  set -e
  if [[ "$code" -ne 0 ]]; then
    return 1
  fi
  printf '%s' "$out"
}

record() {
  local status="$1" class="$2" test_failure="$3" action="$4" repo="$5" run_id="$6" job_id="$7" affected_pr="$8" api_attempts="$9"
  printf 'status=%s\nclass=%s\ntest_failure=%s\naction=%s\nrepo=%s\nrun_id=%s\njob_id=%s\naffected_pr=%s\nalert_key=github-actions-zero-step:%s:%s:%s\nalert_once=emit\nretry=suppressed\napi_attempts=%s\n' \
    "$status" "$class" "$test_failure" "$action" "$repo" "$run_id" "$job_id" "$affected_pr" "$repo" "$run_id" "$job_id" "$api_attempts"
}

diagnose() {
  local repo="$1" run_id="$2" job_id="$3" run job run_status job_status job_run_id steps conclusion pr_number affected_pr
  if ! run="$(api_get "repos/$repo/actions/runs/$run_id")"; then
    record unavailable github_api_unavailable unknown retry_manually_after_api_recovery "$repo" "$run_id" "$job_id" unknown 1
    return 13
  fi
  if ! job="$(api_get "repos/$repo/actions/jobs/$job_id")"; then
    record unavailable github_api_unavailable unknown retry_manually_after_api_recovery "$repo" "$run_id" "$job_id" unknown 2
    return 13
  fi
  if ! run_status="$(json_value "$run" status)" || ! job_status="$(json_value "$job" status)" ||
     ! job_run_id="$(json_value "$job" run_id)" || ! steps="$(json_value "$job" steps.length)"; then
    record unavailable malformed_api_evidence unknown inspect_github_actions_ui "$repo" "$run_id" "$job_id" unknown 2
    return 14
  fi
  pr_number="$(json_value "$run" pull_requests.0.number 2>/dev/null || printf unknown)"
  affected_pr="unknown"; [[ "$pr_number" =~ ^[1-9][0-9]*$ ]] && affected_pr="$repo#$pr_number"
  if [[ "$job_run_id" != "$run_id" ]]; then
    record unavailable evidence_mismatch unknown inspect_github_actions_ui "$repo" "$run_id" "$job_id" "$affected_pr" 2
    return 14
  fi
  if [[ "$run_status" != completed || "$job_status" != completed ]]; then
    record pending run_not_completed unknown wait_for_current_run "$repo" "$run_id" "$job_id" "$affected_pr" 2
    return 11
  fi
  conclusion="$(json_value "$job" conclusion 2>/dev/null || printf unknown)"
  if [[ "$conclusion" == success ]]; then
    record ready workflow_succeeded no none "$repo" "$run_id" "$job_id" "$affected_pr" 2
    return 0
  fi
  if [[ "$steps" == 0 ]]; then
    record blocked zero_step_runner_startup_or_capacity no owner_recovery_required "$repo" "$run_id" "$job_id" "$affected_pr" 2
    return 10
  fi
  record failed workflow_step_failure yes investigate_workflow_failure "$repo" "$run_id" "$job_id" "$affected_pr" 2
  return 20
}

mode="${1:-}"; shift || true
case "$mode" in
  diagnose)
    repo=''; run_id=''; job_id=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repo) repo="${2:-}"; shift 2 ;;
        --run) run_id="${2:-}"; shift 2 ;;
        --job) job_id="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
      esac
    done
    if ! safe_repo "$repo" || ! safe_id "$run_id" || ! safe_id "$job_id"; then usage; exit 2; fi
    diagnose "$repo" "$run_id" "$job_id"
    ;;
  *) usage; exit 2 ;;
esac
