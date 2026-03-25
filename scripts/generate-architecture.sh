#!/usr/bin/env bash
# generate-architecture.sh — Dynamically assemble a comprehensive architecture doc
# for the Grimnir ecosystem by pulling from component repos, Munin, systemd, and env files.
#
# Usage:
#   ./scripts/generate-architecture.sh [--remote] [--munin-token TOKEN]
#
# Idempotent, safe to run repeatedly. Completes in <60s.
# NEVER includes secret values — env var names only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIMNIR_DIR="$(dirname "$SCRIPT_DIR")"
OUT="$GRIMNIR_DIR/docs/full-architecture.md"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
HOSTNAME_VAL="$(hostname)"
REPOS_DIR="$HOME/repos"

# Component repos (order matters for presentation)
COMPONENTS=(munin-memory hugin heimdall skuld ratatoskr noxctl mimir)

# Port assignments (canonical)
declare -A PORTS=(
  [munin-memory]=3030
  [hugin]=3035
  [heimdall]=3033
  [skuld]=3040
  [ratatoskr]=3034
  [noxctl]=""
  [mimir]=3031
)

# Roles (short descriptions)
declare -A ROLES=(
  [munin-memory]="Persistent memory & knowledge graph (MCP server + HTTP API)"
  [hugin]="Task dispatcher — polls Munin for tasks, spawns AI runtimes, reports results"
  [heimdall]="Monitoring dashboard for Raspberry Pi infrastructure"
  [skuld]="Daily intelligence briefings — synthesizes Munin memory + calendar + finances"
  [ratatoskr]="Telegram router and concierge for mobile task dispatch"
  [noxctl]="CLI and MCP server for Fortnox accounting (invoices, bookkeeping, VAT)"
  [mimir]="Self-hosted authenticated file server for artifact delivery"
)

# ─── CLI args ───────────────────────────────────────────────
REMOTE_MODE=false
MUNIN_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE_MODE=true; shift ;;
    --munin-token) MUNIN_TOKEN="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ─── Detect environment ────────────────────────────────────
if [[ "$HOSTNAME_VAL" == "huginmunin" ]]; then
  ENV_MODE="local"
else
  ENV_MODE="remote"
  REMOTE_MODE=true
fi

if [[ "$REMOTE_MODE" == true && "$ENV_MODE" != "local" ]]; then
  echo "⚠ Remote mode not yet implemented — run this script directly on huginmunin."
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

# Read file if it exists, otherwise return empty
safe_cat() {
  if [[ -f "$1" ]]; then
    cat "$1"
  fi
}

# Extract JSON field with node (available on the Pi)
json_field() {
  local file="$1" field="$2"
  if [[ -f "$file" ]]; then
    node -e "const p=require('$file'); console.log(p['$field'] || '')" 2>/dev/null || true
  fi
}

# Extract dependencies as bullet list
json_deps() {
  local file="$1"
  if [[ -f "$file" ]]; then
    node -e "
      const p=require('$file');
      const deps = {...(p.dependencies||{}), ...(p.devDependencies||{})};
      Object.entries(deps).sort().forEach(([k,v]) => console.log('- \`' + k + '\` ' + v));
    " 2>/dev/null || true
  fi
}

# Extract env var names from .env or .env.example (mask values)
env_var_names() {
  local dir="$1"
  local envfile=""
  for candidate in "$dir/.env.example" "$dir/.env"; do
    [[ -f "$candidate" ]] && envfile="$candidate"
  done
  if [[ -n "$envfile" ]]; then
    grep -E '^[A-Z_]+=.' "$envfile" 2>/dev/null | sed 's/=.*/=***/' | sort || true
  fi
}

# List source files with sizes
list_sources() {
  local dir="$1"
  if [[ -d "$dir/src" ]]; then
    find "$dir/src" -type f \( -name "*.ts" -o -name "*.js" \) 2>/dev/null | head -25 | while read -r f; do
      local sz
      sz="$(wc -l < "$f" 2>/dev/null || echo '?')"
      local rel="${f#"$dir/"}"
      echo "- \`$rel\` ($sz lines)"
    done
  fi
}

