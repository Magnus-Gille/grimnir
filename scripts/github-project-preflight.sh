#!/usr/bin/env bash
# shellcheck shell=bash
# github-project-preflight.sh — Plane ticket creation and read-only readiness check.
#
# History: this began as the scope-aware GitHub Project preflight (#135). Tickets and the
# Grimnir Roadmap moved to self-hosted Plane CE on 2026-10-28, so it now drives the tix CLI
# (ticket gateway). The path and the subcommand names are kept so existing callers keep working.
#
# preflight  makes no mutation: it runs "tix projects". Its stable key=value record distinguishes
#            a missing tix binary, a missing token, an unknown project, and API/transport failure.
# ticket     creates the owning-repository ticket in ONE tix call. Grimnir Roadmap membership
#            (label board:grimnir-roadmap), component, priority and sender travel with that call,
#            so there is no separate board step that can be left pending.
set -euo pipefail

TIX_BIN="${TIX_BIN:-tix}"
BOARD_LABEL="board:grimnir-roadmap"
TIX_OUT=''
TIX_ERR=''
LEGACY_NOTED=no

usage() {
  cat >&2 <<'USAGE'
Usage:
  github-project-preflight.sh preflight [--repo [OWNER/]REPO|IDENT]
  github-project-preflight.sh ticket --repo [OWNER/]REPO|IDENT --title TITLE --body-file FILE \
    [--label LABEL ...] [--component NAME] [--priority urgent|high|medium|low|none] \
    [--from SENDER] [--no-board]
Exit codes: 0 ok, 2 usage, 10 missing_token, 11 missing_tix, 12 missing_project,
            13 network_api_failure, 14 api_failure.
Ignored for compatibility (GitHub Project options): --owner, --number, --require-write.
USAGE
}

safe_repo() { [[ "$1" =~ ^([A-Za-z0-9_.-]+/)?[A-Za-z0-9_.-]+$ ]]; }
# Non-empty, no control characters, and not starting with "-" (tix would read it as an option).
safe_text() { [[ -n "$1" ]] && [[ "$1" != -* ]] && [[ "$1" != *[[:cntrl:]]* ]]; }
safe_component() { local re='^[A-Za-z0-9][A-Za-z0-9._ -]{0,60}$'; [[ "$1" =~ $re ]]; }
safe_sender() { local re='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'; [[ "$1" =~ $re ]]; }

# Plane priorities; the retired board vocabulary (Critical/High/Medium/Low) is accepted too.
normalize_priority() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    urgent|critical) printf '%s' urgent ;;
    high) printf '%s' high ;;
    medium) printf '%s' medium ;;
    low) printf '%s' low ;;
    none) printf '%s' none ;;
    *) return 1 ;;
  esac
}

note_legacy() {
  if [[ "$LEGACY_NOTED" == no ]]; then
    printf '%s\n' "note: --owner/--number/--require-write are GitHub Project options and are ignored; Roadmap membership is the label $BOARD_LABEL" >&2
    LEGACY_NOTED=yes
  fi
}

failure_class() {
  local detail
  detail="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  if [[ "$detail" == *"no token"* ]] || [[ "$detail" == *"token file"* ]]; then
    printf '%s' missing_token
  elif [[ "$detail" == *"unknown project"* ]]; then
    printf '%s' missing_project
  elif [[ "$detail" == *"cannot reach"* ]] || [[ "$detail" == *"network"* ]] ||
       [[ "$detail" == *"timeout"* ]] || [[ "$detail" == *"econn"* ]] ||
       [[ "$detail" == *"fetch failed"* ]] || [[ "$detail" == *"http 5"* ]]; then
    printf '%s' network_api_failure
  else
    printf '%s' api_failure
  fi
}

class_code() {
  case "$1" in
    missing_token) return 10 ;;
    missing_tix) return 11 ;;
    missing_project) return 12 ;;
    network_api_failure) return 13 ;;
    *) return 14 ;;
  esac
}

# Runs tix with stdout and stderr captured separately into TIX_OUT / TIX_ERR; returns tix's status.
run_tix() {
  local errfile code
  errfile="$(mktemp)"
  set +e
  TIX_OUT="$("$TIX_BIN" "$@" 2>"$errfile")"; code=$?
  set -e
  TIX_ERR="$(cat "$errfile")"
  rm -f "$errfile"
  return "$code"
}

# Prints the failure record (and tix's own diagnostic on stderr), then returns the class's exit code.
fail_with() {
  local status="$1" class="$2" code=0
  if [[ -n "$TIX_ERR" ]]; then printf '%s\n' "$TIX_ERR" >&2; fi
  printf 'status=%s\nclass=%s\n' "$status" "$class"
  class_code "$class" || code=$?
  return "$code"
}

require_tix() {
  if ! command -v "$TIX_BIN" >/dev/null 2>&1; then
    TIX_ERR="tix executable not found: $TIX_BIN"
    fail_with "$1" missing_tix
    return $?
  fi
}

project_listed() {
  printf '%s\n' "$2" | awk -v p="$1" 'NR > 1 && (tolower($1) == tolower(p) || tolower($2) == tolower(p)) { found = 1 } END { exit !found }'
}

