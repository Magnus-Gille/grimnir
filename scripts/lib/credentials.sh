# shellcheck shell=bash
# Read a one-line secret from a systemd credential or another protected file.
# The value is emitted only on stdout for direct assignment by the caller.

read_credential_file() {
  local credential_path=${1:-} credential_name=${2:-credential} value

  if [[ -z "$credential_path" || ! -f "$credential_path" || ! -r "$credential_path" ]]; then
    echo "ERROR: ${credential_name} credential file is missing or unreadable: ${credential_path:-<unset>}" >&2
    return 1
  fi

  value="$(cat "$credential_path")"
  value="${value%$'\r'}"
  if [[ -z "$value" ]]; then
    echo "ERROR: ${credential_name} credential file is empty" >&2
    return 1
  fi
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "ERROR: ${credential_name} credential file must contain exactly one line" >&2
    return 1
  fi

  printf '%s' "$value"
}
