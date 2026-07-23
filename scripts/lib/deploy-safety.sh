#!/usr/bin/env bash

# Quote one argument for a POSIX shell. The output is safe to interpolate into
# the command string passed to ssh or rsync's remote shell.
posix_shell_quote() {
  local value=$1 quoted="'"
  while [[ "$value" == *"'"* ]]; do
    quoted+="${value%%\'*}'\\''"
    value="${value#*\'}"
  done
  printf "%s%s'" "$quoted" "$value"
}

# Registry-declared unit sources are installed byte-for-byte. Angle-bracket
# identifiers have no rendering semantics in Grimnir and indicate that a
# component-owned template was selected instead of an install-ready unit.
# Comments may document placeholders without making the unit unsafe.
unit_template_token_awk() {
  local render_enabled=${1:-false}
  local allowed=''
  if [[ "$render_enabled" == "true" ]]; then
    allowed=' token != "<user>" && token != "<home>" && token != "<deploy-path>" && token != "<install-dir>" &&'
  fi
  # shellcheck disable=SC2016 # emitted for awk, not expanded by this shell
  printf '%s' '/^[[:space:]]*[#;]/ { next } { rest=$0; while (match(rest, /<[A-Za-z][A-Za-z0-9_-]*>/)) { token=substr(rest, RSTART, RLENGTH); if ('
  printf '%s' "${allowed:-1 &&}"
  printf '%s' ' 1) { print token; exit } rest=substr(rest, RSTART + RLENGTH) } }'
}

resolve_local_unit_source() {
  local repo_path=$1 unit_file=$2 candidate
  for candidate in "$repo_path/systemd/$unit_file" "$repo_path/$unit_file"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

preflight_local_install_ready_unit_source() {
  local repo_path=$1 unit_file=$2 required=${3:-true} render_enabled=${4:-false}
  local source token

  if ! source=$(resolve_local_unit_source "$repo_path" "$unit_file"); then
    if [[ "$required" == "true" ]]; then
      printf 'ERROR: install-ready unit source missing: %s (looked in %s/systemd and %s)\n' \
        "$unit_file" "$repo_path" "$repo_path" >&2
      return 1
    fi
    return 0
  fi

  token=$(awk "$(unit_template_token_awk "$render_enabled")" "$source")
  if [[ -n "$token" ]]; then
    printf 'ERROR: unit source is not install-ready: %s (unit %s contains unresolved placeholder %s)\n' \
      "$source" "$unit_file" "$token" >&2
    return 1
  fi
}

# Emit the equivalent guard for the source selected on the remote host. This
# covers git-pull deployments and prevents a source change between local
# preflight and install from bypassing the byte-for-byte unit contract.
prepare_remote_install_ready_unit_check_command() {
  local source_var=$1 unit_file=$2 quoted_awk quoted_label
  case "$source_var" in
    unit_src|companion_src) ;;
    *) return 1 ;;
  esac
  quoted_awk=$(posix_shell_quote "$(unit_template_token_awk)")
  quoted_label=$(posix_shell_quote "$unit_file")

  # shellcheck disable=SC2016 # command substitution and source variable expand remotely
  printf '%s_placeholder=$(awk %s "$%s"); ' "$source_var" "$quoted_awk" "$source_var"
  printf '[ -z "$%s_placeholder" ] || { printf '\''ERROR: unit source is not install-ready: %%s (unit %%s contains unresolved placeholder %%s)\\n'\'' "$%s" %s "$%s_placeholder" >&2; exit 1; }' \
    "$source_var" "$source_var" "$quoted_label" "$source_var"
}

# Rsync deployments are release directories, never Git checkouts. Remove any
# stale repository metadata before syncing: `.git` can be either a directory or
# a worktree pointer file, and leaving the latter can point the Pi at a path
# that only exists on the developer laptop.
prepare_rsync_destination_command() {
  local deploy_path=$1 quoted_path
  quoted_path=$(posix_shell_quote "$deploy_path")
  printf 'mkdir -p %s && rm -rf -- %s/.git' "$quoted_path" "$quoted_path"
}

# Build the remote command that transitions a deploy target from an accepted
# commit to "unknown" before code can change. A prior valid full SHA is emitted
# for the operator's rollback log; malformed/missing markers become `unknown`.
prepare_deploy_marker_invalidation_command() {
  local deploy_path=$1 quoted_marker
  quoted_marker=$(posix_shell_quote "${deploy_path}/.deployed-commit")
  printf 'marker=%s; prior=unknown; ' "$quoted_marker"
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' 'if [ -f "$marker" ] && [ ! -L "$marker" ]; then candidate=$(tr -d '\''\r\n'\'' < "$marker") || exit 1; case "$candidate" in ""|*[!0-9a-fA-F]*) ;; *) candidate_len=${#candidate}; if [ "$candidate_len" -ge 40 ] && [ "$candidate_len" -le 64 ]; then prior=$candidate; fi ;; esac; fi; '
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' 'rm -f -- "$marker" || exit 1; if [ -e "$marker" ] || [ -L "$marker" ]; then printf '\''ERROR: deploy marker invalidation failed\n'\'' >&2; exit 1; fi; '
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' 'printf '\''DEPLOY_MARKER_INVALIDATED:%s\n'\'' "$prior"'
}

# Shared awk predicate for recurring timer acceptance. At least one realtime or
# monotonic next-elapse property must contain a concrete trigger; active timers
# whose only values are empty/infinity/n/a/0 are elapsed, not scheduled.
recurring_timer_next_check_awk() {
  # shellcheck disable=SC2016 # emitted for awk, not expanded by this shell
  printf '%s' '/^NextElapseUSec(Realtime|Monotonic)=/ && $2 != "" && $2 != "0" && $2 != "infinity" && $2 != "n/a" { scheduled=1 } END { exit(scheduled ? 0 : 1) }'
}

# Build a bounded remote-shell gate for recurring timers. A timer using
# OnUnitInactiveSec can legitimately have no next trigger while its companion
# oneshot is still running immediately after restart. Poll long enough for that
# transition, but continue to reject permanently elapsed/unscheduled timers.
prepare_recurring_timer_next_check_command() {
  local scope=$1 timer_unit=$2 manager quoted_unit quoted_label quoted_awk

  case "$scope" in
    user) manager='systemctl --user' ;;
    system) manager='sudo systemctl' ;;
    *) return 1 ;;
  esac

  quoted_unit=$(posix_shell_quote "$timer_unit")
  quoted_label=$(posix_shell_quote "$timer_unit")
  quoted_awk=$(posix_shell_quote "$(recurring_timer_next_check_awk)")

  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' '{ timer_scheduled=false; timer_attempt=1; while [ "$timer_attempt" -le 30 ]; do if '
  printf '%s show %s --property=NextElapseUSecRealtime --property=NextElapseUSecMonotonic | awk -F= %s; then ' \
    "$manager" "$quoted_unit" "$quoted_awk"
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' 'timer_scheduled=true; break; fi; sleep 1; timer_attempt=$((timer_attempt + 1)); done; '
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' '[ "$timer_scheduled" = true ] || { printf '\''ERROR: recurring timer has no concrete next trigger: %s\n'\'' '
  printf '%s >&2; exit 1; }; }' "$quoted_label"
}
