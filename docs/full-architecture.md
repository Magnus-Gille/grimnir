# Grimnir System — Complete Architecture & Implementation Reference

> Auto-generated on 2026-03-25T13:48:10Z by `scripts/generate-architecture.sh`
> Host: `huginmunin` | Source hash: `66256e8bfe9115a9`

---

## How to Read This Document

This document is **designed for AI agent consumption**. It is auto-generated from live data across all Grimnir component repositories, Munin memory, systemd service states, and environment configurations.

- Each component section is **self-contained** — you can read any section in isolation.
- Cross-references are explicit (e.g., "Hugin polls Munin" not "the dispatcher polls the memory server").
- Environment variable names are listed but **values are never included** — they are masked as `***`.
- The "Current Deployment Snapshot" section reflects the state at generation time and may be stale.
- To regenerate: `cd ~/repos/grimnir && ./scripts/generate-architecture.sh`

---

## Executive Summary

**Grimnir** is a personal AI infrastructure system running on a Raspberry Pi 5 cluster (2 nodes). It provides persistent memory, task dispatch, monitoring, daily briefings, Telegram-based mobile interaction, accounting integration, and file serving — all orchestrated through the MCP protocol and Munin memory server.

- **14** active project status entries in Munin
- **7** component repositories
- **8** systemd service units tracked

---

## System Topology

### Hardware

| Node | Hostname | Role | Specs |
|------|----------|------|-------|
| Pi 1 | huginmunin | Primary compute | Raspberry Pi 5, 8GB RAM, ARM64 |
| Pi 2 | NAS (100.99.119.52) | Storage + mimir | Raspberry Pi, file server |

### Network Model

All services bind to `127.0.0.1` (localhost only). External access is via **Cloudflare Tunnel** (Heimdall dashboard) or **Tailscale** (inter-node, laptop access).

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

```
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
```

---

## Component Deep Dives

### munin-memory

- **Role:** Persistent memory & knowledge graph (MCP server + HTTP API)
- **Package:** `munin-memory` v0.1.0
- **Port:** 3030
- **Description:** MCP server providing persistent memory for Claude across conversations

#### Overview (from README)

Persistent memory for AI assistants, self-hosted and provider-portable.
Named after Munin, one of Odin's two ravens — the one responsible for memory.
## Why
AI assistants forget everything between conversations. The context you build up — project decisions, personal preferences, how your systems work — evaporates when the session ends.
Some providers offer built-in memory features, but that context lives on their servers, in their format, under their control. If you switch providers, or they change their terms, or they shut down — your accumulated context goes with them.

#### Architecture Notes (CLAUDE.md)

<details>
<summary>Click to expand CLAUDE.md</summary>

# Munin Memory — CLAUDE.md

## What this project is

Munin Memory is an MCP (Model Context Protocol) server that provides persistent memory for Claude across conversations. Named after Odin's raven of memory. Built **for Claude, by Claude** — Claude is the primary "user" of the tools this server exposes.

Part of the Hugin & Munin personal AI system. See `prd.md` for full product context and `technical-spec.md` for implementation details.

## Architecture overview

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Database:** SQLite via `better-sqlite3` with FTS5 full-text search + sqlite-vec vector search
- **Protocol:** MCP over stdio (local) or stateless Streamable HTTP (network, Express-based)
- **Auth:** Dual auth — legacy Bearer token (MUNIN_API_KEY) + OAuth 2.1 (dynamic client registration, PKCE)
- **Platforms:** macOS (dev), Linux ARM64 (Raspberry Pi 5 target)

### Core concepts

- **State entries** — mutable key-value pairs (namespace + key). Represent current truth. Upserted on write.
- **Log entries** — append-only, timestamped, no key. Represent chronological history. Never modified.
- **Namespaces** — hierarchical strings with `/` separator (e.g. `projects/hugin-munin`). Created implicitly.
- **FTS5 search** — keyword search across all entries (lexical mode).
- **Vector search** — sqlite-vec KNN over 384-dim embeddings from Transformers.js (semantic mode).
- **Hybrid search** — Reciprocal Rank Fusion (RRF) of FTS5 + vector results.

### MCP tools exposed

| Tool | Purpose |
|------|---------|
| `memory_orient` | **Start here.** Returns conventions, computed project dashboard (grouped by lifecycle), curated notes, maintenance suggestions, and namespace overview in one call |
| `memory_write` | Store/update a state entry (namespace + key + content). Supports compare-and-swap via `expected_updated_at` for tracked statuses. Auto-canonicalizes lifecycle tags. |
| `memory_read` | Retrieve a specific state entry by namespace + key |
| `memory_get` | Retrieve any entry (state or log) by UUID |
| `memory_query` | Search memories (lexical/semantic/hybrid) with filters |
| `memory_log` | Append a chronological log entry to a namespace |
| `memory_list` | Browse namespaces and their contents (with recent log previews and demo filtering) |
| `memory_delete` | Delete entries (with token-based confirmation) |

## Project structure

```
munin-memory/
├── package.json
├── tsconfig.json
├── CLAUDE.md              # This file
├── prd.md                 # Product requirements (reference)
├── technical-spec.md      # Technical spec (reference)
├── src/
│   ├── index.ts           # Entry point — MCP server setup, stdio + Express HTTP transports
│   ├── db.ts              # SQLite init, pragmas, queries, vec operations
│   ├── migrations.ts      # Migration framework + migration definitions (v1-v3)
│   ├── embeddings.ts      # Embedding pipeline, background worker, feature flags
│   ├── oauth.ts           # OAuth 2.1 provider (OAuthServerProvider impl, SQLite-backed)
│   ├── consent.ts         # Minimal HTML consent page for OAuth authorization
│   ├── tools.ts           # MCP tool definitions and handlers
│   ├── security.ts        # Secret pattern detection + input validation
│   └── types.ts           # TypeScript type definitions
├── tests/
│   ├── db.test.ts
│   ├── embeddings.test.ts
│   ├── migrations.test.ts
│   ├── http-hardening.test.ts
│   ├── http-transport.test.ts   # Stateless HTTP route tests
│   ├── oauth.test.ts              # OAuth provider unit tests
│   ├── oauth-integration.test.ts  # OAuth end-to-end tests (supertest)
│   ├── tools.test.ts
│   └── security.test.ts
├── docs/
│   └── agentic-dev-days-munin-memory.md   # Presentation case study for the stateless HTTP incident
├── munin-memory.service   # systemd unit file for RPi deployment
├── scripts/
│   ├── deploy-rpi.sh      # Deploy to Raspberry Pi
│   └── migrate-db.sh      # One-time DB migration to Pi
└── dist/                  # Compiled output (gitignored)
```

## How to build

```bash
npm install
npm run build    # Compiles TypeScript to dist/
```

## How to test

```bash
npm test         # Runs vitest (single run)
npm run test:watch  # Runs vitest in watch mode
```

## How to run locally

**Stdio mode** (default — for Claude Code, Claude Desktop local):
```bash
node dist/index.js
```

**HTTP mode** (for network access — RPi deployment, remote clients):
```bash
MUNIN_TRANSPORT=http MUNIN_API_KEY=<key> node dist/index.js
```

Development with auto-reload:
```bash
npm run dev      # tsx watch src/index.ts
```

## Deployment to Raspberry Pi

```bash
# First deploy (set DEPLOY_USER if your Pi username differs from local)
./scripts/deploy-rpi.sh <your-pi-hostname>

# One-time database migration
./scripts/migrate-db.sh <your-pi-hostname>
```

The Pi needs a `.env` file at the project root:
```
MUNIN_API_KEY=<generate with: openssl rand -hex 32>
MUNIN_OAUTH_ISSUER_URL=https://<your-domain>
MUNIN_ALLOWED_HOSTS=<your-domain>,<your-domain>:443
```

## MCP client configuration

**Claude Code (HTTP — connecting to remote server):**
```bash
claude mcp add --transport http \
  -H "Authorization: Bearer <MUNIN_API_KEY>" \
  -s user munin-memory https://<your-domain>/mcp
```

If using Cloudflare Access, add `-H "CF-Access-Client-Id: <ID>"` and `-H "CF-Access-Client-Secret: <SECRET>"` headers.

**Claude Desktop (HTTP — via mcp-remote bridge):**
Uses `mcp-remote` bridge with Bearer + any reverse proxy auth headers.

**Claude.ai / Claude Mobile (OAuth — via Settings > Connectors):**
URL: `https://<your-domain>/mcp` — OAuth 2.1 flow handles auth automatically.
Requires reverse proxy path policies for OAuth endpoints and trusted consent-header configuration (see OAuth section below).

**Claude Code (stdio — local dev only):**
```bash
claude mcp add-json munin-memory '{"command":"node","args":["/path/to/munin-memory/dist/index.js"]}' -s user
```

## Computed dashboard and tracked statuses

The project dashboard in `memory_orient` is computed dynamically from status entries, replacing the manually-maintained `meta/workbench`.

### Tracked namespaces
Namespaces matching `projects/*` or `clients/*` are "tracked". Status entries (`key = "status"`) in these namespaces feed the computed dashboard.

### Lifecycle tags
Canonical lifecycle tags: `active`, `blocked`, `completed`, `stopped`, `maintenance`, `archived`. Aliases are auto-normalized on write: `done` → `completed`, `paused` → `stopped`, `inactive` → `archived`.

### Compare-and-swap (CAS)
`memory_write` accepts an optional `expected_updated_at` parameter. For tracked status writes, if the entry was modified since the given timestamp, the write returns `status: "conflict"` instead of overwriting. This prevents blind overwrites from concurrent environments.

### Curated overlay
`meta/workbench-notes` is a freeform entry for items not backed by namespaces (obligations, cross-cutting notes). Read by `memory_orient` as a `notes` field alongside the computed dashboard.

