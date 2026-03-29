#!/usr/bin/env bash
# generate-architecture.sh — Assemble the full architecture reference
#
# Reads curated content from docs/architecture.md (never modified),
# generates a live deployment snapshot into docs/snapshot.md,
# and concatenates both into docs/full-architecture.md.
#
# Usage:
#   ./scripts/generate-architecture.sh [--munin-token TOKEN]
#
# Idempotent, safe to run repeatedly. Completes in <60s.
# NEVER includes secret values — env var names only.
#
# Authority boundary (see docs/authority.md):
#   architecture.md owns: topology, roles, ports, security, deployment, roadmap
#   snapshot.md owns: timestamped service state, health, commits, Munin excerpts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIMNIR_DIR="$(dirname "$SCRIPT_DIR")"
CURATED="$GRIMNIR_DIR/docs/architecture.md"
SNAPSHOT="$GRIMNIR_DIR/docs/snapshot.md"
OUT="$GRIMNIR_DIR/docs/full-architecture.md"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
HOSTNAME_VAL="$(hostname)"
REPOS_DIR="$HOME/repos"

COMPONENTS=(munin-memory hugin heimdall skuld ratatoskr noxctl mimir)

# ─── CLI args ───────────────────────────────────────────────
MUNIN_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --munin-token) MUNIN_TOKEN="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ─── Detect environment ────────────────────────────────────
if [[ "$HOSTNAME_VAL" != "huginmunin" ]]; then
  echo "⚠ This script must run on huginmunin (needs systemd, repos, Munin)."
  exit 1
fi

# ─── Verify curated source exists ─────────────────────────
if [[ ! -f "$CURATED" ]]; then
  echo "❌ Curated source not found: $CURATED"
  exit 1
fi

# ─── Find Munin bearer token ──────────────────────────────
if [[ -z "$MUNIN_TOKEN" ]]; then
  for envfile in "$REPOS_DIR/hugin/.env" "$REPOS_DIR/ratatoskr/.env" "$REPOS_DIR/heimdall/.env"; do
    if [[ -f "$envfile" ]]; then
      val="$(grep -E '^MUNIN_API_KEY=' "$envfile" 2>/dev/null | head -1 | cut -d= -f2-)"
      if [[ -n "$val" ]]; then
        MUNIN_TOKEN="$val"
        break
      fi
    fi
  done
fi

# ─── Helper functions ─────────────────────────────────────

munin_call() {
  local payload="$1"
  if [[ -z "$MUNIN_TOKEN" ]]; then
    echo "(Munin token not available)"
    return 1
  fi
  curl -s --max-time 10 \
    -X POST http://localhost:3030/mcp \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $MUNIN_TOKEN" \
    -d "$payload" 2>/dev/null | \
    sed -n 's/^data: //p' | head -1 || echo "{}"
}

munin_tool_call() {
  local tool_name="$1" args_json="$2"
  local payload
  payload=$(node -e "console.log(JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'$tool_name',arguments:$args_json}}))")
  munin_call "$payload"
}

service_status_row() {
  local svc="$1"
  local unit="${svc}.service"
  local active enabled pid mem mem_mb started
  active="$(systemctl is-active "$unit" 2>/dev/null || echo 'unknown')"
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || echo 'unknown')"
  if [[ "$active" == "active" ]]; then
    pid="$(systemctl show "$unit" --property=MainPID 2>/dev/null | cut -d= -f2)"
    mem="$(systemctl show "$unit" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)"
    started="$(systemctl show "$unit" --property=ExecMainStartTimestamp 2>/dev/null | cut -d= -f2-)"
    if [[ "$mem" =~ ^[0-9]+$ ]] && [[ "$mem" -gt 0 ]]; then
      mem_mb="$((mem / 1024 / 1024))MB"
    else
      mem_mb="n/a"
    fi
    echo "| $unit | ✅ $active | $enabled | $pid | $mem_mb | $started |"
  else
    echo "| $unit | ❌ $active | $enabled | — | — | — |"
  fi
}

# ─── Begin snapshot generation ─────────────────────────────

echo "🔨 Generating deployment snapshot..."
echo "   Timestamp: $TIMESTAMP"
echo "   Host: $HOSTNAME_VAL"
echo ""

# ─── Service status ───────────────────────────────────────

echo "🔍 Collecting service status..."
SYSTEMD_SERVICES=(munin-memory hugin heimdall heimdall-collect heimdall-maintain ratatoskr mimir skuld)
DEPLOYMENT_TABLE=""
for svc in "${SYSTEMD_SERVICES[@]}"; do
  DEPLOYMENT_TABLE+="$(service_status_row "$svc")\n"
done

# ─── Git versions ─────────────────────────────────────────

echo "🔍 Collecting git versions..."
GIT_VERSIONS=""
for comp in "${COMPONENTS[@]}"; do
  dir="$REPOS_DIR/$comp"
  if [[ -d "$dir/.git" ]]; then
    info="$(git -C "$dir" log -1 --format='`%h` %s (%ar)' 2>/dev/null || echo '(unknown)')"
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    dirty=""
    if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
      dirty=" ⚠️ dirty"
    fi
    GIT_VERSIONS+="| $comp | $branch | $info |$dirty\n"
  else
    GIT_VERSIONS+="| $comp | — | (not a git repo) |\n"
  fi
