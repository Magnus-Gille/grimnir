#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/munin-rpc.sh
source "$SCRIPT_DIR/../lib/munin-rpc.sh"

PASS=0
FAIL=0
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_status() {
  local desc=$1 expected=$2 mode=$3 rc=0
  CURL_MODE="$mode" PATH="$TMP_DIR/bin:$PATH" \
    munin_http_jsonrpc token '{"jsonrpc":"2.0"}' >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — expected $expected, got $rc"
    FAIL=$((FAIL + 1))
  fi
}

mkdir -p "$TMP_DIR/bin"
apply_stub="$TMP_DIR/bin/curl"
# This file is generated only inside the disposable test directory.
# shellcheck disable=SC2016 # runtime stub expands CURL_MODE, not this test shell
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$CURL_MODE" in' \
  '  ok) printf '\''data: {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{\\"ok\\":true}"}]}}\n\n'\'' ;;' \
  '  event) printf '\''event: message\ndata:{"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{\\"ok\\":true}"}]}}\n\n'\'' ;;' \
  '  json) printf '\''{"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{\\"ok\\":true}"}]}}\n'\'' ;;' \
  '  read-missing) printf '\''data: {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{\\"ok\\":true,\\"found\\":false}"}]}}\n\n'\'' ;;' \
  '  inner-false) printf '\''data: {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{\\"ok\\":false}"}]}}\n\n'\'' ;;' \
  '  inner-error) printf '\''data: {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{\\"error\\":\\"write failed\\"}"}]}}\n\n'\'' ;;' \
  '  inner-malformed) printf '\''data: {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"not-json"}]}}\n\n'\'' ;;' \
  '  empty-content) printf '\''data: {"jsonrpc":"2.0","result":{"content":[]}}\n\n'\'' ;;' \
  '  rpc-error) printf '\''data: {"jsonrpc":"2.0","error":{"code":-1}}\n\n'\'' ;;' \
  '  tool-error) printf '\''data: {"jsonrpc":"2.0","result":{"isError":true}}\n\n'\'' ;;' \
  '  malformed) printf '\''not-json\n'\'' ;;' \
  '  transport) exit 22 ;;' \
  'esac' > "$apply_stub"
chmod +x "$apply_stub"

echo "Munin RPC response tests"
echo "========================"
assert_status "valid SSE result succeeds" 0 ok
assert_status "SSE event and unspaced data result succeeds" 0 event
assert_status "valid JSON result succeeds" 0 json
assert_status "memory_read ok=true found=false succeeds" 0 read-missing
assert_status "inner ok=false fails" 1 inner-false
assert_status "inner error fails" 1 inner-error
assert_status "malformed inner text fails" 1 inner-malformed
assert_status "empty tool content fails" 1 empty-content
assert_status "JSON-RPC error fails" 1 rpc-error
assert_status "MCP tool error fails" 1 tool-error
assert_status "malformed response fails" 1 malformed
assert_status "HTTP/transport failure fails" 1 transport

rc=0; munin_http_jsonrpc '' '{}' >/dev/null 2>&1 || rc=$?
if [[ "$rc" == 1 ]]; then
  echo "  PASS: missing token fails"
  PASS=$((PASS + 1))
else
  echo "  FAIL: missing token must fail"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