# Find systemd unit files for a component
find_systemd_units() {
  local name="$1" dir="$2"
  local units=()
  # Check repo root
  for f in "$dir/$name.service" "$dir/$name.timer"; do
    [[ -f "$f" ]] && units+=("$f")
  done
  # Check repo systemd/ dir
  for f in "$dir/systemd/"*.service "$dir/systemd/"*.timer "$dir/systemd/"*.path; do
    [[ -f "$f" ]] && units+=("$f")
  done
  # Check /etc/systemd/system
  for f in /etc/systemd/system/"$name"*.service /etc/systemd/system/"$name"*.timer /etc/systemd/system/"$name"*.path; do
    [[ -f "$f" ]] && units+=("$f")
  done
  # Deduplicate by basename
  declare -A seen
  for f in "${units[@]}"; do
    local bn
    bn="$(basename "$f")"
    if [[ -z "${seen[$bn]:-}" ]]; then
      seen[$bn]=1
      echo "$f"
    fi
  done
}

# Extract routes from source files
extract_routes() {
  local dir="$1"
  if [[ -d "$dir/src" ]]; then
    grep -rEn '(app|fastify|router|server)\.(get|post|put|patch|delete)\s*\(' "$dir/src" 2>/dev/null | \
      sed 's|.*\.\(get\|post\|put\|patch\|delete\)\s*(\s*['"'"'"]\([^'"'"'"]*\)'"'"'".*|\U\1\E \2|' | \
      sort -u | head -30 || true
  fi
}

