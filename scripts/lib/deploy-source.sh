#!/usr/bin/env bash
# Reusable local deployment-source identity guard.

is_full_commit_sha() {
  local revision=${1:-}
  [[ "$revision" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]
}

verify_deploy_source_identity() {
  local requested_source=${1:-} expected_revision=${2:-}
  local invocation_source=${3:-$PWD} quiet_success=${4:-false}
  local expected_source invocation_path actual_source actual_revision mismatch=false

  if ! is_full_commit_sha "$expected_revision"; then
    echo "ERROR: deploy source requires an explicit full commit SHA (40 or 64 lowercase hex characters)" >&2
    return 1
  fi

  if ! expected_source=$(cd "$requested_source" 2>/dev/null && pwd -P); then
    echo "Expected source: $requested_source @ $expected_revision"
    echo "Actual source: unresolved @ unknown"
    echo "ERROR: deployment source directory does not exist or is not accessible" >&2
    return 1
  fi

  if ! invocation_path=$(cd "$invocation_source" 2>/dev/null && pwd -P); then
    echo "Expected source: $expected_source @ $expected_revision"
    echo "Actual source: unresolved @ unknown"
    echo "ERROR: deployment invocation directory does not exist or is not accessible" >&2
    return 1
  fi

  if ! actual_source=$(git -C "$invocation_path" rev-parse --show-toplevel 2>/dev/null); then
    echo "Expected source: $expected_source @ $expected_revision"
    echo "Actual source: $invocation_path @ not-a-git-worktree"
    echo "ERROR: deployment invocation source is not a git worktree" >&2
    return 1
  fi
  if ! actual_source=$(cd "$actual_source" 2>/dev/null && pwd -P); then
    echo "Expected source: $expected_source @ $expected_revision"
    echo "Actual source: unresolved-git-root @ unknown"
    echo "ERROR: deployment source Git root cannot be resolved" >&2
    return 1
  fi
  actual_revision=$(git -C "$actual_source" rev-parse --verify HEAD 2>/dev/null || echo unknown)

  [[ "$expected_source" == "$invocation_path" ]] || mismatch=true
  [[ "$invocation_path" == "$actual_source" ]] || mismatch=true
  [[ "$expected_revision" == "$actual_revision" ]] || mismatch=true

  if [[ "$quiet_success" != "true" || "$mismatch" == "true" ]]; then
    echo "Expected source: $expected_source @ $expected_revision"
    echo "Actual source: $actual_source @ $actual_revision"
  fi

  if [[ "$expected_source" != "$invocation_path" ]]; then
    echo "ERROR: deployment command ran from a different directory than the expected source" >&2
    return 1
  fi
  if [[ "$invocation_path" != "$actual_source" ]]; then
    echo "ERROR: deployment invocation directory is not the resolved Git worktree root" >&2
    return 1
  fi
  if [[ "$expected_revision" != "$actual_revision" ]]; then
    echo "ERROR: deployment source revision does not match the orchestrator's expected revision" >&2
    return 1
  fi
}

verify_deploy_source_revision() {
  local requested_source=${1:-} expected_revision=${2:-} quiet_success=${3:-false}
  verify_deploy_source_identity \
    "$requested_source" "$expected_revision" "$requested_source" "$quiet_success"
}

verify_expected_remote_revision() {
  local source=${1:-} remote=${2:-origin} ref=${3:-refs/heads/main}
  local expected_revision=${4:-} quiet_success=${5:-false}
  local actual_revision output

  if ! is_full_commit_sha "$expected_revision"; then
    echo "ERROR: remote source check requires an explicit full commit SHA" >&2
    return 1
  fi
  if ! output=$(git -C "$source" ls-remote --exit-code "$remote" "$ref" 2>/dev/null); then
    echo "Expected remote source: $remote/$ref @ $expected_revision"
    echo "Actual remote source: unresolved @ unknown"
    echo "ERROR: expected deployment revision could not be resolved from the source remote" >&2
    return 1
  fi
  actual_revision=${output%%[[:space:]]*}
  if [[ "$quiet_success" != "true" || "$actual_revision" != "$expected_revision" ]]; then
    echo "Expected remote source: $remote/$ref @ $expected_revision"
    echo "Actual remote source: $remote/$ref @ $actual_revision"
  fi
  if [[ "$actual_revision" != "$expected_revision" ]]; then
    echo "ERROR: remote source revision does not match the orchestrator's expected revision" >&2
    return 1
  fi
}
