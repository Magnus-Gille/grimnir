#!/usr/bin/env bash
# shellcheck shell=bash
# claude-capacity-preflight.sh — cheap, read-only Claude availability check (#136).
#
# probe runs one no-tools, no-session-persistence request with the fixed one-token
# prompt "Reply with exactly READY." It never retries. The output is a public-safe
# key=value record; stderr is classified but never replayed because it can contain
# account or transport detail. A capacity result exits 10, auth 11, model 12,
# network 13, and unknown 14.
#
# fallback does not invoke Claude. It preserves the current worktree/commit, reports
# whether the branch is ahead or dirty, suppresses same-capacity retries, and names
# the next configured agent for the caller to hand the same bounded task to.
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CLAUDE_PREFLIGHT_MODEL="${CLAUDE_PREFLIGHT_MODEL:-sonnet}"
NEXT_AGENT="${CLAUDE_FALLBACK_AGENT:-codex}"

usage() {
  cat >&2 <<'USAGE'
Usage: claude-capacity-preflight.sh probe [--model MODEL]
       claude-capacity-preflight.sh fallback [--task-ref SAFE-ID]
USAGE
}

safe_model() {
  [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]
}

classify_failure() {
  local text
  text="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  if [[ "$text" == *"monthly spend limit"* ]] || [[ "$text" == *"spend limit"* ]] ||
     [[ "$text" == *"capacity"* ]] || [[ "$text" == *"usage limit"* ]] || [[ "$text" == *"rate limit"* ]]; then
    printf '%s' capacity
  elif [[ "$text" == *"authentication"* ]] || [[ "$text" == *"unauthorized"* ]] ||
       [[ "$text" == *"not logged in"* ]] || [[ "$text" == *"api key"* ]]; then
    printf '%s' auth
  elif [[ "$text" == *"model"* && ( "$text" == *"unavailable"* || "$text" == *"not found"* || "$text" == *"unknown"* ) ]]; then
    printf '%s' model
  elif [[ "$text" == *"network"* ]] || [[ "$text" == *"econn"* ]] || [[ "$text" == *"enotfound"* ]] ||
       [[ "$text" == *"connection"* ]] || [[ "$text" == *"timeout"* ]]; then
    printf '%s' network
  else
    printf '%s' unknown
  fi
}

probe() {
  local model="$1" out err code failure
  if ! safe_model "$model"; then
    printf 'status=fallback\nclass=model\nmodel=invalid\nretry=suppressed\n'
    return 12
  fi
  out="$(mktemp)"; err="$(mktemp)"
  trap 'rm -f "$out" "$err"' RETURN
  set +e
  "$CLAUDE_BIN" --print --no-session-persistence --tools '' --model "$model" 'Reply with exactly READY.' >"$out" 2>"$err"
  code=$?
  set -e
  if [[ "$code" -eq 0 && "$(tr -d '[:space:]' <"$out")" == READY ]]; then
    printf 'status=ready\nclass=none\nmodel=%s\nretry=not-needed\n' "$model"
    return 0
  fi
  failure="$(classify_failure "$(cat "$err" "$out")")"
  printf 'status=fallback\nclass=%s\nmodel=%s\nretry=suppressed\n' "$failure" "$model"
  case "$failure" in
    capacity) return 10 ;; auth) return 11 ;; model) return 12 ;; network) return 13 ;; *) return 14 ;;
  esac
}

fallback() {
  local task_ref="$1" branch ahead dirty
  branch="$(git branch --show-current 2>/dev/null || printf detached)"
  ahead="$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || printf unknown)"
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then dirty=yes; else dirty=no; fi
  printf 'action=handoff\npreserve_worktree=yes\nbranch=%s\nbranch_ahead=%s\ndirty=%s\ntask_ref=%s\nnext_agent=%s\nretry=suppressed\n' \
    "$branch" "$ahead" "$dirty" "$task_ref" "$NEXT_AGENT"
}

mode="${1:-}"; shift || true
case "$mode" in
  probe)
    model="$CLAUDE_PREFLIGHT_MODEL"
    if [[ "${1:-}" == --model ]]; then model="${2:-}"; shift 2; fi
    [[ "$#" -eq 0 ]] || { usage; exit 2; }
    probe "$model"
    ;;
  fallback)
    task_ref="unspecified"
    if [[ "${1:-}" == --task-ref ]]; then task_ref="${2:-}"; shift 2; fi
    [[ "$#" -eq 0 && "$task_ref" =~ ^[A-Za-z0-9._:/-]+$ ]] || { usage; exit 2; }
    fallback "$task_ref"
    ;;
  *) usage; exit 2 ;;
esac
