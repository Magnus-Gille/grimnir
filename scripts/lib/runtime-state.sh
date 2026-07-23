#!/usr/bin/env bash
# Pure desired runtime/deployment-state policy used by validation and snapshots.

RUNTIME_STATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/systemd-status.sh
source "$RUNTIME_STATE_LIB_DIR/systemd-status.sh"

runtime_checks_applicable() {
  case "${1:-active}" in
    active|stopped) printf '%s\n' yes ;;
    not-applicable) printf '%s\n' no ;;
    *) printf '%s\n' no ;;
  esac
}

health_check_applicable() {
  local desired=${1:-active} port=${2:-}
  if [[ "$desired" == "active" && -n "$port" ]]; then
    printf '%s\n' yes
  else
    printf '%s\n' no
  fi
}

deployment_check_applicable() {
  if [[ "${1:-false}" == "true" ]]; then
    printf '%s\n' yes
  else
    printf '%s\n' no
  fi
}

runtime_observation_severity() {
  local desired=${1:-active} observed=$2 scope=${3:-system}
  case "$desired" in
    active)
      systemctl_status_severity "$observed" "$scope"
      ;;
    stopped)
      case "$observed" in
        inactive) printf '%s\n' pass ;;
        unreachable)
          # Preserve the existing bounded user-manager transport warning.
          systemctl_status_severity "$observed" "$scope"
          ;;
        *) printf '%s\n' fail ;;
      esac
      ;;
    not-applicable)
      printf '%s\n' skip
      ;;
    *)
      printf '%s\n' fail
      ;;
  esac
}
