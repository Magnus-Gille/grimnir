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
