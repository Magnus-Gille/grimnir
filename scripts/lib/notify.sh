# shellcheck shell=bash
# ─── Grimnir shared Telegram-notify helper ───────────────────────────────────
#
# notify_telegram "message"  → pushes a one-line alert to Magnus's Telegram.
#
# Preferred path: the running Ratatoskr bot's local HTTP endpoint
#   POST http://127.0.0.1:3034/api/send  {chat_id:<number>, text:<string>}
# (no auth header — the socket is 127.0.0.1-only and gated by an allowlist).
# Falls back to the direct Telegram Bot API if Ratatoskr is unreachable.
#
# Both paths source TELEGRAM_ALLOWED_USERS (chat id) and TELEGRAM_BOT_TOKEN
# (fallback only) from the Ratatoskr .env — never hardcoded, never echoed.
# Best-effort by design: a notify failure NEVER fails the calling script.
# Compatible with bash 3.2+.

RATATOSKR_URL="${RATATOSKR_URL:-http://127.0.0.1:3034/api/send}"
RATATOSKR_ENV="${RATATOSKR_ENV:-$HOME/repos/ratatoskr/.env}"

# JSON-escape an arbitrary string into a quoted JSON string literal.
_notify_json_string() {
  MSG="$1" node --input-type=commonjs -e 'process.stdout.write(JSON.stringify(process.env.MSG||""))'
}

notify_telegram() {
  local msg="$1"
  [[ -z "$msg" ]] && return 0

  # Load chat id (+ token, used only by the fallback) from Ratatoskr's .env.
  local chat_id="" bot_token=""
  if [[ -f "$RATATOSKR_ENV" ]]; then
    chat_id="$(grep -E '^TELEGRAM_ALLOWED_USERS=' "$RATATOSKR_ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' )"
    chat_id="${chat_id%%,*}"   # first allowed user if comma-separated
    bot_token="$(grep -E '^TELEGRAM_BOT_TOKEN=' "$RATATOSKR_ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')"
  fi
  if [[ -z "$chat_id" ]]; then
    echo "  notify: no Telegram chat id available — skipping alert" >&2
    return 0
  fi
  if [[ ! "$chat_id" =~ ^-?[0-9]+$ ]]; then
    echo "  notify: TELEGRAM_ALLOWED_USERS first entry '$chat_id' is not numeric — skipping alert" >&2
    return 0
  fi

  local text_json
  text_json="$(_notify_json_string "$msg")"

  # Preferred: Ratatoskr local endpoint (chat_id MUST be an unquoted JSON number).
  local code
  code="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' -X POST "$RATATOSKR_URL" \
       -H "Content-Type: application/json" \
       -d "{\"chat_id\": ${chat_id}, \"text\": ${text_json}}" 2>/dev/null || echo 000)"
  if [[ "$code" == "200" ]]; then
    return 0
  fi

  # Fallback: direct Telegram Bot API. Pass the token-bearing URL via curl's
  # --config (stdin) so the bot token never appears in the process argv (ps).
  if [[ -n "$bot_token" ]]; then
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$bot_token" | \
    curl -sS -m 8 -o /dev/null --config - \
      --data-urlencode "chat_id=${chat_id}" \
      --data-urlencode "text=${msg}" 2>/dev/null || true
  else
    echo "  notify: Ratatoskr unreachable and no bot token for fallback" >&2
  fi
  return 0
}