done

# ─── Health checks ────────────────────────────────────────

echo "🔍 Running health checks..."
declare -A PORTS=(
  [munin-memory]=3030
  [hugin]=3032
  [heimdall]=3033
  [skuld]=3040
  [ratatoskr]=3034
  [mimir]=3031
)

HEALTH_RESULTS=""
for comp in "${COMPONENTS[@]}"; do
  port="${PORTS[$comp]:-}"
  if [[ -n "$port" ]]; then
    health_url="http://localhost:$port/health"
    status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$health_url" 2>/dev/null || echo '000')"
    if [[ "$status" == "000" ]] || [[ "$status" == "404" ]]; then
      health_url="http://localhost:$port/api/health"
      status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$health_url" 2>/dev/null || echo '000')"
    fi
    if [[ "$status" == "200" ]]; then
      HEALTH_RESULTS+="- ✅ **$comp** (:$port) — HTTP $status\n"
    elif [[ "$status" == "000" ]]; then
      HEALTH_RESULTS+="- ❌ **$comp** (:$port) — unreachable\n"
    else
      HEALTH_RESULTS+="- ⚠️ **$comp** (:$port) — HTTP $status\n"
    fi
  fi
done

# ─── Munin project statuses ──────────────────────────────

echo "📡 Querying Munin for project statuses..."
MUNIN_STATUSES=""
SEEN_NS=""

for ns_source in "${COMPONENTS[@]}" "grimnir" "grimnir-system"; do
  ns="projects/$ns_source"
  # Skip duplicates
  if echo "$SEEN_NS" | grep -qF "$ns"; then
    continue
  fi
  SEEN_NS+="$ns "

  result="$(munin_tool_call "memory_read" "{\"namespace\":\"$ns\",\"key\":\"status\"}" 2>/dev/null || echo "")"
  if [[ -n "$result" ]]; then
    content="$(echo "$result" | node -e "
      const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      const c=JSON.parse(d?.result?.content?.[0]?.text || '{}');
      if(c.found) console.log(c.content||'');
    " 2>/dev/null || echo "")"
    if [[ -n "$content" ]]; then
      MUNIN_STATUSES+="### $ns\n\n$content\n\n---\n\n"
    fi
  fi
done

# ─── Write snapshot.md ────────────────────────────────────

echo "📝 Writing $SNAPSHOT..."

cat > "$SNAPSHOT" << EOF

---

## Deployment Snapshot

> Captured at $TIMESTAMP on \`$HOSTNAME_VAL\`
>
> This section is auto-generated by \`scripts/generate-architecture.sh\`.
> Do not edit — changes will be overwritten. Edit \`docs/architecture.md\` for curated content.

### Service Status

| Unit | State | Enabled | PID | Memory | Started |
|------|-------|---------|-----|--------|---------|
$(echo -e "$DEPLOYMENT_TABLE")

### Repository Versions

| Repo | Branch | Last Commit |
|------|--------|-------------|
$(echo -e "$GIT_VERSIONS")

### Health Checks

$(echo -e "$HEALTH_RESULTS")
EOF

# Munin project statuses
if [[ -n "$MUNIN_STATUSES" ]]; then
  cat >> "$SNAPSHOT" << EOF

---

## Project Statuses (from Munin)

> Live project state from Munin memory. Authoritative for current work and blockers.
> Architecture facts (roles, ports, topology) are owned by the sections above.

$(echo -e "$MUNIN_STATUSES")
EOF
fi

# Footer
cat >> "$SNAPSHOT" << EOF

---

*Snapshot generated at $TIMESTAMP on \`$HOSTNAME_VAL\` by \`scripts/generate-architecture.sh\`*
EOF

# ─── Assemble full-architecture.md ─────────────────────────

echo "📝 Assembling $OUT..."
cat "$CURATED" "$SNAPSHOT" > "$OUT"

# ─── Verify no secrets leaked ─────────────────────────────

SECRET_CHECK="$(grep -E '(Bearer [A-Za-z0-9_/+=-]{10,}|eyJ[A-Za-z0-9_-]{20,}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{30,}|gho_[a-zA-Z0-9]{30,}|glpat-[a-zA-Z0-9-]{20,}|xox[bpas]-[a-zA-Z0-9-]{20,}|AKIA[A-Z0-9]{16}|[a-f0-9]{32,})' "$OUT" | grep -v '\*\*\*\|<TOKEN>\|<key>\|<same key' | grep -v 'sha256\|Source hash\|SOURCE_HASH\|commit hash' || true)"
if [[ -n "$SECRET_CHECK" ]]; then
  echo "⚠️  WARNING: Possible secret detected in output! Review before committing:"
  echo "$SECRET_CHECK"
else
  echo "   ✅ No secrets detected in output"
fi

echo ""
echo "✅ Done:"
echo "   Curated: $CURATED ($(wc -l < "$CURATED") lines)"
echo "   Snapshot: $SNAPSHOT ($(wc -l < "$SNAPSHOT") lines)"
echo "   Combined: $OUT ($(wc -l < "$OUT") lines)"
