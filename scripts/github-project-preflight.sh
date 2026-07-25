#!/usr/bin/env bash
# shellcheck shell=bash
# github-project-preflight.sh — scope-aware, read-only Roadmap Project check (#135).
#
# `preflight` makes no GitHub mutations. Its stable key=value record distinguishes
# unavailable project scopes, a missing project, and an API/transport failure.
# `ticket` deliberately creates the owning-repository issue first; when the board
# cannot be updated it reports the issue as a pending board addition instead.
set -euo pipefail

GH_BIN="${GH_BIN:-gh}"

usage() {
  cat >&2 <<'USAGE'
Usage:
  github-project-preflight.sh preflight --owner OWNER --number PROJECT_NUMBER [--require-write]
  github-project-preflight.sh ticket --repo OWNER/REPO --title TITLE --body-file FILE \
    --owner OWNER --number PROJECT_NUMBER [--label LABEL ...]
USAGE
}

safe_owner() { [[ "$1" =~ ^[A-Za-z0-9-]+$ ]]; }
safe_number() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
safe_repo() { [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; }

failure_class() {
  local detail
  detail="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  if [[ "$detail" == *"missing required scopes"* ]] || [[ "$detail" == *"read:project"* ]]; then
    printf '%s' missing_read_scope
  elif [[ "$detail" == *"project not found"* ]] || [[ "$detail" == *"could not resolve to a project"* ]]; then
    printf '%s' missing_project
  elif [[ "$detail" == *"connecting to api.github.com"* ]] || [[ "$detail" == *"network"* ]] ||
       [[ "$detail" == *"timeout"* ]] || [[ "$detail" == *"econn"* ]] || [[ "$detail" == *"http 5"* ]]; then
    printf '%s' network_api_failure
  else
    printf '%s' api_failure
  fi
}

scope_record() {
  local out code
  set +e
  out="$($GH_BIN auth status --active --hostname github.com --json hosts 2>&1)"; code=$?
  set -e
  printf '%s\n' "$out"
  return "$code"
}

has_scope() {
  local normalized wanted="$2"
  normalized="$(printf '%s' "$1" | tr -d " '")"
  [[ ",$normalized," == *",$wanted,"* ]]
}

preflight() {
  local owner="$1" number="$2" require_write="$3" auth scopes out code class
  set +e
  auth="$(scope_record)"; code=$?
  set -e
  if [[ "$code" -ne 0 ]]; then
    printf 'status=unavailable\nclass=auth_failure\nproject_owner=%s\nproject_number=%s\n' "$owner" "$number"
    return 14
  fi
  scopes="$(printf '%s' "$auth" | sed -n 's/.*"scopes":"\([^"]*\)".*/\1/p' | head -n 1)"
  # A `project` token grants Project write access and therefore project reads;
  # `read:project` is sufficient for inspection only.
  if ! has_scope "$scopes" read:project && ! has_scope "$scopes" project; then
    printf 'status=unavailable\nclass=missing_read_scope\nproject_owner=%s\nproject_number=%s\n' "$owner" "$number"
    return 10
  fi
  if [[ "$require_write" == yes ]] && ! has_scope "$scopes" project; then
    printf 'status=unavailable\nclass=missing_write_scope\nproject_owner=%s\nproject_number=%s\n' "$owner" "$number"
    return 11
  fi
  set +e
  out="$($GH_BIN project view "$number" --owner "$owner" 2>&1)"; code=$?
  set -e
  if [[ "$code" -ne 0 ]]; then
    class="$(failure_class "$out")"
    printf 'status=unavailable\nclass=%s\nproject_owner=%s\nproject_number=%s\n' "$class" "$owner" "$number"
    case "$class" in missing_read_scope) return 10 ;; missing_project) return 12 ;; network_api_failure) return 13 ;; *) return 14 ;; esac
  fi
  printf 'status=ready\nclass=none\nproject_owner=%s\nproject_number=%s\n' "$owner" "$number"
}

ticket() {
  local repo="$1" title="$2" body_file="$3" owner="$4" number="$5"; shift 5
  local -a args=(issue create --repo "$repo" --title "$title" --body-file "$body_file")
  local label issue_url result code
  if [[ "$#" -gt 0 ]]; then
    for label in "$@"; do args+=(--label "$label"); done
  fi
  issue_url="$($GH_BIN "${args[@]}")"
  printf 'issue_url=%s\n' "$issue_url"
  set +e
  result="$(preflight "$owner" "$number" yes)"; code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    $GH_BIN project item-add "$number" --owner "$owner" --url "$issue_url" >/dev/null
    printf 'board_addition=added\n'
  else
    printf '%s\n' "$result"
    printf 'board_addition=pending\npending_board_addition=%s\n' "$issue_url"
  fi
}

mode="${1:-}"; shift || true
case "$mode" in
  preflight)
    owner=''; number=''; require_write=no
    while [[ "$#" -gt 0 ]]; do
      case "$1" in --owner) owner="${2:-}"; shift 2 ;; --number) number="${2:-}"; shift 2 ;; --require-write) require_write=yes; shift ;; *) usage; exit 2 ;; esac
    done
    if ! [[ -n "$owner" && -n "$number" ]] || ! safe_owner "$owner" || ! safe_number "$number"; then usage; exit 2; fi
    preflight "$owner" "$number" "$require_write"
    ;;
  ticket)
    repo=''; title=''; body_file=''; owner=''; number=''; labels=()
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repo) repo="${2:-}"; shift 2 ;; --title) title="${2:-}"; shift 2 ;; --body-file) body_file="${2:-}"; shift 2 ;;
        --owner) owner="${2:-}"; shift 2 ;; --number) number="${2:-}"; shift 2 ;; --label) labels+=("${2:-}"); shift 2 ;;
        *) usage; exit 2 ;;
      esac
    done
    if ! [[ -n "$title" && -r "$body_file" ]] || ! safe_repo "$repo" || ! safe_owner "$owner" || ! safe_number "$number"; then usage; exit 2; fi
    if [[ "${#labels[@]}" -gt 0 ]]; then
      ticket "$repo" "$title" "$body_file" "$owner" "$number" "${labels[@]}"
    else
      ticket "$repo" "$title" "$body_file" "$owner" "$number"
    fi
    ;;
  *) usage; exit 2 ;;
esac
