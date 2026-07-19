#!/usr/bin/env bash
# Read-only, scope-aware systemd status helpers used by architecture validation.

SYSTEMD_STATUS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/deploy-safety.sh
source "$SYSTEMD_STATUS_LIB_DIR/deploy-safety.sh"

normalize_systemctl_status() {
  local status=${1%%$'\n'*}
  status=${status%$'\r'}
  case "$status" in
    active|inactive|failed|activating|deactivating|reloading|maintenance|unknown)
      printf '%s\n' "$status"
      ;;
    *)
      # A missing status normally means that the manager (or the remote host)
      # could not be reached. Do not turn that transport failure into a false
      # inactive report.
      printf '%s\n' 'unreachable'
      ;;
  esac
}

systemctl_status_severity() {
  local status=$1 scope=${2:-system}
  case "$status" in
    active) printf '%s\n' pass ;;
    unreachable)
      if [[ "$scope" == "user" ]]; then
        printf '%s\n' warn
      else
        printf '%s\n' fail
      fi
      ;;
    *) printf '%s\n' fail ;;
  esac
}

systemctl_user() {
  local user=${SYSTEMD_USER:-grimnir}
  local uid runtime bus

  uid="$(id -u "$user" 2>/dev/null || true)"
  [[ "$uid" =~ ^[0-9]+$ ]] || return 1
  runtime="/run/user/$uid"
  bus="unix:path=$runtime/bus"

  if [[ "$(id -un 2>/dev/null || true)" == "$user" ]]; then
    XDG_RUNTIME_DIR="$runtime" DBUS_SESSION_BUS_ADDRESS="$bus" systemctl --user "$@"
  else
    sudo -u "$user" env XDG_RUNTIME_DIR="$runtime" \
      DBUS_SESSION_BUS_ADDRESS="$bus" systemctl --user "$@"
  fi
}

local_systemctl_status() {
  local scope=$1 action=$2 unit=$3 user=${SYSTEMD_USER:-grimnir}
  local output

  if [[ "$scope" == "user" ]]; then
    output="$(systemctl_user "$action" "$unit" 2>/dev/null || true)"
  else
    output="$(systemctl "$action" "$unit" 2>/dev/null || true)"
  fi

  normalize_systemctl_status "$output"
}

remote_systemctl_status() {
  local host=$1 scope=$2 action=$3 unit=$4 user=${SYSTEMD_USER:-grimnir}
  local output command

  command=''
  if [[ "$scope" == "user" ]]; then
    # Expanded by the remote shell, not by this process.
    # shellcheck disable=SC2016
    command='uid=$(id -u) || exit; export XDG_RUNTIME_DIR=/run/user/$uid; export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus; '
    command+='systemctl --user '
  else
    command+='systemctl '
  fi
  command+="$(posix_shell_quote "$action") $(posix_shell_quote "$unit")"

  output="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "${user}@${host}" "$command" \
    2>/dev/null || true)"
  normalize_systemctl_status "$output"
}
