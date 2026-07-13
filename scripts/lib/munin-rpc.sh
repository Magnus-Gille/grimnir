# shellcheck shell=bash
# Strict JSON-RPC transport for scheduled Grimnir jobs.
#
# A successful curl exit is not sufficient: proxies can return HTTP errors and
# MCP can return JSON-RPC or tool-level errors with a readable body. Callers use
# this helper so failed validation/security writes never masquerade as durable.

munin_rpc_response_ok() {
  node --input-type=commonjs -e '
    var input = require("fs").readFileSync("/dev/stdin", "utf8");
    var value;
    try { value = JSON.parse(input); } catch (_) { process.exit(1); }
    if (!value || value.error || !value.result || value.result.isError === true) process.exit(1);
  ' 2>/dev/null
}

munin_http_jsonrpc() {
  local token="${1:-}" payload="${2:-}" url="${MUNIN_RPC_URL:-http://localhost:3030/mcp}"
  local raw data
  [[ -n "$token" && -n "$payload" ]] || return 1

  raw="$(curl -fsS --max-time 10 \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $token" \
    -d "$payload" 2>/dev/null)" || return 1

  if [[ "$raw" == data:* ]] || [[ "$raw" == *$'\ndata:'* ]]; then
    data="$(printf '%s\n' "$raw" | awk 'sub(/^data:[[:space:]]?/, "") { print; exit }')"
  else
    data="$raw"
  fi
  [[ -n "$data" ]] || return 1
  printf '%s' "$data" | munin_rpc_response_ok || return 1
  printf '%s\n' "$data"
}
