#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY_LIB="$SCRIPT_DIR/../lib/notify.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home"
cat > "$TMP_DIR/bin/curl" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '503'
EOF
chmod +x "$TMP_DIR/bin/curl"

export CURL_LOG="$TMP_DIR/curl.log"
export HOME="$TMP_DIR/home"
export PATH="$TMP_DIR/bin:$PATH"
export RATATOSKR_ENV="$TMP_DIR/missing-ratatoskr.env"
export NOTIFY_ENV="$TMP_DIR/missing-notify.env"
export RATATOSKR_URL=""
export RATATOSKR_SEND_API_KEY="test-bearer-key"
export TELEGRAM_ALLOWED_USERS="12345"
export TELEGRAM_BOT_TOKEN=""

# Resolved from this test's absolute SCRIPT_DIR.
# shellcheck disable=SC1090
source "$NOTIFY_LIB"
notify_telegram "test alert"

if [[ -e "$CURL_LOG" ]]; then
  echo "FAIL: missing RATATOSKR_URL invoked curl and could disclose the bearer key" >&2
  exit 1
fi

echo "PASS: missing RATATOSKR_URL does not invoke authenticated Ratatoskr curl"