### Maintenance suggestions
`memory_orient` returns `maintenance_needed` when it detects: active-but-stale entries (>14 days), tracked namespaces missing a status key, conflicting lifecycle tags, or missing lifecycle tags.

### Legacy workbench
During the transition period, `memory_orient` includes `legacy_workbench` if `meta/workbench` exists, with a deprecation note. Delete `meta/workbench` when the transition is complete.

### Recognized namespace patterns

| Pattern | Tracked (dashboard) | Purpose |
|---------|:-------------------:|---------|
| `projects/<name>` | Yes | Project state and logs |
| `clients/<name>` | Yes | Client engagement context |
| `people/<name>` | No | People profiles, contact context |
| `decisions/<topic>` | No | Cross-cutting decisions |
| `meta/<topic>` | No | System notes, conventions |
| `documents/<slug>` | No | Indexed artifacts (summaries + Mímir references) |
| `reading/<slug>` | No | Reading queue and completed reads |
| `signals/<source>` | No | Hugin tracking state per source |
| `digests/<period>` | No | Compiled signal digests |

### Document entry convention

Entries in `documents/*` follow this structure for indexed artifacts:

- **Source:** Mímir URL (`https://mimir.gille.ai/files/<path>`)
- **Local:** Laptop path (`~/mgc/<path>`)
- **Type:** PDF | HTML | Markdown | Image
- **Size, Date, SHA-256** for integrity checking
- **Summary:** 2-5 sentences (no AI summarization for private/client docs)
- **Key Points:** Extracted insights
- **Extracted Text:** First ~10,000 characters (truncated for content limit)

Tags should use the prefixed convention below.

### Prefixed tag convention

Tags support colon-separated prefixes for cross-referencing:

| Prefix | Example | Purpose |
|--------|---------|---------|
| `client:<name>` | `client:lofalk` | Links to a client |
| `person:<name>` | `person:sara` | Links to a person |
| `topic:<topic>` | `topic:ai-education` | Subject categorization |
| `type:<artifact>` | `type:pdf`, `type:meeting-notes` | Document/artifact type |
| `source:external` | `source:external` | Content from outside (Hugin-ingested) |
| `source:internal` | `source:internal` | Internally produced content |

Unprefixed tags remain valid for lifecycle (`active`, `blocked`, etc.) and category (`decision`, `architecture`, etc.) use.

## Key design decisions

