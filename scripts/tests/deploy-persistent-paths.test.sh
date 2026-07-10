#!/usr/bin/env bash
# Proves deploy.sh fails before rsync on an unsafe registry and passes declared
# root-anchored exclusions through to rsync for an audited in-target data path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

pass() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/repos/alpha"

cat > "$TMP_DIR/bin/ssh" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"DEPLOY_OK"* ]]; then
  echo "DEPLOY_OK"
fi
exit 0
EOF

cat > "$TMP_DIR/bin/rsync" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RSYNC_CAPTURE"
exit 0
EOF

chmod +x "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/rsync"

cat > "$TMP_DIR/unsafe.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": ["/srv/alpha/data"], "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF

RSYNC_CAPTURE="$TMP_DIR/unsafe-rsync.args"
export RSYNC_CAPTURE
if REGISTRY_PATH="$TMP_DIR/unsafe.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" alpha >"$TMP_DIR/unsafe.out" 2>&1; then
  fail "unsafe registry must stop deploy"
else
  pass "unsafe registry stops deploy"
fi
if [[ -e "$RSYNC_CAPTURE" ]]; then
  fail "unsafe registry must fail before rsync"
else
  pass "unsafe registry fails before rsync"
fi

cat > "$TMP_DIR/safe.json" << 'EOF'
{
  "components": [
    {
      "name": "alpha", "repo": "alpha", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/alpha",
      "persistent_paths": ["/srv/alpha/data"], "rsync_excludes": ["/data/"],
      "needs_build": false,
      "systemd_units": [{ "name": "alpha", "type": "service" }]
    }
  ]
}
EOF

RSYNC_CAPTURE="$TMP_DIR/safe-rsync.args"
export RSYNC_CAPTURE
if REGISTRY_PATH="$TMP_DIR/safe.json" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" alpha >"$TMP_DIR/safe.out" 2>&1; then
  pass "safe registry completes mocked deploy"
else
  fail "safe registry completes mocked deploy"
  sed -n '1,160p' "$TMP_DIR/safe.out"
fi
if grep -Fxq -- '--exclude=/data/' "$RSYNC_CAPTURE"; then
  pass "declared persistent-path exclusion reaches rsync"
else
  fail "declared persistent-path exclusion reaches rsync"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
