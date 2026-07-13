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