- SQLite + FTS5 + sqlite-vec for storage, keyword search, and vector search
- `better-sqlite3` for synchronous database access (simpler with MCP stdio model)
- All writes validated against secret patterns before storage (API keys, tokens, passwords rejected)
- State entries (mutable) and log entries (append-only) are the two fundamental types
- Namespaces are hierarchical strings separated by `/`
- Database location configurable via `MUNIN_MEMORY_DB_PATH` env var (default: `~/.munin-memory/memory.db`)
- Database file created with `0600` permissions
- **Dual auth:** Bearer token (MUNIN_API_KEY) for existing clients + OAuth 2.1 for web/mobile
- HTTP transport uses Express (required by MCP SDK's `mcpAuthRouter`)
- `/mcp` runs in stateless Streamable HTTP mode: fresh transport and fresh MCP `Server` per POST request
- `agent_id` field included in schema for future multi-agent support

## Semantic search architecture (Feature 2)

### Overview

Embedding pipeline runs asynchronously: writes are never blocked by embedding generation. A background worker processes entries with `embedding_status = 'pending'` in batches.

### Data flow

1. `memory_write` / `memory_log` → entry stored with `embedding_status = 'pending'`
2. Background worker claims pending entries → generates embeddings via Transformers.js → stores in `entries_vec` vec0 table
3. `memory_query` with `search_mode: "semantic"` → generates query embedding → KNN search via sqlite-vec
4. `memory_query` with `search_mode: "hybrid"` → runs both FTS5 and KNN, merges via RRF (k=60)

### Schema

- **Migration v2** adds `embedding_status` (CHECK: pending/processing/generated/failed) and `embedding_model` columns to `entries`
- **`entries_vec`** vec0 virtual table created idempotently on startup (NOT in migration — requires sqlite-vec extension loaded). Schema: `entry_id TEXT, embedding float[384]`
- No SQL trigger for vec cleanup — done in application code during `executeDelete`

### Three-tier feature gates

| Gate | Env var | Default | Controls |
|------|---------|---------|----------|
| Infra | `MUNIN_EMBEDDINGS_ENABLED` | `true` | Load model, run worker |
| Gate 1 | `MUNIN_SEMANTIC_ENABLED` | `true` | Accept `search_mode: "semantic"` |
| Gate 2 | `MUNIN_HYBRID_ENABLED` | `false` | Accept `search_mode: "hybrid"` |

When a requested mode is unavailable, `memory_query` degrades to lexical search with a `warning` and `search_mode_actual` in the response.

### Circuit breaker

After `MUNIN_EMBEDDINGS_MAX_FAILURES` (default 5) consecutive embedding failures, the circuit breaker trips: embedding generation is disabled, all search degrades to lexical. Reset requires server restart.

### Background worker

- Uses recursive `setTimeout` (not `setInterval`) to prevent overlap
- Claims rows atomically: `UPDATE ... SET embedding_status = 'processing' WHERE id IN (SELECT ... LIMIT batchSize)`
- Guards against stale writes: checks `updated_at` before persisting embeddings
- `stopEmbeddingWorker()` awaits in-flight batch before returning (graceful shutdown)

### Key implementation details (from Codex adversarial review)

- `embeddingToBuffer()`: uses `Buffer.from(f32.buffer, f32.byteOffset, f32.byteLength)` — NOT `Buffer.from(f32)` which silently truncates
- RRF scoring: entries in only one result set contribute `1/(60 + rank)` from that set + 0 from the other. No Infinity sentinel.
- Over-fetch 5x limit from each source for RRF (not 3x)
- Vec0 tables don't have an `id` column — use `entry_id TEXT` metadata column instead

## OAuth 2.1 (Feature 3)

### Overview

OAuth 2.1 support enables Claude.ai and Claude mobile to connect to Munin Memory. Uses the MCP SDK's built-in `mcpAuthRouter()` and `requireBearerAuth()` middleware backed by a SQLite OAuth provider.

### Dual auth on `/mcp`

The `verifyAccessToken()` method checks in order:
1. **Legacy Bearer token** — if token matches `MUNIN_API_KEY`, returns immediately (backward compat)
2. **OAuth access token** — looks up in `oauth_tokens` table

Existing Claude Code and Claude Desktop clients using `MUNIN_API_KEY` continue working unchanged.

### OAuth endpoints (served by MCP SDK auth router)

| Endpoint | Purpose |
|----------|---------|
| `/.well-known/oauth-authorization-server` | OAuth metadata discovery (RFC 8414) |
| `/.well-known/oauth-protected-resource` | Protected resource metadata (RFC 9728) |
| `/authorize` | Authorization + consent page |
| `/authorize/approve` | Consent form POST handler (custom) |
| `/token` | Code exchange + token refresh |
| `/register` | Dynamic client registration (RFC 7591) |
| `/revoke` | Token revocation (RFC 7009) |

### Schema (migration v3)

- **`oauth_clients`** — registered OAuth clients (client_id, secret, redirect_uris, metadata)
- **`oauth_auth_codes`** — authorization codes (code, client_id, PKCE challenge, expiry)
- **`oauth_tokens`** — access + refresh tokens (token, type, client_id, scopes, expiry, revoked)

### Token lifecycle

- Access tokens: configurable TTL (default 1 hour), checked on every request
- Refresh tokens: configurable TTL (default 30 days), rotation on use (old token revoked)
- Auth codes: 10-minute TTL, single use
- Access tokens, refresh tokens, and auth codes are stored hashed at rest
- Cleanup: expired auth codes and expired/revoked tokens swept on a periodic cleanup timer (60s)

### Reverse proxy path policies

If using a reverse proxy (e.g. Cloudflare Access, nginx), configure path-based auth:
- `/.well-known/*`, `/token`, `/register`, `/health` — public (metadata, server-to-server)
- `/authorize`, `/authorize/approve` — user authentication (browser consent flow)
- `/mcp` — API authentication (Bearer token or OAuth)

For public issuers, the server now fails closed unless both of these are set:
- `MUNIN_OAUTH_TRUSTED_USER_HEADER`
- `MUNIN_OAUTH_TRUSTED_USER_VALUE`

The consent endpoints only proceed when that header/value pair is present, or when the request is loopback-local and `MUNIN_OAUTH_ALLOW_LOCALHOST_CONSENT=true` for development.

### Key files

- `src/oauth.ts` — `MuninOAuthProvider` (implements `OAuthServerProvider`), `MuninClientsStore`
- `src/consent.ts` — Self-contained HTML consent page
- `src/index.ts` — Express app setup, mounts `mcpAuthRouter()` + `requireBearerAuth()`
- `src/migrations.ts` — Migration v3 creates OAuth tables

## Code style

- TypeScript strict mode
- No classes unless genuinely needed — prefer functions and modules
- Error messages must be clear and actionable for an LLM reading them
- Keep dependencies minimal
- No ORMs, no frameworks

## Security rules

Content is scanned before every write. Reject writes containing:
- API keys (`sk-`, `ghp_`, `gho_`, `github_pat_`, `AKIA...`)
- Bearer tokens
- Private keys / certificates
- Inline passwords/secrets

See `technical-spec.md` § Security Module for the full pattern list.

## Input validation

- `namespace`: must match `/^[a-zA-Z0-9][a-zA-Z0-9/_-]*$/`
- `key`: must match `/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/`
- `content`: max 100,000 characters
- `tags`: each tag matches `/^[a-zA-Z0-9][a-zA-Z0-9_:-]*$/`, max 20 tags. Colons enable prefixed tags (e.g. `client:lofalk`, `topic:ai-education`).

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MUNIN_MEMORY_DB_PATH` | `~/.munin-memory/memory.db` | Database file location |
| `MUNIN_MEMORY_LOG_LEVEL` | `info` | Log level (debug/info/warn/error) |
| `MUNIN_MEMORY_MAX_CONTENT_SIZE` | `100000` | Max content size in characters |
| `MUNIN_TRANSPORT` | `stdio` | Transport mode: `stdio` or `http` |
| `MUNIN_HTTP_PORT` | `3030` | HTTP server port (http mode only) |
| `MUNIN_HTTP_HOST` | `127.0.0.1` | HTTP bind address (http mode only) |
| `MUNIN_API_KEY` | — | Bearer token for auth (required in http mode) |
| `MUNIN_EMBEDDINGS_ENABLED` | `true` | Load embedding model + run worker |
| `MUNIN_SEMANTIC_ENABLED` | `true` | Gate 1: accept `search_mode: "semantic"` |
| `MUNIN_HYBRID_ENABLED` | `false` | Gate 2: accept `search_mode: "hybrid"` |
| `MUNIN_EMBEDDINGS_MODEL` | `Xenova/all-MiniLM-L6-v2` | HuggingFace model for embeddings |
| `MUNIN_EMBEDDINGS_BACKFILL` | `true` | Backfill existing entries on startup |
| `MUNIN_EMBEDDINGS_BATCH_SIZE` | `25` | Entries per worker batch |
| `MUNIN_EMBEDDINGS_BATCH_DELAY_MS` | `200` | Delay between worker batches |
| `MUNIN_EMBEDDINGS_MAX_FAILURES` | `5` | Circuit breaker failure threshold |
| `MUNIN_EMBEDDINGS_LOCAL_ONLY` | `false` | Only use cached models (no downloads) |
| `MUNIN_ALLOWED_HOSTS` | — | Comma-separated extra Host headers to accept (e.g. `your-domain.com:443,your-domain.com`) |
| `MUNIN_OAUTH_ISSUER_URL` | `http://localhost:3030` | OAuth issuer URL (set to your public domain in production) |
| `MUNIN_OAUTH_ACCESS_TOKEN_TTL` | `3600` | Access token lifetime (seconds) |
| `MUNIN_OAUTH_REFRESH_TOKEN_TTL` | `2592000` | Refresh token lifetime (30 days, seconds) |

## Spec amendments from adversarial review

A pre-implementation debate between Claude (Opus 4.6) and Codex (GPT-5.3) produced spec amendments. See `debate/resolution.md` for the full record. Key changes from the original `technical-spec.md`:

1. **UPSERT** uses `ON CONFLICT ... DO UPDATE`, not `INSERT OR REPLACE`
2. **All mutations** wrapped in a single `db.transaction()` (entries + audit_log)
3. **WAL mode** + `busy_timeout=5000` + `synchronous=NORMAL` set at DB init
4. **Composite indexes** replace the useless tags index: `(namespace, entry_type, key)` and `(namespace, entry_type, created_at DESC)`
5. **CHECK constraints** enforce state→key NOT NULL, log→key NULL, and `json_type(tags)='array'`
6. **Timestamps** always UTC ISO 8601 via single `nowUTC()` function
7. **FTS rebuild** function included in `db.ts` (not just a comment)
8. **New tool `memory_get`** for fetching full entries by ID
9. **Delete uses token-based confirmation** instead of simple boolean
10. **LIKE queries** escape `_` and `%` wildcards in namespace prefix search
11. **Tag filtering** applied before `limit` in query results

When `technical-spec.md` and `debate/resolution.md` conflict, the resolution takes precedence.

## Important constraints

- The spec files (`prd.md`, `technical-spec.md`) are the source of truth, **amended by `debate/resolution.md`**.
- v1 is local-only, single-user. Multi-agent auth and encryption are v2 concerns.
- Semantic search (sqlite-vec + Transformers.js) available via `memory_query` with `search_mode` parameter. Three-tier gating: infra + semantic gate + hybrid gate.
- No memory decay or scoring — everything persists until explicitly deleted.
- The design must not preclude future deployment on Raspberry Pi 5 (ARM64).

</details>

#### API Surface

- `GET /health`
- `POST /authorize/approve`
- `POST /mcp`

#### Dependencies

- `@huggingface/transformers` ^3.8.1
- `@modelcontextprotocol/sdk` ^1.12.1
- `@types/better-sqlite3` ^7.6.13
- `@types/express` ^5.0.6
- `@types/node` ^22.13.4
- `@types/supertest` ^6.0.3
- `@types/uuid` ^10.0.0
- `better-sqlite3` ^11.8.2
- `express` ^5.2.1
- `sqlite-vec` ^0.1.7-alpha.2
- `supertest` ^7.2.2
- `tsx` ^4.19.2
- `typescript` ^5.7.3
- `uuid` ^11.1.0
- `vitest` ^3.0.5

#### Configuration (env var names)

```
MUNIN_EMBEDDINGS_BACKFILL=***
MUNIN_EMBEDDINGS_BATCH_DELAY_MS=***
MUNIN_EMBEDDINGS_BATCH_SIZE=***
MUNIN_EMBEDDINGS_ENABLED=***
MUNIN_EMBEDDINGS_LOCAL_ONLY=***
MUNIN_EMBEDDINGS_MAX_FAILURES=***
MUNIN_EMBEDDINGS_MODEL=***
MUNIN_HTTP_HOST=***
MUNIN_HTTP_PORT=***
MUNIN_HYBRID_ENABLED=***
MUNIN_MEMORY_DB_PATH=***
MUNIN_MEMORY_LOG_LEVEL=***
MUNIN_MEMORY_MAX_CONTENT_SIZE=***
MUNIN_OAUTH_ACCESS_TOKEN_TTL=***
MUNIN_OAUTH_ALLOW_LOCALHOST_CONSENT=***
MUNIN_OAUTH_ISSUER_URL=***
MUNIN_OAUTH_REFRESH_TOKEN_TTL=***
MUNIN_SEMANTIC_ENABLED=***
MUNIN_SESSION_IDLE_TTL_MS=***
MUNIN_TRANSPORT=***
```

#### Systemd Units

`munin-memory.service`:
```ini
# NOTE: Replace <user> and <install-dir> with your system username and
# install location before installing this service file.
[Unit]
Description=Munin Memory MCP Server
After=network.target

[Service]
Type=simple
User=<user>
WorkingDirectory=/home/<user>/<install-dir>
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=5
Environment=MUNIN_TRANSPORT=http
Environment=MUNIN_HTTP_PORT=3030
Environment=MUNIN_HTTP_HOST=127.0.0.1
EnvironmentFile=/home/<user>/<install-dir>/.env

# Sandboxing
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/<user>/.munin-memory
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

#### Key Source Files

- `src/consent.ts` (112 lines)
- `src/oauth.ts` (554 lines)
- `src/index.ts` (619 lines)
- `src/types.ts` (240 lines)
- `src/migrations.ts` (206 lines)
- `src/tools.ts` (977 lines)
- `src/bridge.ts` (394 lines)
- `src/embeddings.ts` (240 lines)
- `src/db.ts` (646 lines)
- `src/security.ts` (129 lines)

#### Current Commit

`01d8153cf2b44aaca7d87c2e1a685454d2761c0f docs: add health, scalability & OSS readiness debate summary (2026-03-23 11:45:26 +0100)`

---

### hugin

- **Role:** Task dispatcher — polls Munin for tasks, spawns AI runtimes, reports results
- **Package:** `hugin` v0.1.0
- **Port:** 3035
- **Description:** Task dispatcher for the Grimnir AI system — polls Munin for tasks, spawns AI runtimes, reports results

#### Overview (from README)

Task dispatcher for the [Grimnir](https://github.com/Magnus-Gille/grimnir) personal AI system. Named after Odin's raven of thought.
Polls [Munin](https://github.com/magnusgille/munin-memory) for pending tasks, spawns AI runtimes to execute them, and writes results back. Submit tasks from any Claude environment (Desktop, Web, Mobile, Code) — Hugin picks them up and runs them on the Pi.
## Quick start
```bash
npm install

#### Architecture Notes (CLAUDE.md)

<details>
<summary>Click to expand CLAUDE.md</summary>

# Hugin — CLAUDE.md

## What this project is

Hugin is a task dispatcher for the Grimnir personal AI system. Named after one of Odin's ravens (thought). Polls Munin for pending tasks, spawns AI runtimes (Claude Code, Codex) to execute them, and writes results back.

Part of the Grimnir system: **Munin** (memory/brain), **Mímir** (file archive), **Hugin** (task dispatcher).

## Architecture

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Framework:** Express (health endpoint only)
- **Deployment:** Hugin-Munin Pi (huginmunin.local), systemd
- **Integration:** Munin HTTP API at localhost:3030

### How it works

1. Polls Munin every 30s for entries in `tasks/` namespace with tag `pending`
2. Claims a task (updates tags to `running` with compare-and-swap)
3. Executes via the configured runtime:
   - `claude` (default): Agent SDK `query()` for structured results (or legacy `claude -p` spawn via `HUGIN_CLAUDE_EXECUTOR=spawn`)
   - `codex`: `codex exec --full-auto` spawn
4. Captures output (SDK message events or stdout/stderr) + streams to per-task log file
5. Writes result back to Munin, updates tags to `completed` or `failed`
6. Emits heartbeat to `tasks/_heartbeat` after each poll cycle
7. One task at a time — no parallelism

### Task schema

Submit a task by writing to Munin from any environment:

```
Namespace: tasks/<task-id>   (e.g. tasks/20260314-100000-a3f1)
Key: status
Tags: ["pending", "runtime:claude"]
```

Content format:
```markdown
## Task: <title>

- **Runtime:** claude
- **Context:** repo:heimdall
- **Working dir:** /home/magnus/workspace
- **Timeout:** 300000
- **Submitted by:** claude-desktop
- **Submitted at:** 2026-03-14T10:00:00Z
- **Reply-to:** telegram:12345678
- **Reply-format:** summary
- **Group:** batch-20260323
- **Sequence:** 1

### Prompt
<the actual prompt for the AI runtime>
```

**Context resolution:** `Context:` takes priority over `Working dir:` for determining the working directory. Supported aliases:
- `repo:<name>` → `/home/magnus/repos/<name>`
- `scratch` → `/home/magnus/scratch` (non-code tasks)
- `files` → `/home/magnus/mimir`
- Raw absolute paths are passed through unchanged

**Reply routing:** `Reply-to:` and `Reply-format:` are forwarded in the result for downstream consumers (e.g., Ratatoskr).

**Task groups:** `Group:` and `Sequence:` enable multi-step task orchestration. Both are forwarded in results and heartbeats.

**Type tags:** Tags matching `type:*` (e.g., `type:research`, `type:email`) are carried forward through the task lifecycle (pending → running → completed/failed).

Results are written to the same namespace under key `result`.

## Project structure

```
hugin/
├── package.json
├── tsconfig.json
├── CLAUDE.md
├── hugin.service
├── src/
│   ├── index.ts           # Dispatcher: poll loop, task execution, health endpoint
│   ├── sdk-executor.ts    # Agent SDK executor (query() based, default for claude runtime)
│   └── munin-client.ts    # HTTP client for Munin JSON-RPC API
├── tests/
│   ├── dispatcher.test.ts
│   └── sdk-executor.test.ts
└── scripts/
    ├── deploy-pi.sh
    ├── sync-claude-config.sh  # Sync ~/.claude/ config to Pi
    └── update-cli.sh          # Auto-update CLI tools (daily cron)
```

## How to build

```bash
npm install
npm run build
```

## How to test

```bash
npm test
```

## How to run locally

```bash
MUNIN_API_KEY=<key> MUNIN_URL=http://localhost:3030 npm run dev
```

## Deployment

```bash
./scripts/deploy-pi.sh [hostname]
```

Default host: `huginmunin.local` (or Tailscale IP `100.97.117.37` if mDNS unavailable).

The Pi needs a `.env` file at `/home/magnus/hugin/.env`:
```
MUNIN_API_KEY=<same key Munin uses>
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HUGIN_PORT` | `3032` | Health endpoint port |
| `HUGIN_HOST` | `127.0.0.1` | Bind address |
| `MUNIN_URL` | `http://localhost:3030` | Munin HTTP endpoint |
| `MUNIN_API_KEY` | — | Bearer token for Munin (required) |
| `HUGIN_POLL_INTERVAL_MS` | `30000` | Poll frequency (ms) |
| `HUGIN_DEFAULT_TIMEOUT_MS` | `300000` | Default task timeout (ms) |
| `HUGIN_WORKSPACE` | `/home/magnus/workspace` | Default working directory |
| `HUGIN_MAX_OUTPUT_CHARS` | `50000` | Max output chars to capture |
| `HUGIN_CLAUDE_EXECUTOR` | `sdk` | Claude executor: `sdk` (Agent SDK) or `spawn` (legacy CLI) |
| `NOTIFY_EMAIL` | — | Email recipient for task notifications (via Heimdall) |
| `HEIMDALL_URL` | `http://127.0.0.1:3033` | Heimdall HTTP endpoint |

</details>

#### API Surface

- `GET /health`

#### Dependencies

- `@anthropic-ai/claude-agent-sdk` ^0.2.81
- `@types/express` ^5.0.2
- `@types/node` ^22.15.3
- `express` ^5.1.0
- `tsx` ^4.19.4
- `typescript` ^5.8.3
- `vitest` ^3.1.2

#### Configuration (env var names)

```
MUNIN_API_KEY=***
NOTIFY_EMAIL=***
```

#### Systemd Units

`hugin.service`:
```ini
[Unit]
Description=Hugin Task Dispatcher
After=network-online.target munin-memory.service
Wants=network-online.target

[Service]
Type=simple
User=magnus
WorkingDirectory=/home/magnus/repos/hugin
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=10
EnvironmentFile=/home/magnus/repos/hugin/.env
Environment=PATH=/home/magnus/.npm-global/bin:/usr/local/bin:/usr/bin:/bin

# Sandboxing
ProtectSystem=strict
ReadWritePaths=/home/magnus /tmp
NoNewPrivileges=true
PrivateTmp=false

[Install]
WantedBy=multi-user.target
```

#### Key Source Files

- `src/index.ts` (804 lines)
- `src/sdk-executor.ts` (246 lines)
- `src/munin-client.ts` (159 lines)

#### Current Commit

`b0fa2b5f37aa14da7002dd741242d7f24688c03d feat: add Context field, reply routing, task groups, and type tags (2026-03-23 10:15:36 +0100)`

---

### heimdall

- **Role:** Monitoring dashboard for Raspberry Pi infrastructure
- **Package:** `heimdall` v1.0.0
- **Port:** 3033
- **Description:** Monitoring dashboard for a two-Raspberry-Pi infrastructure (huginmunin + NAS).

#### Overview (from README)

Monitoring dashboard for a two-Raspberry-Pi infrastructure (huginmunin + NAS).
**Status:** Architecture plan complete — implementation pending.
## What it will do
- System health monitoring (CPU temp, memory, load) for both Pis
- Backup freshness tracking (Time Machine, Munin Memory, Mímir)

#### API Surface

- `GET /`
- `GET /api/alerts`
- `GET /api/card/alerts`
- `GET /api/card/backups`
- `GET /api/card/change-summary`
- `GET /api/card/collector-health`
- `GET /api/card/deploy-status`
- `GET /api/card/deployments`
- `GET /api/card/events`
- `GET /api/card/hugin-tasks`
- `GET /api/card/last-updated`
- `GET /api/card/munin-stats`
- `GET /api/card/network-quality`
- `GET /api/card/overall-status`
- `GET /api/card/processes`
- `GET /api/card/projects-list`
- `GET /api/card/ram`
- `GET /api/card/skuld-briefing`
- `GET /api/card/system-health`
- `GET /api/card/tailscale`
- `GET /api/card/task-detail`
- `GET /api/card/task-history`
- `GET /api/card/tasks-list`
- `GET /api/card/temperature`
- `GET /api/events`
- `GET /api/events/search`
- `GET /api/health`
- `GET /api/metrics/:host/:metric`
- `GET /api/nas-state`
- `GET /api/status`
- `GET /api/summary`
- `GET /architecture`
- `GET /deployments`
- `GET /favicon.ico`
- `GET /projects`
- `GET /status`
- `GET /tasks`
- `POST /api/send-email`

#### Dependencies

- `@azure/msal-node` ^2.16.3
- `@fastify/rate-limit` ^10.3.0
- `better-sqlite3` ^12.8.0
- `fastify` ^5.8.2

#### Systemd Units

`heimdall-collect.service`:
```ini
[Unit]
Description=Heimdall metric collector
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=magnus
WorkingDirectory=/home/magnus/repos/heimdall
ExecStart=/usr/bin/node src/collector.js
Environment=NODE_ENV=production
Environment=DB_PATH=/home/magnus/.heimdall/heimdall.db
EnvironmentFile=-/home/magnus/.heimdall/env

# Sandboxing — collector needs SSH access and read access to Munin DB
ProtectSystem=strict
ReadWritePaths=/home/magnus/.heimdall
ReadOnlyPaths=/home/magnus/repos/heimdall /home/magnus/.munin-memory /home/magnus/.ssh/heimdall_ed25519
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
PrivateDevices=yes
RestrictNamespaces=yes
RestrictRealtime=yes
LockPersonality=yes
ProtectClock=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
SystemCallArchitectures=native
```

`heimdall-deploy.service`:
```ini
[Unit]
Description=Restart Heimdall after new commit

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart heimdall.service
```

`heimdall-maintain.service`:
```ini
[Unit]
Description=Heimdall daily maintenance (aggregation + cleanup)

[Service]
Type=oneshot
User=magnus
WorkingDirectory=/home/magnus/repos/heimdall
ExecStart=/usr/bin/node src/maintain.js
Environment=NODE_ENV=production
Environment=DB_PATH=/home/magnus/.heimdall/heimdall.db

# Sandboxing — maintenance only needs DB write access
ProtectSystem=strict
ReadWritePaths=/home/magnus/.heimdall
ReadOnlyPaths=/home/magnus/repos/heimdall
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
PrivateDevices=yes
MemoryDenyWriteExecute=yes
RestrictNamespaces=yes
RestrictRealtime=yes
LockPersonality=yes
ProtectClock=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
SystemCallArchitectures=native
```

`heimdall.service`:
```ini
[Unit]
Description=Heimdall Monitoring Dashboard
After=network.target

[Service]
Type=simple
User=magnus
WorkingDirectory=/home/magnus/repos/heimdall
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3033
Environment=DB_PATH=/home/magnus/.heimdall/heimdall.db
Environment=HEIMDALL_BIND=127.0.0.1

# Sandboxing
ProtectSystem=strict
ReadWritePaths=/home/magnus/.heimdall
ReadOnlyPaths=/home/magnus/repos/heimdall /home/magnus/.munin-memory
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
PrivateDevices=yes
MemoryDenyWriteExecute=yes
RestrictNamespaces=yes
RestrictRealtime=yes
LockPersonality=yes
ProtectClock=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
```

`heimdall-collect.timer`:
```ini
[Unit]
Description=Heimdall metric collection timer

[Timer]
OnCalendar=*:0/5
RandomizedDelaySec=30
Persistent=true

[Install]
WantedBy=timers.target
```

`heimdall-maintain.timer`:
```ini
[Unit]
Description=Heimdall daily maintenance timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

`heimdall-deploy.path`:
```ini
[Unit]
Description=Watch Heimdall repo for new commits

[Path]
PathModified=/home/magnus/repos/heimdall/.git/refs/heads/main

[Install]
WantedBy=multi-user.target
```

#### Key Source Files

- `src/charts.js` (83 lines)
- `src/server.js` (1090 lines)
- `src/munin-projects.js` (210 lines)
- `src/task-utils.js` (30 lines)
- `src/alerts.js` (77 lines)
- `src/html.js` (2039 lines)
- `src/microsoft-mcp.js` (40 lines)
- `src/nas-state.js` (66 lines)
- `src/email.js` (311 lines)
- `src/collector.js` (508 lines)
- `src/db.js` (303 lines)
- `src/maintain.js` (92 lines)
- `src/metrics.js` (467 lines)
- `src/hugin.js` (359 lines)
- `src/drift.js` (316 lines)
- `src/deployments.js` (523 lines)
- `src/munin-sync.js` (214 lines)
- `src/causality.js` (80 lines)
- `src/status.js` (155 lines)
- `src/mcp-probe.js` (132 lines)
- `src/events.js` (167 lines)

#### Current Commit

`bbaaeb6e3798fd512c6f8fe807511b72237dc417 feat: add deployments tab with full Pi audit (2026-03-25 14:41:14 +0100)`

---

### skuld

- **Role:** Daily intelligence briefings — synthesizes Munin memory + calendar + finances
- **Package:** `skuld` v0.1.0
- **Port:** 3040
- **Description:** The Daily Oracle — proactive intelligence briefings from the Grimnir ecosystem

#### Overview (from README)

> *Skuld is the youngest of the three Norns who tend the Well of Urd at the base of Yggdrasil. While Urd remembers what was and Verdandi watches what is, Skuld weaves what shall become. She doesn't predict the future — she prepares it.*
Skuld is a proactive daily intelligence briefing system. Every morning, it reads across data sources in the [Grimnir ecosystem](#the-grimnir-ecosystem) — Munin (memory), Google Calendar (ICS), and soon Fortnox (finances) — and synthesizes a narrative briefing via Claude API that tells you what your day looks like, what needs attention, and what's coming next.
The difference between a filing cabinet and a chief of staff is initiative. Skuld is the chief of staff.
## Example Output
```

#### Architecture Notes (CLAUDE.md)

<details>
<summary>Click to expand CLAUDE.md</summary>

# Skuld — Project Conventions

## What is this?
Skuld is a proactive daily intelligence briefing system. It reads from Munin (memory), calendar (ICS), and Fortnox (finances), synthesizes a narrative briefing via Claude API, and outputs it to CLI/Munin/web.

## Quick commands
```bash
npm run build        # tsc
npm run dev          # tsx src/index.ts
npm test             # vitest
npm run briefing     # generate today's briefing (requires ANTHROPIC_API_KEY)
npm run serve        # start web server on port 3040
```

## Stack
- TypeScript, Node.js 22+, ARM64 (Raspberry Pi)
- Vitest for tests
- Express for web UI
- @anthropic-ai/sdk for Claude API
- No bundler — tsx for dev, tsc for production

## Architecture
- `src/collectors/` — data source readers (calendar, munin, fortnox)
- `src/engine/` — context assembly and LLM synthesis
- `src/output/` — briefing output (munin writer, web server)
- `src/types.ts` — shared type definitions
- `src/config.ts` — configuration loader

## Environment variables
- `ANTHROPIC_API_KEY` — required for briefing generation
- `MUNIN_BASE_URL` — Munin HTTP API (default: http://localhost:3030)
- `MUNIN_API_KEY` — optional API key for remote Munin access
- `CALENDAR_ICS_URL` — Google Calendar ICS feed URL
- `SKULD_PORT` — web server port (default: 3040)

## Testing
- Unit tests mock external dependencies (Munin API, Claude API, ICS feeds)
- Fixtures in `test/fixtures/`
- Run `npm test` — all tests must pass before committing

## Munin integration
- Reads from: `projects/*/status`, `clients/*/status`, `rituals/weekly/current-plan`, recent logs
- Writes to: `briefings/daily/YYYY-MM-DD` with tag `briefing`

## Git conventions
- Conventional commits: `feat:`, `fix:`, `test:`, `docs:`, `chore:`
- Main branch: `main`

</details>

#### API Surface

- `GET /`
- `GET /api/briefing`
- `GET /health`

#### Dependencies

- `@anthropic-ai/sdk` ^0.39.0
- `@types/better-sqlite3` ^7.6.13
- `@types/express` ^5.0.0
- `@types/node` ^22.0.0
- `better-sqlite3` ^12.8.0
- `express` ^4.21.0
- `ical.js` ^2.1.0
- `tsx` ^4.19.0
- `typescript` ^5.7.0
- `vitest` ^3.0.0

#### Configuration (env var names)

```
ANTHROPIC_API_KEY=***
MUNIN_API_KEY=***
```

#### Systemd Units

`skuld.service`:
```ini
[Unit]
Description=Skuld Daily Briefing — generate today's intelligence briefing
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/home/magnus/repos/skuld
ExecStart=/usr/bin/node dist/index.js briefing
EnvironmentFile=/home/magnus/repos/skuld/.env

# Timeouts — briefing generation can take 30-60s
TimeoutStartSec=120

[Install]
WantedBy=default.target
```

`skuld.timer`:
```ini
[Unit]
Description=Skuld Daily Briefing Timer — trigger at 06:00 every morning

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
```

#### Key Source Files

- `src/output/web.ts` (209 lines)
- `src/output/munin-writer.ts` (44 lines)
- `src/index.ts` (302 lines)
- `src/commitments/extractor.ts` (176 lines)
- `src/commitments/store.ts` (137 lines)
- `src/types.ts` (90 lines)
- `src/collectors/fortnox.ts` (113 lines)
- `src/collectors/calendar.ts` (87 lines)
- `src/collectors/munin.ts` (206 lines)
- `src/config.ts` (14 lines)
- `src/engine/prompts.ts` (210 lines)
- `src/engine/synthesizer.ts` (58 lines)
- `src/engine/assembler.ts` (40 lines)

#### Current Commit

`48e026c7057f97dd3c4a7a2632750220145f1bf7 feat: add service identifier to /health endpoint for Heimdall drift tracking (2026-03-23 08:53:44 +0100)`

---

### ratatoskr

- **Role:** Telegram router and concierge for mobile task dispatch
- **Package:** `ratatoskr` v0.1.0
- **Port:** 3034
- **Description:** Telegram router and concierge for the Grimnir AI infrastructure

#### Architecture Notes (CLAUDE.md)

<details>
<summary>Click to expand CLAUDE.md</summary>

# Ratatoskr — CLAUDE.md

## What this project is

Ratatoskr is a Telegram router and concierge for the Grimnir personal AI system. Named after the squirrel that carries messages between the eagle and serpent on Yggdrasil. It lets Magnus interact with Grimnir from Telegram — sending tasks from a phone and receiving results back.

Part of the Grimnir system: **Munin** (memory), **Hugin** (task dispatcher), **Ratatoskr** (Telegram router).

## Architecture

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Framework:** Express (health endpoint only) + grammy (Telegram bot)
- **AI:** @anthropic-ai/sdk (Haiku for intent triage via concierge layer)
- **Deployment:** systemd on Pi 1 (huginmunin), port 3034
- **Telegram mode:** Long-polling (no webhook, no inbound HTTP)

### How it works

1. Telegram message arrives from allowlisted user
2. Concierge layer calls Claude Haiku with message + Munin context
3. Haiku decides: ready (submit task), clarify (ask user), or answer (reply directly)
4. If ready: task-writer formats Hugin task and writes to Munin
5. Result-poller monitors task completion and replies on Telegram

### Components

- `src/index.ts` — Express health endpoint + bot startup
- `src/bot.ts` — Telegram bot setup, message handler, allowlist
- `src/concierge.ts` — Intent triage via Claude Haiku API
- `src/task-writer.ts` — Format task markdown, write to Munin
- `src/result-poller.ts` — Poll Munin for task results, reply on Telegram
- `src/munin-client.ts` — HTTP client for Munin JSON-RPC API
- `src/config.ts` — Environment configuration

## How to build

```bash
npm install
npm run build
```

## How to test

```bash
npm test
```

## How to run locally

```bash
TELEGRAM_BOT_TOKEN=<token> TELEGRAM_ALLOWED_USERS=<user_id> MUNIN_API_KEY=<key> npm run dev
```

## Deployment

```bash
./scripts/deploy-pi.sh [hostname]
```

Default host: `huginmunin.local`.

The Pi needs a `.env` file at `/home/magnus/repos/ratatoskr/.env`:
```
TELEGRAM_BOT_TOKEN=<from BotFather>
TELEGRAM_ALLOWED_USERS=<magnus telegram user id>
ANTHROPIC_API_KEY=<for concierge Haiku calls>
MUNIN_API_KEY=<same key Munin/Hugin use>
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3034` | Health endpoint port |
| `HOST` | `127.0.0.1` | Bind address |
| `TELEGRAM_BOT_TOKEN` | — | Bot token from @BotFather (required) |
| `TELEGRAM_ALLOWED_USERS` | — | Comma-separated Telegram user IDs (required) |
| `ANTHROPIC_API_KEY` | — | API key for concierge Haiku calls (required) |
| `CONCIERGE_MODEL` | `claude-haiku-4-5-20251001` | Model for intent triage |
| `MUNIN_URL` | `http://localhost:3030` | Munin HTTP endpoint |
| `MUNIN_API_KEY` | — | Bearer token for Munin (required) |
| `POLL_INTERVAL_MS` | `30000` | How often to check task results |
| `MAX_POLL_DURATION_MS` | `7200000` | Stop polling after this (2x default task timeout) |

## Concierge design

The concierge is a lightweight Claude Haiku call (~2000 tokens, ~$0.001/call) that triages incoming Telegram messages before submitting Hugin tasks. It receives:
- The user's message
- Recent Munin context (last 5 log entries from active projects, current task queue)
- Conversation history (if in a clarification loop)

It returns one of three actions:
- `ready` — intent is clear, here's the enriched task prompt, context, and timeout
- `clarify` — ambiguous, here's a question to ask the user
- `answer` — can be answered directly from context, no task needed

Tone: casual and terse (matches phone context).

</details>

#### API Surface

- `GET /health`

#### Dependencies

- `@anthropic-ai/sdk` ^0.52.0
- `@types/express` ^5.0.0
- `@types/node` ^22.0.0
- `express` ^4.21.0
- `grammy` ^1.35.0
- `tsx` ^4.19.0
- `typescript` ^5.7.0
- `vitest` ^3.0.0

#### Configuration (env var names)

```
ANTHROPIC_API_KEY=***
CONCIERGE_MODEL=***
HOST=***
MAX_POLL_DURATION_MS=***
MUNIN_API_KEY=***
MUNIN_URL=***
POLL_INTERVAL_MS=***
PORT=***
TELEGRAM_ALLOWED_USERS=***
TELEGRAM_BOT_TOKEN=***
```

#### Systemd Units

`ratatoskr.service`:
```ini
[Unit]
Description=Ratatoskr Telegram Router
After=network-online.target munin-memory.service
Wants=network-online.target

[Service]
Type=simple
User=magnus
WorkingDirectory=/home/magnus/repos/ratatoskr
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=10
EnvironmentFile=/home/magnus/repos/ratatoskr/.env

ProtectSystem=strict
ReadWritePaths=/home/magnus /tmp
NoNewPrivileges=true
PrivateTmp=false

[Install]
WantedBy=multi-user.target
```

#### Key Source Files

- `src/task-writer.ts` (57 lines)
- `src/concierge.ts` (153 lines)
- `src/index.ts` (60 lines)
- `src/bot.ts` (297 lines)
- `src/config.ts` (38 lines)
- `src/result-poller.ts` (90 lines)
- `src/munin-client.ts` (159 lines)

#### Current Commit

`bd28ebc86207a795b737d245453a08df0f667d3f feat: implement Ratatoskr — Telegram router with concierge (2026-03-23 10:26:50 +0100)`

---

### noxctl

- **Role:** CLI and MCP server for Fortnox accounting (invoices, bookkeeping, VAT)
- **Package:** `noxctl` v0.1.0
- **Description:** CLI and MCP server for Fortnox accounting — invoices, customers, bookkeeping, and VAT

#### Overview (from README)

Command-line interface (CLI) and Model Context Protocol (MCP) server for Fortnox — manage invoices, customers, bookkeeping, and VAT (Value Added Tax) from the terminal or from AI (Artificial Intelligence) agents like Claude Code.
```
noxctl init                          # interactive setup wizard
noxctl company info                  # verify connection
noxctl customers list                # list customers

#### Architecture Notes (CLAUDE.md)

<details>
<summary>Click to expand CLAUDE.md</summary>

# CLAUDE.md — noxctl

## What is this?

CLI and MCP server for Fortnox accounting (invoices, customers, bookkeeping, VAT).

## CLI-first in Claude Code

**Prefer the CLI over MCP tools when running in Claude Code.** The MCP server exists for environments without a shell (Claude Desktop, Web, Mobile).

```bash
# Reading data
noxctl invoices list
noxctl invoices list --output json
noxctl customers get 25

# Writing data (prompts for confirmation on TTY; use --yes to skip)
echo '{"InvoiceRows": [...]}' | noxctl invoices update 28 --input - --yes
noxctl invoices send 28              # prompts: Continue? [y/N]
noxctl invoices send 28 --yes        # skip prompt (non-interactive/scripting)

# Dry run first
noxctl invoices create --customer 25 --input data.json --dry-run
```

## Backlog

See `TODO.md` for the prioritized backlog and instructions for adding new resources.

## Project structure

- `src/operations/` — Fortnox API calls (shared by CLI and MCP)
- `src/tools/` — MCP tool registrations (Zod schemas)
- `src/cli.ts` — Commander CLI definitions
- `src/fortnox-client.ts` — HTTP client with rate limiting and retry
- `src/views.ts` — Column definitions for table output
- `src/formatter.ts` — Table/JSON output formatting

## Dev commands

```bash
npm run build       # TypeScript compile
npm test            # Vitest (323 unit tests)
npm run test:live   # Live API tests (needs credentials)
npm run lint        # ESLint
npm run format      # Prettier
```

## Conventions

- All MCP tool descriptions are in Swedish
- CLI commands mirror MCP tools 1:1
- Mutations prompt for confirmation on TTY; require `--yes` when piped (CLI) or `confirm: true` (MCP)
- Both support `--dry-run` / `dryRun` to preview without executing

</details>

#### Dependencies

- `@modelcontextprotocol/sdk` ^1.27.1
- `@types/node` ^25.4.0
- `commander` ^14.0.3
- `eslint` ^10.0.3
- `husky` ^9.1.7
- `lint-staged` ^16.3.3
- `prettier` ^3.8.1
- `typescript` ^5.9.3
- `typescript-eslint` ^8.57.0
- `vitest` ^4.1.0
- `zod` ^4.3.6

#### Key Source Files

- `src/views.ts` (397 lines)
- `src/formatter.ts` (285 lines)
- `src/index.ts` (65 lines)
- `src/cli.ts` (2080 lines)
- `src/operations/costcenters.ts` (68 lines)
- `src/operations/suppliers.ts` (71 lines)
- `src/operations/tax.ts` (89 lines)
- `src/operations/invoice-payments.ts` (65 lines)
- `src/operations/supplier-invoices.ts` (75 lines)
- `src/operations/invoices.ts` (131 lines)
- `src/operations/supplier-invoice-payments.ts` (67 lines)
- `src/operations/articles.ts` (71 lines)
- `src/operations/company.ts` (10 lines)
- `src/operations/orders.ts` (83 lines)
- `src/operations/pricelists.ts` (119 lines)
- `src/operations/accounts.ts` (51 lines)
- `src/operations/customers.ts` (72 lines)
- `src/operations/vouchers.ts` (76 lines)
- `src/operations/offers.ts` (93 lines)
- `src/operations/financial-reports.ts` (303 lines)
- `src/operations/taxreductions.ts` (56 lines)
- `src/operations/projects.ts` (65 lines)
- `src/auth.ts` (352 lines)
- `src/credentials-store.ts` (250 lines)
- `src/tools/costcenters.ts` (127 lines)

#### Current Commit

`579ac08655ea4170900d861ba503c73b5dc1d5f3 docs: update test count and mark completed backlog items (2026-03-20 23:31:40 +0100)`

---

### mimir

- **Role:** Self-hosted authenticated file server for artifact delivery
- **Package:** `mimir` v0.1.0
- **Port:** 3031
- **Description:** Self-hosted authenticated file server for the Jarvis personal AI system

#### Overview (from README)

Self-hosted authenticated file server for the [Jarvis](https://github.com/magnusgille) personal AI system. Named after the Norse figure of wisdom.
Serves documents, presentations, PDFs, and images over HTTPS with Bearer token auth. Part of the Hugin & Munin system: **Munin** (memory/brain), **Mímir** (file archive), **Hugin** (signal hunter).
## How it works
AI agents query **Munin** for document context (summaries, extracted text). When an agent needs the full file, it follows the Mímir URL from the Munin entry. Plain HTTP — no MCP required.
```

#### Architecture Notes (CLAUDE.md)

<details>
<summary>Click to expand CLAUDE.md</summary>

# Mímir — CLAUDE.md

## What this project is

Mímir is a self-hosted authenticated file server for the Jarvis personal AI system. Named after the Norse figure of wisdom. Serves documents, presentations, PDFs, and images over HTTPS with Bearer token auth.

Part of the Hugin & Munin system: **Munin** (memory/brain), **Mímir** (file archive), **Hugin** (signal hunter).

## Architecture

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Framework:** Express (minimal — static file serving + auth + directory listing)
- **Auth:** Bearer token (`MIMIR_API_KEY`), timing-safe comparison
- **Deployment:** NAS Pi (Pi 2), Cloudflare Tunnel, systemd
- **Storage:** `/home/magnus/artifacts/` on SD card, append-only backup to `/mnt/timemachine/backups/mimir/`
- **Laptop archive:** `~/mimir/` — dedicated artifact directory, synced to NAS

### Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/health` | GET | None | Health check |
| `/files/*` | GET | Bearer | Serve file from archive |
| `/list/*` | GET | Bearer | JSON directory listing |

### How agents use Mímir

Agents don't talk to Mímir directly via MCP. Instead:
1. Agent queries Munin for document context (summaries + extracted text in `documents/*` entries)
2. If the agent needs the full file, it follows the Mímir URL from the Munin entry
3. Only environments that can pass Bearer headers (Claude Code, Codex) can fetch full files
4. Web/Mobile agents get summaries from Munin — sufficient for ~90% of queries

### Security (2-layer, same model as Munin)

1. **Cloudflare Access** — Service Token (`munin-memory-mcp`) required at edge. CF Access app: `mimir.gille.ai`
2. **Bearer token** — `MIMIR_API_KEY` at origin, timing-safe comparison
3. **App hardening:**
   - Path traversal prevention (resolve + startsWith jail to root dir)
   - Rate limiting (60 req/min per IP)
   - DNS rebinding protection via allowed hosts
   - Security headers (X-Content-Type-Options, X-Frame-Options, CSP, X-Robots-Tag)
   - Dotfiles hidden from directory listings
   - systemd sandboxing (ProtectSystem=strict, ReadOnlyPaths for artifacts, NoNewPrivileges)

## Project structure

```
mimir/
├── package.json
├── tsconfig.json
├── CLAUDE.md              # This file
├── mimir.service          # systemd unit file
├── src/
│   └── index.ts           # Express server — all in one file
├── tests/
│   └── server.test.ts     # supertest integration tests
└── scripts/
    ├── deploy-nas.sh           # Deploy to NAS Pi
    ├── sync-artifacts.sh       # Manual rsync mgc/ from laptop to NAS (--delete + safety check)
    ├── sync-artifacts-daemon.sh # Launchd daemon wrapper (auto-sync, --delete + safety check)
    └── backup-artifacts.sh     # Append-only backup SD→NAS disk (cron on Pi, no --delete)
```

## How to build

```bash
npm install
npm run build
```

## How to test

```bash
npm test
```

## How to run locally

```bash
MIMIR_API_KEY=dev-key MIMIR_ROOT_DIR=./tests/__test_fixtures__ npm run dev
```

## Deployment to NAS Pi

```bash
./scripts/deploy-nas.sh [hostname-or-ip]
```

Default host: `100.99.119.52` (NAS Pi via Tailscale).

The NAS Pi needs a `.env` file at `/home/magnus/mimir/.env`:
```
MIMIR_API_KEY=<generate with: openssl rand -hex 32>
MIMIR_ALLOWED_HOSTS=mimir.gille.ai
```

### Tunnel infrastructure

- **Tunnel ID:** `9e8bc8af-dcf6-459d-90ed-f014c714b7d2`
- **cloudflared:** v2026.3.0, systemd service (enabled), config at `/etc/cloudflared/config.yml`
- **CF Access App:** `mimir.gille.ai` with Service Token Auth policy (reuses `munin-memory-mcp` token)
- **DNS:** CNAME `mimir.gille.ai` → tunnel
- **Public URL:** `https://mimir.gille.ai`

## Syncing files from laptop

**Automatic (launchd):** Runs every 30 minutes via `com.magnusgille.mimir-sync` launch agent. Checks NAS reachability before syncing — skips silently if offline.

```bash
# Manage the agent
launchctl list | grep mimir          # Check status
launchctl start com.magnusgille.mimir-sync  # Trigger manual sync
cat ~/.local/share/mimir/logs/sync-stdout.log  # View logs
```

**Manual:**
```bash
./scripts/sync-artifacts.sh [hostname-or-ip]
```

Syncs `~/mimir/` to `/home/magnus/artifacts/mgc/` on the NAS Pi with `--delete` (laptop is source of truth). Both manual and daemon scripts include a safety check that aborts if >20% of files would be deleted. The `~/mimir/` directory is a pure artifact archive — no excludes needed.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MIMIR_PORT` | `3031` | HTTP server port |
| `MIMIR_HOST` | `127.0.0.1` | Bind address (localhost for tunnel) |
| `MIMIR_API_KEY` | — | Bearer token (required) |
| `MIMIR_ROOT_DIR` | `/home/magnus/artifacts` | Root directory to serve |
| `MIMIR_ALLOWED_HOSTS` | — | Extra allowed Host headers (comma-separated) |
| `MIMIR_RATE_LIMIT` | `60` | Max requests per minute per IP |

## Key design decisions

- Single-file server (~200 lines) — no need for complexity
- No MCP — plain HTTP is universally accessible. MCP can be added later if needed (via Munin proxy)
- No upload endpoint — files arrive via rsync from laptop
- Range request support for large PDFs (streaming)
- Artifacts on SD card (51GB free), append-only backup to NAS disk hourly (no `--delete` — HD is retention layer)
- Ingress sync (laptop → SD) uses `--delete` with 20% deletion safety threshold
- Separate from Time Machine mount to keep backups safe

</details>

#### API Surface

- `GET /files/{*path}`
- `GET /health`
- `GET /list/`
- `GET /list/{*path}`

#### Dependencies

- `@types/express` ^5.0.2
- `@types/mime-types` ^2.1.4
- `@types/node` ^22.15.3
- `@types/supertest` ^6.0.2
- `express` ^5.1.0
- `mime-types` ^3.0.1
- `supertest` ^7.1.0
- `tsx` ^4.19.4
- `typescript` ^5.8.3
- `vitest` ^3.1.2

#### Systemd Units

`mimir.service`:
```ini
[Unit]
Description=Mímir File Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=magnus
WorkingDirectory=/home/magnus/mimir
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=5
EnvironmentFile=/home/magnus/mimir/.env

# Sandboxing
ProtectSystem=strict
ReadWritePaths=/home/magnus/mimir
ReadOnlyPaths=/home/magnus/artifacts
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

#### Key Source Files

- `src/index.ts` (256 lines)

#### Current Commit

`b71faa16b1c78d32b21c5702c29ba36e15089757 fix: remove --delete from backup, add deletion safety to sync scripts (2026-03-15 21:30:20 +0100)`

---


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


---

## Current Deployment Snapshot

> Captured at 2026-03-25T13:48:10Z on huginmunin

### Service Status

| Unit | State | Enabled | PID | Memory | Started |
|------|-------|---------|-----|--------|---------|
| munin-memory.service | ✅ active | enabled | 268571 | n/a | Mon 2026-03-23 16:31:07 CET |
| hugin.service | ✅ active | enabled | 258596 | n/a | Mon 2026-03-23 11:00:25 CET |
| heimdall.service | ✅ active | enabled | 341797 | n/a | Wed 2026-03-25 14:41:14 CET |
| heimdall-collect.service | ❌ inactive
unknown | static | — | — | — |
| heimdall-maintain.service | ❌ inactive
unknown | static | — | — | — |
| ratatoskr.service | ✅ active | enabled | 266541 | n/a | Mon 2026-03-23 15:04:54 CET |
| mimir.service | ❌ inactive
unknown | not-found
unknown | — | — | — |
| skuld.service | ❌ inactive
unknown | not-found
unknown | — | — | — |

### Repository Versions

| Repo | Branch | Last Commit |
|------|--------|-------------|
| munin-memory | main | `01d8153` docs: add health, scalability & OSS readiness debate summary (2 days ago) | ⚠️ dirty
| hugin | main | `b0fa2b5` feat: add Context field, reply routing, task groups, and type tags (2 days ago) | ⚠️ dirty
| heimdall | main | `bbaaeb6` feat: add deployments tab with full Pi audit (7 minutes ago) | ⚠️ dirty
| skuld | main | `48e026c` feat: add service identifier to /health endpoint for Heimdall drift tracking (2 days ago) |
| ratatoskr | main | `bd28ebc` feat: implement Ratatoskr — Telegram router with concierge (2 days ago) |
| noxctl | main | `579ac08` docs: update test count and mark completed backlog items (5 days ago) | ⚠️ dirty
| mimir | main | `b71faa1` fix: remove --delete from backup, add deletion safety to sync scripts (10 days ago) |

### Health Checks

- ✅ **munin-memory** (:3030) — HTTP 200
- ⚠️ **hugin** (:3035) — HTTP 000000
- ✅ **heimdall** (:3033) — HTTP 200
- ⚠️ **skuld** (:3040) — HTTP 000000
- ✅ **ratatoskr** (:3034) — HTTP 200
- ⚠️ **mimir** (:3031) — HTTP 000000

---

## Project Statuses (from Munin)

### projects/munin-memory

# Munin Memory — Current Status

**Phase:** Maintenance. Security audit complete, all public repos reviewed and hardened.
**Current work:** No active feature work. Security audit of all 10 public GitHub repos completed — 4 repos made private, TantRagnar identity rewritten, npm vulns fixed, paths sanitized, debate skill updated with PII sanitization. Heimdall issue #1 filed for deploy drift detection.
**Blockers:** None.

---

### projects/grimnir

Phase: Active — infrastructure stabilizing, shifting to visibility and polish.

Email outcome rendering fixed (shared extraction, `<pre>`, no truncation). Alerts → Munin pipeline live. Skuld /health enhanced. grimnir-bot added as collaborator on all 6 Norse Stack repos. `actions/pending` convention established for task follow-up items.

5 Pi tasks queued: verify alerts pipeline, mimir-inbox backup, Homebrew tap, blog post drafts, axon-lang A2A repositioning. Next big items: MCP marketplace publish for munin-memory, Telegram bridge.

---

### projects/hugin

**Phase:** Active — enhanced task parser shipped

**Current:** Context field (repo:/scratch/files aliases), Reply-to/Reply-format for Ratatoskr routing, Group/Sequence for task orchestration, type:* tag forwarding through lifecycle. Scratch workspace at /home/magnus/scratch. Path traversal guard on resolveContext.

**Commit:** b0fa2b5 on main, pushed to origin.

**Blocker:** `sudo systemctl restart hugin` needed — sandbox blocked sudo. Manual restart required for new parser to be active.

**Next:** Ratatoskr integration to consume Reply-to from results.

---

### projects/grimnir

Phase: Active — infrastructure stabilizing, shifting to visibility and polish.

Email outcome rendering fixed (shared extraction, `<pre>`, no truncation). Alerts → Munin pipeline live. Skuld /health enhanced. grimnir-bot added as collaborator on all 6 Norse Stack repos. `actions/pending` convention established for task follow-up items.

5 Pi tasks queued: verify alerts pipeline, mimir-inbox backup, Homebrew tap, blog post drafts, axon-lang A2A repositioning. Next big items: MCP marketplace publish for munin-memory, Telegram bridge.

---

### projects/heimdall

## Phase
Maintenance — v2 feature-complete

## Current State
- Dashboard with full infrastructure monitoring
- Tasks tab (Hugin task tracking)
- Projects tab (Munin memory integration)
- **Deployments tab** — services grid, repo status, process audit, cleanup suggestions
- Architecture tab
- Deploy drift detection, backup monitoring, NAS probing, alerting
- Security hardened (CSP, rate limiting, input validation)

## Recent
- 2026-03-25: Added Deployments tab with comprehensive Pi audit
- 2026-03-25: Added Projects tab with Munin integration

## Next
- Polish and iterate on new tabs based on usage

---

### projects/grimnir

Phase: Active — infrastructure stabilizing, shifting to visibility and polish.

Email outcome rendering fixed (shared extraction, `<pre>`, no truncation). Alerts → Munin pipeline live. Skuld /health enhanced. grimnir-bot added as collaborator on all 6 Norse Stack repos. `actions/pending` convention established for task follow-up items.

5 Pi tasks queued: verify alerts pipeline, mimir-inbox backup, Homebrew tap, blog post drafts, axon-lang A2A repositioning. Next big items: MCP marketplace publish for munin-memory, Telegram bridge.

---

### projects/skuld

Phase 3 complete. Commitment tracking — LLM extraction from briefing context, Munin-backed store (skuld/commitments namespace), urgency scoring (age-based + deadline-based), commitments section in briefing prompts with overdue highlighting, CLI commands (commitments, done). Codex-reviewed, all 64 tests passing. Commit 14eb2e6 pushed to main.

---

### projects/grimnir

Phase: Active — infrastructure stabilizing, shifting to visibility and polish.

Email outcome rendering fixed (shared extraction, `<pre>`, no truncation). Alerts → Munin pipeline live. Skuld /health enhanced. grimnir-bot added as collaborator on all 6 Norse Stack repos. `actions/pending` convention established for task follow-up items.

5 Pi tasks queued: verify alerts pipeline, mimir-inbox backup, Homebrew tap, blog post drafts, axon-lang A2A repositioning. Next big items: MCP marketplace publish for munin-memory, Telegram bridge.

---

### projects/ratatoskr

Ratatoskr deployed and running on Pi (port 3034). Telegram bot connected via long-polling. Added to Heimdall monitoring. Systemd service enabled and active.

Latest: poll recovery, delivery confirmation, conversation persistence, instance isolation (659a1ab). Needs redeployment to Pi to activate new features. Add RATATOSKR_INSTANCE_ID=prod to Pi .env.

Next: deploy to Pi, then consider photo/voice handling, task progress notifications, rate limiting.

---

### projects/grimnir

Phase: Active — infrastructure stabilizing, shifting to visibility and polish.

Email outcome rendering fixed (shared extraction, `<pre>`, no truncation). Alerts → Munin pipeline live. Skuld /health enhanced. grimnir-bot added as collaborator on all 6 Norse Stack repos. `actions/pending` convention established for task follow-up items.

5 Pi tasks queued: verify alerts pipeline, mimir-inbox backup, Homebrew tap, blog post drafts, axon-lang A2A repositioning. Next big items: MCP marketplace publish for munin-memory, Telegram bridge.

---

### projects/noxctl

**Phase:** Published — maintenance + expanding coverage

**Current work:** API drift detection shipped (2026-03-23). Weekly GH Actions workflow diffs Fortnox OpenAPI spec and opens issues on changes. All 323 tests passing.

**Repo:** github.com/Magnus-Gille/noxctl | Local: /Users/magnus/repos/fortnox-mcp
**Stack:** TypeScript, Node 20+, Commander, MCP SDK
**Tests:** 323 passing (39 files, Vitest)
**HEAD:** `7e97337` on main
**npm:** `noxctl@0.1.0` (published 2026-03-20)

**API coverage (18 modules):** invoices, customers, suppliers, articles, vouchers, accounts, financial reports, tax, company, invoice payments, supplier invoice payments, offers, orders, projects, cost centers, tax reductions (ROT/RUT), price lists, prices

**Priority backlog:**
- Tier 2: confirmation preview, analytics MCP tools, shell completions, natural date periods, Claude Desktop auto-registration
- Tier 3 remaining: contracts, bank transactions, file attachments
- Release: npm 0.2.0

---

### projects/grimnir

Phase: Active — infrastructure stabilizing, shifting to visibility and polish.

Email outcome rendering fixed (shared extraction, `<pre>`, no truncation). Alerts → Munin pipeline live. Skuld /health enhanced. grimnir-bot added as collaborator on all 6 Norse Stack repos. `actions/pending` convention established for task follow-up items.

5 Pi tasks queued: verify alerts pipeline, mimir-inbox backup, Homebrew tap, blog post drafts, axon-lang A2A repositioning. Next big items: MCP marketplace publish for munin-memory, Telegram bridge.

---

### projects/mimir

Phase: Maintenance
Current: Refactored Pi layout — symmetric ~/mimir/ on both laptop and Pi for artifacts, server at ~/mimir-server/ on Pi (2026-03-15)
Paths: Laptop ~/mimir/ → rsync → Pi ~/mimir/ (served by Mímir). Server code at Pi ~/mimir-server/. Backup from Pi ~/mimir/ → /mnt/timemachine/backups/mimir/
Deployed: Server running on NAS Pi via Cloudflare Tunnel at mimir.gille.ai

---

### projects/grimnir

Phase: Active — infrastructure stabilizing, shifting to visibility and polish.

Email outcome rendering fixed (shared extraction, `<pre>`, no truncation). Alerts → Munin pipeline live. Skuld /health enhanced. grimnir-bot added as collaborator on all 6 Norse Stack repos. `actions/pending` convention established for task follow-up items.

5 Pi tasks queued: verify alerts pipeline, mimir-inbox backup, Homebrew tap, blog post drafts, axon-lang A2A repositioning. Next big items: MCP marketplace publish for munin-memory, Telegram bridge.

---

### projects/grimnir

Phase: Active — infrastructure stabilizing, shifting to visibility and polish.

Email outcome rendering fixed (shared extraction, `<pre>`, no truncation). Alerts → Munin pipeline live. Skuld /health enhanced. grimnir-bot added as collaborator on all 6 Norse Stack repos. `actions/pending` convention established for task follow-up items.

5 Pi tasks queued: verify alerts pipeline, mimir-inbox backup, Homebrew tap, blog post drafts, axon-lang A2A repositioning. Next big items: MCP marketplace publish for munin-memory, Telegram bridge.

---

---

## Roadmap

> Assembled from project statuses in Munin. See individual project entries for details.



---

## Appendix: Full Dependency Tree

> Combined and deduplicated across all component `package.json` files.

### Production Dependencies

| Package | Version(s) | Used By |
|---------|-----------|---------|
| `@anthropic-ai/claude-agent-sdk` | ^0.2.81 | hugin |
| `@anthropic-ai/sdk` | ^0.39.0, ^0.52.0 | skuld, ratatoskr |
| `@azure/msal-node` | ^2.16.3 | heimdall |
| `@fastify/rate-limit` | ^10.3.0 | heimdall |
| `@huggingface/transformers` | ^3.8.1 | munin-memory |
| `@modelcontextprotocol/sdk` | ^1.12.1, ^1.27.1 | munin-memory, noxctl |
| `better-sqlite3` | ^11.8.2, ^12.8.0 | munin-memory, heimdall, skuld |
| `commander` | ^14.0.3 | noxctl |
| `express` | ^5.2.1, ^5.1.0, ^4.21.0 | munin-memory, hugin, skuld, ratatoskr, mimir |
| `fastify` | ^5.8.2 | heimdall |
| `grammy` | ^1.35.0 | ratatoskr |
| `ical.js` | ^2.1.0 | skuld |
| `mime-types` | ^3.0.1 | mimir |
| `sqlite-vec` | ^0.1.7-alpha.2 | munin-memory |
| `uuid` | ^11.1.0 | munin-memory |
| `zod` | ^4.3.6 | noxctl |

### Dev Dependencies

| Package | Version(s) | Used By |
|---------|-----------|---------|
| `@types/better-sqlite3` | ^7.6.13 | munin-memory, skuld |
| `@types/express` | ^5.0.6, ^5.0.2, ^5.0.0 | munin-memory, hugin, skuld, ratatoskr, mimir |
| `@types/mime-types` | ^2.1.4 | mimir |
| `@types/node` | ^22.13.4, ^22.15.3, ^22.0.0, ^25.4.0 | munin-memory, hugin, skuld, ratatoskr, noxctl, mimir |
| `@types/supertest` | ^6.0.3, ^6.0.2 | munin-memory, mimir |
| `@types/uuid` | ^10.0.0 | munin-memory |
| `eslint` | ^10.0.3 | noxctl |
| `husky` | ^9.1.7 | noxctl |
| `lint-staged` | ^16.3.3 | noxctl |
| `prettier` | ^3.8.1 | noxctl |
| `supertest` | ^7.2.2, ^7.1.0 | munin-memory, mimir |
| `tsx` | ^4.19.2, ^4.19.4, ^4.19.0 | munin-memory, hugin, skuld, ratatoskr, mimir |
| `typescript` | ^5.7.3, ^5.8.3, ^5.7.0, ^5.9.3 | munin-memory, hugin, skuld, ratatoskr, noxctl, mimir |
| `typescript-eslint` | ^8.57.0 | noxctl |
| `vitest` | ^3.0.5, ^3.1.2, ^3.0.0, ^4.1.0 | munin-memory, hugin, skuld, ratatoskr, noxctl, mimir |

---

*Generated at 2026-03-25T13:48:10Z on `huginmunin` by `scripts/generate-architecture.sh`*
*Source hash: `66256e8bfe9115a9` — regenerate if stale.*