# Better route extraction using node
extract_routes_node() {
  local dir="$1"
  if [[ -d "$dir/src" ]]; then
    node -e "
      const fs = require('fs');
      const path = require('path');
      function walk(d) {
        let files = [];
        for (const e of fs.readdirSync(d, {withFileTypes:true})) {
          const p = path.join(d, e.name);
          if (e.isDirectory()) files.push(...walk(p));
          else if (/\.(ts|js)$/.test(e.name)) files.push(p);
        }
        return files;
      }
      const routes = [];
      for (const f of walk('$dir/src')) {
        const src = fs.readFileSync(f, 'utf8');
        const re = /(?:app|fastify|router|server)\.(get|post|put|patch|delete)\s*\(\s*['\"\`]([^'\"\`]+)['\"\`]/gi;
        let m;
        while ((m = re.exec(src)) !== null) {
          routes.push(m[1].toUpperCase() + ' ' + m[2]);
        }
      }
      [...new Set(routes)].sort().forEach(r => console.log('- \`' + r + '\`'));
    " 2>/dev/null || true
  fi
}

# Get systemd service status
service_status() {
  local unit="$1"
  if systemctl is-active "$unit" &>/dev/null; then
    systemctl show "$unit" --property=ActiveState,SubState,MainPID,MemoryCurrent,ExecMainStartTimestamp 2>/dev/null | \
      sed 's/^/  /'
  else
    echo "  ActiveState=inactive (unit not running or not found)"
  fi
}

# Get git info for a repo
git_info() {
  local dir="$1"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" log -1 --format='%H %s (%ai)' 2>/dev/null || echo "(no commits)"
  else
    echo "(not a git repo)"
  fi
}

# Call Munin API
munin_call() {
  local method="$1" shift_args=("${@:2}")
  if [[ -z "$MUNIN_TOKEN" ]]; then
    echo "(Munin token not available)"
    return 1
  fi
  local payload="$1"
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

# ─── Begin assembly ────────────────────────────────────────

echo "🔨 Generating Grimnir architecture document..."
echo "   Timestamp: $TIMESTAMP"
echo "   Host: $HOSTNAME_VAL"
echo "   Output: $OUT"
echo ""

# Collect source hashes for staleness detection
HASH_INPUTS=""
for comp in "${COMPONENTS[@]}"; do
  for f in "$REPOS_DIR/$comp/package.json" "$REPOS_DIR/$comp/README.md" "$REPOS_DIR/$comp/CLAUDE.md"; do
    [[ -f "$f" ]] && HASH_INPUTS+="$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1) $(basename "$f")@$comp\n"
  done
done
SOURCE_HASH="$(echo -e "$HASH_INPUTS" | sha256sum | cut -d' ' -f1)"

# ─── Collect Munin project statuses ───────────────────────

echo "📡 Querying Munin for project statuses..."
MUNIN_STATUSES=""
ACTIVE_PROJECTS=0
ALL_BLOCKERS=""
ALL_NEXT_STEPS=""

for comp in "${COMPONENTS[@]}"; do
  for ns in "projects/$comp" "projects/grimnir"; do
    result="$(munin_tool_call "memory_read" "{\"namespace\":\"$ns\",\"key\":\"status\"}" 2>/dev/null || echo "")"
    if [[ -n "$result" ]] && echo "$result" | node -e "
      const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      const c=d?.result?.content?.[0]?.text;
      if(c){const p=JSON.parse(c); if(p.found) process.exit(0);}
      process.exit(1);
    " 2>/dev/null; then
      content="$(echo "$result" | node -e "
        const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
        const c=JSON.parse(d.result.content[0].text);
        console.log(c.content||'');
      " 2>/dev/null || echo "")"
      if [[ -n "$content" ]]; then
        MUNIN_STATUSES+="### $ns\n\n$content\n\n---\n\n"
        ACTIVE_PROJECTS=$((ACTIVE_PROJECTS + 1))
      fi
    fi
  done
done

# Also grab grimnir-level status
for ns in "projects/grimnir" "projects/grimnir-system"; do
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

echo "   Found $ACTIVE_PROJECTS project status entries"

# ─── Collect deployment snapshot ──────────────────────────

echo "🔍 Collecting deployment snapshot..."
SYSTEMD_SERVICES=(munin-memory hugin heimdall heimdall-collect heimdall-maintain ratatoskr mimir skuld)
DEPLOYMENT_TABLE=""
for svc in "${SYSTEMD_SERVICES[@]}"; do
  unit="${svc}.service"
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
    DEPLOYMENT_TABLE+="| $unit | ✅ $active | $enabled | $pid | $mem_mb | $started |\n"
  else
    DEPLOYMENT_TABLE+="| $unit | ❌ $active | $enabled | — | — | — |\n"
  fi
done

# Git versions per repo
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

# ─── Assemble component deep dives ────────────────────────

echo "📦 Assembling component deep dives..."
COMPONENT_SECTIONS=""

for comp in "${COMPONENTS[@]}"; do
  dir="$REPOS_DIR/$comp"
  echo "   → $comp"

  if [[ ! -d "$dir" ]]; then
    COMPONENT_SECTIONS+="### $comp\n\n> ⚠️ Repository not found at \`$dir\`. Skipped.\n\n"
    continue
  fi

  # Basic metadata
  name="$(json_field "$dir/package.json" "name")"
  version="$(json_field "$dir/package.json" "version")"
  description="$(json_field "$dir/package.json" "description")"
  port="${PORTS[$comp]:-}"
  role="${ROLES[$comp]:-$description}"

  COMPONENT_SECTIONS+="### ${comp}\n\n"
  COMPONENT_SECTIONS+="- **Role:** $role\n"
  COMPONENT_SECTIONS+="- **Package:** \`$name\` v$version\n"
  [[ -n "$port" ]] && COMPONENT_SECTIONS+="- **Port:** $port\n"
  COMPONENT_SECTIONS+="- **Description:** $description\n\n"

  # README excerpt (first 5 non-empty lines after title)
  if [[ -f "$dir/README.md" ]]; then
    readme_excerpt="$(sed -n '2,30p' "$dir/README.md" | grep -v '^$' | head -5)"
    if [[ -n "$readme_excerpt" ]]; then
      COMPONENT_SECTIONS+="#### Overview (from README)\n\n$readme_excerpt\n\n"
    fi
  fi

  # CLAUDE.md (include in full — it's designed for agent consumption)
  if [[ -f "$dir/CLAUDE.md" ]]; then
    claude_md="$(cat "$dir/CLAUDE.md")"
    COMPONENT_SECTIONS+="#### Architecture Notes (CLAUDE.md)\n\n<details>\n<summary>Click to expand CLAUDE.md</summary>\n\n$claude_md\n\n</details>\n\n"
  fi

  # API Surface
  routes="$(extract_routes_node "$dir")"
  if [[ -n "$routes" ]]; then
    COMPONENT_SECTIONS+="#### API Surface\n\n$routes\n\n"
  fi

  # Dependencies
  deps="$(json_deps "$dir/package.json")"
  if [[ -n "$deps" ]]; then
    COMPONENT_SECTIONS+="#### Dependencies\n\n$deps\n\n"
  fi

  # Environment variables
  env_vars="$(env_var_names "$dir")"
  if [[ -n "$env_vars" ]]; then
    COMPONENT_SECTIONS+="#### Configuration (env var names)\n\n\`\`\`\n$env_vars\n\`\`\`\n\n"
  fi

  # Systemd units
  units="$(find_systemd_units "$comp" "$dir")"
  if [[ -n "$units" ]]; then
    COMPONENT_SECTIONS+="#### Systemd Units\n\n"
    while IFS= read -r unit_file; do
      bn="$(basename "$unit_file")"
      COMPONENT_SECTIONS+="\`$bn\`:\n\`\`\`ini\n$(cat "$unit_file")\n\`\`\`\n\n"
    done <<< "$units"
  fi

  # Key source files
  sources="$(list_sources "$dir")"
  if [[ -n "$sources" ]]; then
    COMPONENT_SECTIONS+="#### Key Source Files\n\n$sources\n\n"
  fi

  # Git info
  gitinfo="$(git_info "$dir")"
  COMPONENT_SECTIONS+="#### Current Commit\n\n\`$gitinfo\`\n\n"

  COMPONENT_SECTIONS+="---\n\n"
done

# ─── Write the document ───────────────────────────────────

echo "📝 Writing $OUT..."

cat > "$OUT" << 'HEADER'
# Grimnir System — Complete Architecture & Implementation Reference

HEADER

cat >> "$OUT" << EOF
> Auto-generated on $TIMESTAMP by \`scripts/generate-architecture.sh\`
> Host: \`$HOSTNAME_VAL\` | Source hash: \`${SOURCE_HASH:0:16}\`

---

## How to Read This Document

This document is **designed for AI agent consumption**. It is auto-generated from live data across all Grimnir component repositories, Munin memory, systemd service states, and environment configurations.

- Each component section is **self-contained** — you can read any section in isolation.
- Cross-references are explicit (e.g., "Hugin polls Munin" not "the dispatcher polls the memory server").
- Environment variable names are listed but **values are never included** — they are masked as \`***\`.
- The "Current Deployment Snapshot" section reflects the state at generation time and may be stale.
- To regenerate: \`cd ~/repos/grimnir && ./scripts/generate-architecture.sh\`

---

## Executive Summary

**Grimnir** is a personal AI infrastructure system running on a Raspberry Pi 5 cluster (2 nodes). It provides persistent memory, task dispatch, monitoring, daily briefings, Telegram-based mobile interaction, accounting integration, and file serving — all orchestrated through the MCP protocol and Munin memory server.

- **$ACTIVE_PROJECTS** active project status entries in Munin
- **${#COMPONENTS[@]}** component repositories
- **${#SYSTEMD_SERVICES[@]}** systemd service units tracked

---

## System Topology

### Hardware

| Node | Hostname | Role | Specs |
|------|----------|------|-------|
| Pi 1 | huginmunin | Primary compute | Raspberry Pi 5, 8GB RAM, ARM64 |
| Pi 2 | NAS (100.99.119.52) | Storage + mimir | Raspberry Pi, file server |

### Network Model

All services bind to \`127.0.0.1\` (localhost only). External access is via **Cloudflare Tunnel** (Heimdall dashboard) or **Tailscale** (inter-node, laptop access).

### Port Assignments

| Port | Service | Protocol |
|------|---------|----------|
| 3030 | munin-memory | HTTP (MCP JSON-RPC) |
| 3031 | mimir | HTTP (file server) |
| 3033 | heimdall | HTTP (Fastify dashboard) |
| 3034 | ratatoskr | HTTP (health only; Telegram via long-poll) |
| 3035 | hugin | HTTP (health only) |
| 3040 | skuld | HTTP (briefing web UI) |

### Architecture Diagram

\`\`\`
┌──────────────────────────────────────────────────────────────────┐
│                    External Interfaces                            │
│  Claude Desktop/Code ←→ MCP (stdio)                              │
│  Telegram ←→ Ratatoskr (grammy long-poll)                        │
│  Browser ←→ Cloudflare Tunnel ←→ Heimdall                       │
│  Fortnox API ←→ Noxctl (OAuth 2.1)                              │
└──────────────────────────────────────────────────────────────────┘
         │                    │                │
    ┌────▼──────┐      ┌─────▼─────┐    ┌─────▼─────┐
    │   Munin   │◄─────│ Ratatoskr │    │  Noxctl   │
    │  Memory   │      │ (Telegram)│    │ (Fortnox) │
    │ :3030     │      │ :3034     │    │  CLI/MCP  │
    └────┬──────┘      └───────────┘    └───────────┘
         │
    ┌────┼──────────┬────────────┬──────────────┐
    │    │          │            │              │
┌───▼──┐│   ┌──────▼───┐ ┌─────▼────┐  ┌──────▼───┐
│Hugin ││   │  Skuld   │ │ Heimdall │  │  Mimir   │
│:3035 ││   │  :3040   │ │  :3033   │  │  :3031   │
│Task  ││   │ Briefing │ │ Monitor  │  │  Files   │
│Exec  ││   └──────────┘ └──────────┘  └──────────┘
└──────┘│
        │ (NAS / Pi 2)
   ┌────▼────────────┐
   │  mimir-inbox    │
   │  artifacts      │
   │  backups        │
   └─────────────────┘
\`\`\`

---

## Component Deep Dives

EOF

# Write component sections
echo -e "$COMPONENT_SECTIONS" >> "$OUT"

# Cross-cutting concerns
cat >> "$OUT" << 'CROSSCUT'
## Cross-Cutting Concerns

### Security Model

- **All services bind to localhost** (`127.0.0.1`) — no direct external exposure.
- **Cloudflare Tunnel** provides HTTPS access to Heimdall with Cloudflare Access authentication.
- **Bearer token auth** on Munin (MCP) and Mimir (file server) — timing-safe comparison.
- **OAuth 2.1** available on Munin for third-party MCP clients (PKCE, refresh tokens).
- **Systemd sandboxing** on all services: `ProtectSystem=strict`, minimal `ReadWritePaths`.
- **DNS rebinding protection** on Mimir via allowed-hosts check.
- **Secret detection** in Munin — refuses to store values matching known secret patterns.

### Backup Strategy

- **Munin DB**: `munin-backup.service` + `munin-backup.timer` → NAS via rsync.
- **Git repos**: All pushed to GitHub (private repos under `magnusgille` org).
- **Heimdall DB**: Local SQLite, daily maintenance aggregation reduces size.
- **NAS**: Primary artifact storage, syncs to laptop via Tailscale.

### Deployment Patterns

- **Git push → auto-deploy**: Heimdall uses `heimdall-deploy.path` (systemd path watcher) — push triggers rebuild + restart.
- **Manual deploy**: Other services require `sudo systemctl restart <service>` after git pull + build.
- **Build**: All TypeScript services use `npm run build` (tsc) → `dist/` directory.
- **Heimdall**: CommonJS, no build step — runs directly from `src/`.

### Technology Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Runtime | Node.js 20-22 | ARM64 on Raspberry Pi 5 |
| Language | TypeScript (strict) | Heimdall is CommonJS/JS |
| Database | SQLite (better-sqlite3) | FTS5 + sqlite-vec for Munin |
| Protocol | MCP (JSON-RPC 2.0) | stdio + HTTP transports |
| Web | Express / Fastify | Minimal, no heavy frameworks |
| Bot | grammy (Telegram) | Long-polling mode |
| Scheduling | systemd timers | No cron, no external scheduler |
| Auth | Bearer tokens, OAuth 2.1 | Cloudflare Access for external |

### Debate/Review Process

All significant architectural decisions are debated and documented in Munin under `debates/*` namespace. Format: problem statement → options → decision → rationale.

### GitHub Ownership

All repositories under the `magnusgille` GitHub account (private). Repos:
- `munin-memory`, `hugin`, `heimdall`, `skuld`, `ratatoskr`, `noxctl`, `mimir`, `grimnir`

CROSSCUT

# Deployment snapshot
cat >> "$OUT" << EOF

---

## Current Deployment Snapshot

> Captured at $TIMESTAMP on $HOSTNAME_VAL

### Service Status

| Unit | State | Enabled | PID | Memory | Started |
|------|-------|---------|-----|--------|---------|
$(echo -e "$DEPLOYMENT_TABLE")

### Repository Versions

| Repo | Branch | Last Commit |
|------|--------|-------------|
$(echo -e "$GIT_VERSIONS")

EOF

# Health check
cat >> "$OUT" << 'HEALTH_HEADER'
### Health Checks

HEALTH_HEADER

for comp in "${COMPONENTS[@]}"; do
  port="${PORTS[$comp]:-}"
  if [[ -n "$port" ]]; then
    health_url="http://localhost:$port/health"
    # Try /health then /api/health
    status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$health_url" 2>/dev/null || echo '000')"
    if [[ "$status" == "000" ]] || [[ "$status" == "404" ]]; then
      health_url="http://localhost:$port/api/health"
      status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$health_url" 2>/dev/null || echo '000')"
    fi
    if [[ "$status" == "200" ]]; then
      echo "- ✅ **$comp** (:$port) — HTTP $status" >> "$OUT"
    elif [[ "$status" == "000" ]]; then
      echo "- ❌ **$comp** (:$port) — unreachable" >> "$OUT"
    else
      echo "- ⚠️ **$comp** (:$port) — HTTP $status" >> "$OUT"
    fi
  fi
done

echo "" >> "$OUT"

# Munin project statuses / Roadmap
if [[ -n "$MUNIN_STATUSES" ]]; then
  cat >> "$OUT" << EOF
---

## Project Statuses (from Munin)

$(echo -e "$MUNIN_STATUSES")
EOF
fi

# Roadmap section — query all project next steps
cat >> "$OUT" << 'ROADMAP_HEADER'

---

## Roadmap

> Assembled from project statuses in Munin. See individual project entries for details.

ROADMAP_HEADER

# Query all projects namespace for roadmap items
roadmap_result="$(munin_tool_call "memory_query" "{\"namespace\":\"projects\",\"query\":\"next steps roadmap planned\",\"limit\":20}" 2>/dev/null || echo "")"
if [[ -n "$roadmap_result" ]]; then
  echo "$roadmap_result" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const entries = JSON.parse(d?.result?.content?.[0]?.text || '{}')?.entries || [];
    entries.forEach(e => {
      console.log('### ' + e.namespace + '/' + e.key);
      console.log('');
      // Extract next steps lines
      const lines = (e.content || '').split('\n');
      const nextIdx = lines.findIndex(l => /next|roadmap|planned|todo/i.test(l));
      if (nextIdx >= 0) {
        lines.slice(nextIdx, nextIdx + 10).forEach(l => console.log(l));
      } else {
        console.log(lines.slice(0, 5).join('\n'));
      }
      console.log('');
    });
  " >> "$OUT" 2>/dev/null || echo "*Could not parse roadmap from Munin.*" >> "$OUT"
else
  echo "*Munin query unavailable — run with --munin-token to include roadmap data.*" >> "$OUT"
fi

echo "" >> "$OUT"

# Appendix: Full dependency tree
cat >> "$OUT" << 'DEPS_HEADER'

---

## Appendix: Full Dependency Tree

> Combined and deduplicated across all component `package.json` files.

DEPS_HEADER

# Collect all deps
node -e "
  const fs = require('fs');
  const path = require('path');
  const repos = '$REPOS_DIR';
  const components = '${COMPONENTS[*]}'.split(' ');
  const allDeps = {};
  const allDevDeps = {};
  for (const comp of components) {
    const pkgPath = path.join(repos, comp, 'package.json');
    if (!fs.existsSync(pkgPath)) continue;
    const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    for (const [k,v] of Object.entries(pkg.dependencies || {})) {
      if (!allDeps[k]) allDeps[k] = {};
      allDeps[k][comp] = v;
    }
    for (const [k,v] of Object.entries(pkg.devDependencies || {})) {
      if (!allDevDeps[k]) allDevDeps[k] = {};
      allDevDeps[k][comp] = v;
    }
  }
  console.log('### Production Dependencies\n');
  console.log('| Package | Version(s) | Used By |');
  console.log('|---------|-----------|---------|');
  for (const [k, usedBy] of Object.entries(allDeps).sort((a,b) => a[0].localeCompare(b[0]))) {
    const versions = [...new Set(Object.values(usedBy))].join(', ');
    const users = Object.keys(usedBy).join(', ');
    console.log('| \`' + k + '\` | ' + versions + ' | ' + users + ' |');
  }
  console.log('');
  console.log('### Dev Dependencies\n');
  console.log('| Package | Version(s) | Used By |');
  console.log('|---------|-----------|---------|');
  for (const [k, usedBy] of Object.entries(allDevDeps).sort((a,b) => a[0].localeCompare(b[0]))) {
    const versions = [...new Set(Object.values(usedBy))].join(', ');
    const users = Object.keys(usedBy).join(', ');
    console.log('| \`' + k + '\` | ' + versions + ' | ' + users + ' |');
  }
" >> "$OUT" 2>/dev/null || echo "*Could not parse dependency tree.*" >> "$OUT"

# Footer
cat >> "$OUT" << EOF

---

*Generated at $TIMESTAMP on \`$HOSTNAME_VAL\` by \`scripts/generate-architecture.sh\`*
*Source hash: \`${SOURCE_HASH:0:16}\` — regenerate if stale.*
EOF

echo ""
echo "✅ Architecture document generated: $OUT"
echo "   Size: $(wc -l < "$OUT") lines, $(wc -c < "$OUT" | xargs) bytes"

# Verify no secrets leaked
SECRET_CHECK="$(grep -iE '(Bearer [a-f0-9]{10,}|sk-[a-zA-Z0-9]{20,}|[a-f0-9]{32,})' "$OUT" | grep -v '***' | grep -v 'sha256\|Source hash\|SOURCE_HASH' || true)"
if [[ -n "$SECRET_CHECK" ]]; then
  echo "⚠️  WARNING: Possible secret detected in output! Review before committing:"
  echo "$SECRET_CHECK"
else
  echo "   ✅ No secrets detected in output"
fi
