#!/usr/bin/env bash
# Regression tests for scope-aware local/remote systemd validation (#63).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/systemd-status.sh
source "$SCRIPT_DIR/../lib/systemd-status.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
MOCK_BIN="$TMP_DIR/bin"
mkdir -p "$MOCK_BIN"
export SYSTEMD_STATUS_TEST_LOG="$TMP_DIR/systemctl.log"
export SYSTEMD_USER=tester

cat > "$MOCK_BIN/id" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -un) printf '%s\n' tester ;;
  -u) printf '%s\n' 1001 ;;
  *) printf '%s\n' 1001 ;;
esac
EOF

cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
{
  printf 'runtime=%s\n' "${XDG_RUNTIME_DIR:-}"
  printf 'bus=%s\n' "${DBUS_SESSION_BUS_ADDRESS:-}"
  printf 'arg=%s\n' "$@"
} > "$SYSTEMD_STATUS_TEST_LOG"
if [[ "${SYSTEMD_STATUS_TEST_EMPTY:-false}" == "true" ]]; then
  exit 1
fi
printf '%s\n' "${SYSTEMD_STATUS_TEST_RESULT:-active}"
[[ "${SYSTEMD_STATUS_TEST_RESULT:-active}" == "active" ]]
EOF

cat > "$MOCK_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
if [[ "${SYSTEMD_STATUS_TEST_SSH_FAIL:-false}" == "true" ]]; then
  exit 255
fi
while [[ "${1:-}" == "-o" ]]; do shift 2; done
printf 'target=%s\n' "$1" > "$SYSTEMD_STATUS_TEST_SSH_LOG"
shift
PATH="$SYSTEMD_STATUS_TEST_PATH" /bin/sh -c "$1"
EOF

chmod +x "$MOCK_BIN/id" "$MOCK_BIN/systemctl" "$MOCK_BIN/ssh"
export PATH="$MOCK_BIN:$PATH"
export SYSTEMD_STATUS_TEST_PATH="$PATH"
export SYSTEMD_STATUS_TEST_SSH_LOG="$TMP_DIR/ssh.log"

PASS=0
FAIL=0

assert_eq() {
  local description=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf '  FAIL: %s (expected %q, got %q)\n' "$description" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_log_line() {
  local description=$1 expected=$2
  if grep -Fxq -- "$expected" "$SYSTEMD_STATUS_TEST_LOG"; then
    printf '  PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf '  FAIL: %s (missing %q)\n' "$description" "$expected"
    FAIL=$((FAIL + 1))
  fi
}

echo 'systemd status helper tests'

export SYSTEMD_STATUS_TEST_RESULT=inactive
export XDG_RUNTIME_DIR=/inherited/runtime
assert_eq 'local system scope preserves inactive state' inactive \
  "$(local_systemctl_status system is-active alpha.service)"
assert_log_line 'local system scope omits --user' 'arg=is-active'
assert_log_line 'local system scope passes the unit as one argument' 'arg=alpha.service'
assert_log_line 'local system scope preserves its inherited runtime dir' 'runtime=/inherited/runtime'
unset XDG_RUNTIME_DIR

export SYSTEMD_STATUS_TEST_RESULT=active
assert_eq 'local user scope queries the user manager' active \
  "$(local_systemctl_status user is-active hugin.service)"
assert_log_line 'local user scope passes --user' 'arg=--user'
assert_log_line 'local user scope sets XDG_RUNTIME_DIR' 'runtime=/run/user/1001'
assert_log_line 'local user scope sets the bus address' 'bus=unix:path=/run/user/1001/bus'

export SYSTEMD_STATUS_TEST_RESULT=inactive
assert_eq 'remote system scope preserves inactive state' inactive \
  "$(remote_systemctl_status pi.example system is-active beta.timer)"
assert_eq 'remote system scope uses the requested SSH target' 'target=tester@pi.example' \
  "$(cat "$SYSTEMD_STATUS_TEST_SSH_LOG")"
assert_log_line 'remote system scope omits --user' 'arg=is-active'

export SYSTEMD_STATUS_TEST_RESULT=active
assert_eq 'remote user scope reaches the user manager' active \
  "$(remote_systemctl_status pi.example user is-active skuld.timer)"
assert_log_line 'remote user scope passes --user' 'arg=--user'
assert_log_line 'remote user scope exports XDG_RUNTIME_DIR' 'runtime=/run/user/1001'
assert_log_line 'remote user scope exports the bus address' 'bus=unix:path=/run/user/1001/bus'

export SYSTEMD_STATUS_TEST_SSH_FAIL=true
assert_eq 'unreachable remote manager is reported honestly' unreachable \
  "$(remote_systemctl_status pi.example user is-active hugin.service)"
unset SYSTEMD_STATUS_TEST_SSH_FAIL

export SYSTEMD_STATUS_TEST_EMPTY=true
assert_eq 'empty local manager response is reported honestly' unreachable \
  "$(local_systemctl_status user is-active hugin.service)"
unset SYSTEMD_STATUS_TEST_EMPTY
assert_eq 'unreachable manager is a warning, not an inactive failure' warn \
  "$(systemctl_status_severity unreachable user)"
assert_eq 'unreachable system manager remains a failure' fail \
  "$(systemctl_status_severity unreachable system)"
assert_eq 'known inactive unit remains a failure' fail \
  "$(systemctl_status_severity inactive user)"

marker="$TMP_DIR/injected"
malicious_unit="odd'; touch $marker; printf '.service"
export SYSTEMD_STATUS_TEST_RESULT=active
assert_eq 'remote shell quoting preserves a hostile unit argument' active \
  "$(remote_systemctl_status pi.example user is-active "$malicious_unit")"
assert_log_line 'hostile unit reaches systemctl as one argument' "arg=$malicious_unit"
if [[ ! -e "$marker" ]]; then
  printf '  PASS: hostile unit cannot execute shell syntax\n'
  PASS=$((PASS + 1))
else
  printf '  FAIL: hostile unit executed shell syntax\n'
  FAIL=$((FAIL + 1))
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