preflight() {
  local project="$1" code=0 class
  require_tix unavailable || return $?
  run_tix projects || code=$?
  if [[ "$code" -ne 0 ]]; then
    class="$(failure_class "$TIX_ERR")"
    fail_with unavailable "$class"
    return $?
  fi
  if [[ -n "$project" ]] && ! project_listed "$project" "$TIX_OUT"; then
    TIX_ERR="no Plane project matches \"$project\" (see: tix projects)"
    fail_with unavailable missing_project
    return $?
  fi
  printf 'status=ready\nclass=none\nboard_label=%s\n' "$BOARD_LABEL"
}

ticket() {
  local project="$1" title="$2" body_file="$3" component="$4" priority="$5" sender="$6" board="$7"; shift 7
  local -a args=(new -p "$project" -t "$title" -f "$body_file")
  local label key='' url='' code=0 class
  require_tix failed || return $?
  if [[ "$board" == yes ]]; then args+=(-l "$BOARD_LABEL"); fi
  if [[ -n "$component" ]]; then args+=(-l "component:$component"); fi
  if [[ "$#" -gt 0 ]]; then
    for label in "$@"; do
      if [[ "$board" == yes ]] && [[ "$label" == "$BOARD_LABEL" ]]; then continue; fi
      args+=(-l "$label")
    done
  fi
  if [[ -n "$priority" ]]; then args+=(--priority "$priority"); fi
  if [[ -n "$sender" ]]; then args+=(--from "$sender"); fi
  run_tix "${args[@]}" || code=$?
  if [[ "$code" -ne 0 ]]; then
    class="$(failure_class "$TIX_ERR")"
    fail_with failed "$class"
    return $?
  fi
  # tix new prints "KEY  URL".
  read -r key url _ <<<"$TIX_OUT" || true
  if ! [[ "$key" =~ ^[A-Za-z][A-Za-z0-9]*-[1-9][0-9]*$ ]] || ! [[ "$url" == https://* ]]; then
    TIX_ERR="unexpected tix new output; the ticket may exist, check with: tix ls -p $project"
    fail_with failed api_failure
    return $?
  fi
  printf 'status=created\nticket_key=%s\nticket_url=%s\n' "$key" "$url"
  if [[ "$board" == yes ]]; then
    printf 'board_label=%s\n' "$BOARD_LABEL"
  else
    printf 'board_label=none\n'
  fi
}

need_value() { if [[ "$1" -lt 2 ]]; then usage; exit 2; fi; }

mode="${1:-}"; shift || true
case "$mode" in
  preflight)
    repo=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repo) need_value "$#"; repo="${2:-}"; shift 2 ;;
        --owner|--number) need_value "$#"; note_legacy; shift 2 ;;
        --require-write) note_legacy; shift ;;
        *) usage; exit 2 ;;
      esac
    done
    if [[ -n "$repo" ]] && ! safe_repo "$repo"; then usage; exit 2; fi
    preflight "${repo##*/}"
    ;;
  ticket)
    repo=''; title=''; body_file=''; component=''; priority=''; sender=''; board=yes; labels=()
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repo) need_value "$#"; repo="${2:-}"; shift 2 ;;
        --title) need_value "$#"; title="${2:-}"; shift 2 ;;
        --body-file) need_value "$#"; body_file="${2:-}"; shift 2 ;;
        --label) need_value "$#"; labels+=("${2:-}"); shift 2 ;;
        --component) need_value "$#"; component="${2:-}"; shift 2 ;;
        --priority) need_value "$#"; priority="${2:-}"; shift 2 ;;
        --from) need_value "$#"; sender="${2:-}"; shift 2 ;;
        --no-board) board=no; shift ;;
        --owner|--number) need_value "$#"; note_legacy; shift 2 ;;
        --require-write) note_legacy; shift ;;
        *) usage; exit 2 ;;
      esac
    done
    if ! safe_repo "$repo" || ! safe_text "$title" || ! safe_text "$body_file" || ! [[ -r "$body_file" ]]; then usage; exit 2; fi
    if [[ -n "$component" ]] && ! safe_component "$component"; then usage; exit 2; fi
    if [[ -n "$sender" ]] && ! safe_sender "$sender"; then usage; exit 2; fi
    if [[ -n "$priority" ]]; then
      if ! priority="$(normalize_priority "$priority")"; then usage; exit 2; fi
    fi
    # A from:<sender> label becomes --from so the gateway also adds the "Filed by" footer.
    kept=()
    if [[ "${#labels[@]}" -gt 0 ]]; then
      for label in "${labels[@]}"; do
        safe_text "$label" || { usage; exit 2; }
        if [[ "$label" == from:* ]]; then
          label_sender="${label#from:}"
          safe_sender "$label_sender" || { usage; exit 2; }
          if [[ -n "$sender" ]] && [[ "$sender" != "$label_sender" ]]; then usage; exit 2; fi
          sender="$label_sender"
        else
          kept+=("$label")
        fi
      done
    fi
    if [[ "${#kept[@]}" -gt 0 ]]; then
      ticket "${repo##*/}" "$title" "$body_file" "$component" "$priority" "$sender" "$board" "${kept[@]}"
    else
      ticket "${repo##*/}" "$title" "$body_file" "$component" "$priority" "$sender" "$board"
    fi
    ;;
  *) usage; exit 2 ;;
esac
