# The Grimnir System — Architecture Guide

> Internal reference document for the Grimnir personal AI infrastructure.
> Last updated: 2026-07-23.

---

## The Grimnir System

Grimnir is a personal AI infrastructure that gives Claude persistent memory, file access, local inference, and autonomous task execution across every environment — from a phone on the bus to a terminal at the desk. It runs on two Raspberry Pis, a MacBook, and a BosGame M5 inference node, under the principle that **data sovereignty and simplicity beat sophistication**.

### Why it exists

Every conversation with Claude starts from zero. There is no memory between sessions, no access to personal files, and no way to say "do this while I sleep." Grimnir solves these three problems:

1. **Memory** — Munin gives Claude persistent, searchable memory across every environment (desktop, mobile, web, CLI).
2. **Files** — Mimir makes personal documents available to agents over HTTPS, with summaries cached in Munin for environments that can't fetch files directly.
3. **Autonomy** — Hugin lets any Claude session submit a task that gets executed on the Pi, with results written back to memory. Skuld synthesizes overnight signals into a morning briefing.

### Design philosophy

Three principles guide every decision:

- **Sovereignty** — Authoritative data at rest lives on Magnus's hardware. Cloud AI services may
  process prompts under their own retention terms, but are never storage authority for Grimnir.
- **Privacy** — Writes to memory are scanned for secrets before storage. Auth is required at every layer. Sensitive documents get summaries in Munin but full text stays on the Pi.
- **Simplicity** — Each service is a single-purpose Node.js/TypeScript application. No frameworks beyond Express/Fastify for HTTP. No ORMs. No Kubernetes. SQLite for storage. systemd for process management.

---

## Components at a Glance

| Component | Role | Port | Host | Repo |
|-----------|------|------|------|------|
| **Munin Memory** | Persistent memory MCP server | 3030 | Pi 1 | `munin-memory` |
| **Hugin** | Task dispatcher | 3032 | Pi 1 | `hugin` |
| **Heimdall** | Monitoring dashboard | 3033 | Pi 1 | `heimdall` |
| **Ratatoskr** | Telegram router + concierge | 3034 | Pi 1 | `ratatoskr` |
| **Skuld** | Daily intelligence briefing | — | Pi 1 | `skuld` (Magnus-Gille) |
| **Verdandi** | Tamper-evident audit log | 3036 | Pi 1 | `verdandi` |
| **Mimir** | Authenticated file server | 3031 | Pi 2 (NAS) | `mimir` |
| **noxctl** | Accounting CLI + MCP | — | Laptop (global) | `fortnox-mcp` |
| **Home-server gateway** | Local-inference gateway + micro-orchestrator | 8080 | BosGame M5 (`inference.gille.ai`, live) | `gille-inference` |

---

## System Topology

The system spans two Raspberry Pis, a MacBook Air, and a BosGame M5 inference node, connected via Tailscale (private mesh VPN) and exposed to cloud services through Cloudflare Tunnels where needed.

```mermaid
graph TB
    subgraph Internet
        CF[Cloudflare Edge]
        Claude_Web[Claude.ai / Mobile]
        Claude_Desktop[Claude Desktop]
        Telegram[Telegram]
    end

    subgraph MacBook["MacBook Air (Development)"]
        CC[Claude Code / CLI]
        Codex[Codex CLI]
        Noxctl["noxctl (Fortnox CLI)"]
        Files_Laptop["~/mimir/ (artifact archive)"]
        Launchd["launchd sync (30 min)"]
    end

    subgraph Pi1["Pi 1 — huginmunin (AI Infrastructure)"]
        Munin["Munin Memory<br/>:3030 (MCP + HTTP)"]
        Hugin["Hugin Dispatcher<br/>:3032 (health only)"]
        Heimdall_Svc["Heimdall Dashboard<br/>:3033 (Fastify + HTMX)"]
        Ratatoskr_Svc["Ratatoskr Router<br/>:3034 (Telegram bot)"]
        Skuld_Svc["Skuld Briefing<br/>(systemd timer)"]
        Verdandi_Svc["Verdandi Audit<br/>:3036 (Fastify)"]
        Claude_Pi[Claude Code / Codex<br/>spawned by Hugin]
        Tunnel_Pi1["cloudflared tunnel"]
    end

    subgraph Pi2["Pi 2 — NAS (Storage & Backup)"]
        Mimir["Mimir File Server<br/>:3031"]
        Artifacts["/home/magnus/artifacts/"]
        Backups["/home/magnus/backups/"]
        TimeMachine["/mnt/timemachine/"]
        Tunnel_Pi2["cloudflared tunnel"]
    end

    subgraph M5["BosGame M5 — Local Inference (live)"]
        Gateway_M5["Home-server Gateway<br/>:8080 (auth + admission)"]
        LMStudio_M5["LM Studio / llama-swap<br/>:1234 (model serving)"]
        Ledger_M5["Capability Ledger<br/>(verdict KB)"]
    end

    %% Cloud → Edge → Services
    Claude_Web -->|OAuth 2.1| CF
    Claude_Desktop -->|Bearer + mcp-remote| CF
    CF -->|Service Token + Bearer| Tunnel_Pi1 --> Munin
    CF -->|Service Token + Bearer| Tunnel_Pi1 --> Heimdall_Svc
    CF -->|Service Token + Bearer| Tunnel_Pi2 --> Mimir

    %% Local connections
    CC -->|MCP stdio or HTTP| Munin
    CC -->|HTTP Bearer| Mimir
    Codex -->|HTTP Bearer| Munin
    Hugin -->|HTTP JSON-RPC| Munin
    Claude_Pi -->|MCP stdio or HTTP| Munin
    Skuld_Svc -->|SQLite read + API write| Munin
    Skuld_Svc -->|Claude API| Internet
    Heimdall_Svc -->|SQLite read + SSH| Pi2

    %% File sync
    Launchd -->|rsync via Tailscale| Artifacts
    Files_Laptop -.->|synced| Artifacts

    %% Backup flows
    Munin -->|hourly sqlite3 .backup| Backups
    Mimir -->|hourly rsync| TimeMachine

    %% Telegram → Ratatoskr
    Telegram -->|long-poll| Ratatoskr_Svc
    Ratatoskr_Svc -->|submit task| Munin
    Ratatoskr_Svc -->|Haiku triage| Internet

    %% Task flow
    CC -->|submit task| Munin
    Hugin -->|spawn| Claude_Pi
    Hugin -.->|macro-route: /delegate, /v1/chat| Gateway_M5
    Gateway_M5 --> LMStudio_M5
    Gateway_M5 --> Ledger_M5
```

### Hardware

| Unit | Hostname | Role | Key Services |
|------|----------|------|-------------|
| Pi 1 | `huginmunin.local` | AI infrastructure (compute) | Munin, Hugin, Heimdall, Skuld, Verdandi |
| Pi 2 | NAS | Storage & backup | Mimir, Samba, Time Machine |
| M5 | `m5` (tailnet `100.76.72.59`) | Local LLM inference (1–5 users) | Home-server gateway, llama-swap |

Both Pis are Raspberry Pi 5 units (8 GB RAM) in Flirc passive-cooling aluminum cases. They run on the same local network and are also connected via Tailscale for reliable cross-Pi communication. The BosGame M5 is the dedicated local-inference node — see *Home-server (M5) — Local Inference* below and the gateway API contract in the `gille-inference` repo.

### Network model

- **Local services** bind either to loopback or an explicitly selected tailnet address. Tailscale
  reachability is not authentication; network services retain their own bearer/OAuth control.
- **Cloudflare Tunnels** provide HTTPS ingress from the internet, with edge-layer authentication (CF Access).
- **Tailscale** provides encrypted Pi-to-Pi and laptop-to-Pi communication for rsync, SSH, and backups.
- **Public endpoints:** `munin-memory.gille.ai`, `heimdall.gille.ai`, `mimir.gille.ai`

### Node/substrate reconciliation boundary (ADR-007)

Relocating a physical node and relocating a workload are separate operations. Grimnir owns desired
topology and placement in `services.json`; Brokkr owns fresh observed node capability, substrate
preflight/realization evidence and rollback; each component owns its requirements, drain/verify
hooks, data migration and workload rollback. Heimdall transports and presents that evidence but
does not determine topology.

The contract keeps four fact classes separate: **desired** placement, **observed** capability,
**required** workload constraints and an attempted **lifecycle result**. Missing, stale or
incompatible decision-driving evidence, unavailable Brokkr, or a missing workload hook blocks
preflight and mutation rather than being inferred healthy. A physical move may pause for an
operator to move or reconnect equipment; a workload move starts with an explicit desired-placement
change and cannot silently authorize a physical move. See
[ADR-007](adr-007-node-substrate-contract.md) for the state machine, conflict rules and promotion
requirements.

---

## Munin — Memory

Munin is the brain of the system. It is an MCP (Model Context Protocol) server that gives Claude persistent, searchable memory across every environment — desktop app, mobile, web, and CLI.

### Architecture

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Database:** SQLite via `better-sqlite3`, with FTS5 full-text search and `sqlite-vec` for vector search
- **Protocol:** MCP over stdio (local) or stateless Streamable HTTP (network)
- **Auth:** Dual — legacy Bearer token for CLI/Desktop + OAuth 2.1 for web/mobile
- **Deployment:** systemd on Pi 1, exposed via Cloudflare Tunnel

### Data model

Munin stores two fundamental types of entry in a single `entries` table:

```mermaid
erDiagram
    ENTRIES {
        uuid id PK
        string namespace
        string key "NULL for log entries"
        enum entry_type "state | log"
        text content
        json tags
        string agent_id
        enum embedding_status "pending | processing | generated | failed"
        string embedding_model
        datetime created_at
        datetime updated_at
    }

    ENTRIES_FTS {
        text content "FTS5 full-text index"
    }

    ENTRIES_VEC {
        string entry_id FK
        float384 embedding "sqlite-vec KNN index"
    }

    AUDIT_LOG {
        datetime timestamp
        string agent_id
        string action
        string namespace
        string key
        text detail
    }

    OAUTH_CLIENTS {
        string client_id PK
        string client_secret
        json redirect_uris
        json metadata
    }

    OAUTH_TOKENS {
        string token PK
        string type "access | refresh"
        string client_id FK
        json scopes
        datetime expires_at
        boolean revoked
    }

    ENTRIES ||--o| ENTRIES_FTS : "indexed by"
    ENTRIES ||--o| ENTRIES_VEC : "embedded in"
    ENTRIES ||--o{ AUDIT_LOG : "audited by"
    OAUTH_CLIENTS ||--o{ OAUTH_TOKENS : "issues"
```

**State entries** are mutable key-value pairs, identified by `namespace + key`. They represent current truth — a project's status, a person's contact info, a decision record. Writing to the same namespace+key overwrites the previous value.

**Log entries** are append-only, timestamped, and have no key. They represent chronological history — decisions made, milestones reached, events recorded. Log entries are never modified after creation.

**Namespaces** are hierarchical strings separated by `/` (e.g., `projects/munin-memory`, `people/magnus`, `documents/internal`). They are created implicitly on first write.

### Search

Munin supports three search modes through `memory_query`:

| Mode | Mechanism | Best for |
|------|-----------|----------|
| **Lexical** | FTS5 keyword search | Exact terms, known identifiers |
| **Semantic** | sqlite-vec KNN over 384-dim embeddings | Conceptual similarity, natural language |
| **Hybrid** | Reciprocal Rank Fusion (RRF) of both | General queries (default) |

Embeddings are generated asynchronously by a background worker using Transformers.js with the `all-MiniLM-L6-v2` model. Writes are never blocked by embedding generation. A circuit breaker trips after repeated failures, gracefully degrading all search to lexical mode.

### MCP tools

| Tool | Purpose |
|------|---------|
| `memory_orient` | Start-of-conversation orientation: conventions, computed project dashboard, namespace overview, maintenance suggestions |
| `memory_write` | Store or update a state entry. Supports compare-and-swap for concurrent safety |
| `memory_read` | Retrieve a specific state entry by namespace + key |
| `memory_read_batch` | Retrieve multiple entries in one call |
| `memory_get` | Retrieve any entry (state or log) by UUID |
| `memory_query` | Search memories with lexical, semantic, or hybrid modes |
| `memory_log` | Append an immutable log entry |
| `memory_delete` | Delete with token-based two-step confirmation |

### Computed dashboard

`memory_orient` dynamically computes a project dashboard from status entries in `projects/*` and `clients/*` namespaces. Entries are grouped by lifecycle tag (`active`, `blocked`, `completed`, `stopped`, `maintenance`, `archived`), with maintenance suggestions surfaced for stale or misconfigured entries.

### How agents connect

| Environment | Transport | Auth |
|-------------|-----------|------|
| Claude Code (local) | MCP stdio | None (process-level) |
| Claude Code (remote) | MCP HTTP | Bearer token + edge service token |
| Claude Desktop | MCP HTTP via `mcp-remote` bridge | Bearer token + edge service token |
| Claude.ai / Claude Mobile | MCP HTTP with OAuth 2.1 | Dynamic client registration, PKCE |

The HTTP transport runs in **stateless mode**: each POST to `/mcp` creates a fresh MCP server and transport, processes the request, and tears down. This eliminates session management complexity.

---

## Mimir — File Archive

Mimir is a self-hosted authenticated file server. It makes personal documents — PDFs, presentations, images, markdown files — available to AI agents over HTTPS.

### Architecture

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Framework:** Express (single ~250-line file)
- **Auth:** Bearer token with timing-safe comparison
- **Deployment:** systemd on Pi 2 (NAS), exposed via Cloudflare Tunnel
- **Storage:** SD card on NAS Pi, backed up hourly to external disk

### Endpoints

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /health` | None | Health check |
| `GET /files/{path}` | Bearer | Serve file from archive, with range request support |
| `GET /list/{path}` | Bearer | JSON directory listing (dotfiles hidden) |

### File flow

Files originate on the MacBook, sync to the NAS Pi, and are discovered by agents through Munin:

```mermaid
sequenceDiagram
    participant Laptop as MacBook (~/mimir/)
    participant NAS as NAS Pi (/home/magnus/artifacts/)
    participant Mimir as Mimir Server (:3031)
    participant Munin as Munin Memory
    participant Agent as AI Agent

    Note over Laptop,NAS: Every 30 minutes (launchd)
    Laptop->>NAS: rsync via Tailscale

    Note over Agent,Munin: Document discovery
    Agent->>Munin: memory_query("quarterly report")
    Munin-->>Agent: documents/internal entry with<br/>summary + Mimir URL

    alt Agent can fetch files (Claude Code, Codex)
        Agent->>Mimir: GET /files/mgc/report.pdf<br/>Authorization: Bearer <TOKEN>
        Mimir-->>Agent: PDF content (streaming, range requests)
    else Agent is web/mobile (Claude.ai)
        Note over Agent: Uses summary + extracted text<br/>from Munin entry (sufficient for ~90% of queries)
    end
```

### Indexing pipeline

Documents are indexed into Munin under `documents/*` namespaces using a `/index-artifacts` skill. Each indexed entry contains source URL, local path, metadata, summary, key points, and extracted text. Munin serves as the **discovery layer** while Mimir serves as the **content layer**.

---

## Hugin — Task Dispatch

Hugin is the system's hands. It polls Munin for pending tasks, spawns AI runtimes to execute them, and writes results back. Named after Odin's raven of thought.

### Architecture

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Framework:** Express (health endpoint only)
- **Deployment:** systemd on Pi 1, co-located with Munin
- **Integration:** Munin HTTP API via JSON-RPC 2.0
- **Agent loop:** the in-process Claude runtime is the **Claude Agent SDK** (`@anthropic-ai/claude-agent-sdk`, `sdk-executor.ts`) — Hugin no longer shells out to `claude -p`. Codex still runs as a subprocess (`codex exec`).
- **Multi-runtime:** a `runtime-registry.ts` + `router.ts` select per task between the Agent SDK, local **Ollama** (`ollama-executor.ts`), **OpenRouter** (`openrouter-client.ts`), and the **M5 home-server** (`homeserver-executor.ts`), with fallback to Claude on local-infra failure.

> **Repo note:** `hugin` is the deployed service. `hugin-orchestrator` is a feature line (broker + workflow expansion) that should either land back into `hugin` or formally supersede it — two repos for one service is drift risk. `hugin-munin` is an archived bootstrap/reference scaffold, not a running service.

### The poll-claim-execute-report lifecycle

```mermaid
sequenceDiagram
    participant Client as Any Claude Environment
    participant Munin as Munin Memory
    participant Hugin as Hugin Dispatcher
    participant Runtime as Claude Code / Codex

    Note over Client: User says "do X on the Pi"
    Client->>Munin: memory_write(tasks/<id>, "status",<br/>task spec, ["pending", "runtime:claude"])

    loop Every 30 seconds
        Hugin->>Munin: memory_query(tags: ["pending"],<br/>namespace: "tasks/")
    end

    Note over Hugin: Task found!
    Hugin->>Munin: memory_write(tasks/<id>, "status",<br/>tags: ["running"], CAS: expected_updated_at)

    Hugin->>Runtime: spawn("claude -p <prompt>"<br/>or "codex exec --full-auto <prompt>")

    Runtime-->>Hugin: exit code + stdout/stderr

    Hugin->>Munin: memory_write(tasks/<id>, "result",<br/>exit code + output + timing)
    Hugin->>Munin: memory_write(tasks/<id>, "status",<br/>tags: ["completed"] or ["failed"])

    Client->>Munin: memory_read(tasks/<id>, "result")
```

### Execution model

- **One task at a time** — the poll loop claims and runs a single task at a time. Simplicity over throughput. (Multi-step *pipelines* fan out within a single claimed task; see below.)
- **Compare-and-swap claiming** — uses Munin's `expected_updated_at` to prevent double-claiming.
- **Output capture** — ring buffer keeps the last 50,000 characters of combined stdout/stderr. Full output also streamed to per-task log files in `~/.hugin/logs/`.
- **Timeout handling** — SIGTERM after configured timeout, SIGKILL after an additional 10 seconds.
- **Stale task recovery** — on startup, scans for `running` tasks; marks as `failed` if elapsed time exceeds 2x timeout.
- **Graceful shutdown** — SIGTERM forwarded to child process with 30-second grace period.

### Pipelines (multi-step task graphs)

Beyond single prompts, Hugin compiles declarative multi-step work into a DAG and executes it: `pipeline-compiler.ts` → `pipeline-ir.ts` / `task-graph.ts` → `pipeline-dispatch.ts`, with `pipeline-gates.ts` enforcing inter-step conditions and `pipeline-summary-manager.ts` rolling up results. This is the structured successor to the older `Group`/`Sequence` FIFO sub-task fields — it lets one submitted task expand into a routed, gated, multi-runtime chain.

### Delegation broker (cloud-side)

`src/broker/` exposes an HTTP delegation API (`server.ts`, `handlers.ts`) so a cloud Claude session can hand Hugin a bounded sub-task without writing a Munin task by hand. It carries idempotency keys (`idempotency.ts`), a durable journal (`journal.ts`), reconciliation (`reconciliation.ts`), and its own OpenRouter executor — this is the `orchestrator-v1` broker behind the `/delegate` skill.

### Safety gating

Because Hugin runs untrusted prompts against real credentials and the tailnet, every task passes a gating layer: `prompt-injection-scanner.ts`, `exfiltration-scanner.ts`, `egress-policy.ts`, a `privacy-filter/`, content `sensitivity.ts` classification, plus `task-signing.ts` / `provenance.ts` for attribution. This is the harness-level analogue of Verdandi's redact-before-persist and Munin's secret-scan.

### Task schema

Any Claude environment (or Ratatoskr) can submit a task by writing to Munin:

```markdown
Namespace: tasks/<task-id>
Key: status
Tags: ["pending", "runtime:claude", "type:code"]

## Task: <title>

- **Runtime:** claude | codex
- **Context:** repo:heimdall | scratch | files | /absolute/path
- **Timeout:** 300000
- **Submitted by:** claude-desktop | ratatoskr
- **Submitted at:** 2026-03-14T10:00:00Z
- **Reply-to:** telegram:12345678 | none
- **Reply-format:** summary | full
- **Group:** 20260323-140000-deploy-cycle
- **Sequence:** 1

### Prompt
<the actual prompt for the AI runtime>
```

**Context resolution:** Hugin resolves the `Context` field to an absolute working directory:

| Context value | Resolved path | Use case |
|---------------|---------------|----------|
| `repo:<name>` | `/home/magnus/repos/<name>` | Code tasks in a specific repo |
| `scratch` | `/home/magnus/scratch` | Research, email, admin, non-code work |
| `files` | `/home/magnus/mimir` | File organization, document work |
| `/absolute/path` | Used as-is | Backward compat, custom paths |
| *(omitted)* | `/home/magnus/workspace` | Legacy default |

`Working dir:` is still accepted for backward compatibility but `Context:` takes priority.

**Reply routing:** When `Reply-to` is set (e.g., `telegram:12345678`), Ratatoskr polls the task result and delivers it back to the specified channel. Without `Reply-to`, results are only available via Munin.

**Task groups:** `Group` and `Sequence` fields link related sub-tasks. Hugin processes them in FIFO order (submission order). Each sub-task's prompt includes a check for the previous step's success.

---

## Home-server (M5) — Local Inference

The BosGame M5 is a dedicated local-inference node, **live** at `inference.gille.ai` (public, Cloudflare) and on the tailnet (`m5`, port 8080). It runs the **home-server gateway** (`gille-inference` repo) — an authenticated, OpenAI-compatible front door to locally-served models (llama-swap on `:8091` loopback), plus a deterministic micro-orchestrator and a capability ledger. It is registered as the `m5` MCP server (`ask` / `list_models`) and is the target of Hugin's local-runtime offload.

### Routing ownership (ADR-004)

- **Hugin owns *macro*-routing** — *which node* should handle a task (M5 / Orin / laptop / Pi). Agentic tasks still flow through Hugin's poll-claim-execute model; verifiable one-shot sub-tasks are macro-routed to an inference node.
- **The gateway owns *micro*-routing** — *which local model* serves a request, plus external admission (per-key auth, sliding-window quota, owner-preempts-guest GPU admission). Model hot-swap at inference time is owned by `llama-swap`, not the gateway.
- **`ledger.ts` is the single capability KB** — per-(task_type, model) verdicts with freeze-on-failure, read via `GET /ledger`. Nightly local sub-tasks route through `POST /delegate` so the ledger keeps learning what local models can be trusted with.

### Gateway surface

`GET /healthz` · `GET /models` · `GET /ledger` · `POST /v1/chat/completions` · `POST /delegate` (owner) · `POST /admin/models/{load,unload,download}` (owner). Full request/response schemas, auth tiers, and the OpenAI-shaped error envelope live in **`docs/gateway-api-contract.md`** in the `gille-inference` repo.

### Why a dedicated node

Offload the bulk of agentic sub-task tokens (classification, extraction, summarize, rewrite, short reasoning) to local models, keeping a frontier orchestrator for planning and escalation. Economics, model roster, and per-task viability are tracked in `gille-inference`, whose **offloadability trend** (which task types local models can be trusted with) now publishes nightly to a Heimdall panel — the data-grounded feedback loop that drives routing decisions.

### Learning evidence ownership

The self-improvement architecture has separate evidence planes; it is not one generic trace table.
Hugin owns Hugin-origin task identity, execution/repository/publication/product outcomes,
corrections, and prompt/harness experiments. `gille-inference` owns direct gateway-origin identity,
gateway rendering/exposure, exact served-model identity, capability evidence, the model roster, and
M5 micro-routing. The content owner remains separate from either service transport identity.
The LearningTaskContract target requires both components to emit natural-keyed immutable
pipeline-accounting events so failures, retries, delivery attempts, corrections, and period closes
backed by authoritative ledger/high-water proofs remain countable without duplicate denominator
members even when no valid learning record exists. It also requires owner authority,
negative-attempt binding, boundary exclusions, and cross-owner erasure membership to use a
separately trusted validation context; producer body hashes are not authentication. Hugin and
`gille-inference` do not yet implement this complete accounting/trust target. Each
source/artifact carries its own governance; joined records derive the
strictest policy rather than claiming all enforcement passed through Hugin. The versioned join and
compatibility rules are defined by [LearningTaskContract v1](learning-task-contract.md); the current implemented,
shadow, manual, and future stages are tracked in
[observability-and-improvement.md](observability-and-improvement.md).

A completed task, published PR, uncalibrated judge, or model self-report cannot substitute for the
other plane's verdict. Hugin's `promotion-ready` state is reviewed evidence only: the owning
repository's human operator applies and rolls back the exact configuration. Model-weight training
is proposed outside v1, pending both component-owner reviews, in
[ADR-006](adr-006-learning-improvement-scope.md).

---

## Ratatoskr — Telegram Router

Ratatoskr is the messenger. Named after the squirrel that carries messages between the eagle and serpent on Yggdrasil, it lets Magnus interact with Grimnir from Telegram — sending tasks from a phone and receiving results back.

### Architecture

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Framework:** Express (health endpoint only) + grammy (Telegram bot)
- **AI:** @anthropic-ai/sdk (Haiku for intent triage)
- **Deployment:** systemd on Pi 1, long-polling mode (no inbound HTTP from internet)

### How it works

Ratatoskr is NOT an AI agent. It's plumbing with a thin intelligence layer:

1. **Receive** — Telegram message arrives from an allowlisted user
2. **Triage** — Concierge layer calls Claude Haiku with the message + recent Munin context. Haiku decides: ready to submit, needs clarification, or can answer directly
3. **Clarify** — If ambiguous, replies on Telegram asking for more detail. Conversational loop until intent is clear
4. **Submit** — Writes a well-formed Hugin task to Munin with context, reply routing, and timeout
5. **Monitor** — Polls Munin for task completion every 30 seconds
6. **Deliver** — Sends result summary back on Telegram

The concierge uses Haiku (~$0.001/call) for triage, not the Max plan. The actual task execution runs through Hugin → Claude Code (Max plan).

### Task schema fields set by Ratatoskr

| Field | Value |
|-------|-------|
| `Context` | Inferred by concierge (default: `scratch`) |
| `Runtime` | Always `claude` |
| `Reply-to` | `telegram:<chat_id>` |
| `Submitted by` | `ratatoskr` |

### Telegram commands

| Command | Action |
|---------|--------|
| `/status` | Show active/recent tasks |
| `/cancel <id>` | Cancel a pending task |
| `/raw <prompt>` | Skip concierge, submit verbatim |
| `/repo <name> <prompt>` | Submit to a specific repo context |
| Any other text | Triaged by concierge, then submitted |

---

## Heimdall — Monitoring

Heimdall is the watchman. It provides at-a-glance health visibility for the entire Grimnir infrastructure — both Pis, all services, backups, and autonomous task execution.

### Architecture

- **Runtime:** Node.js, CommonJS
- **Framework:** Fastify + HTMX + Chart.js
- **Database:** SQLite (collected metrics, forensic logs)
- **Deployment:** systemd on Pi 1 (:3033), exposed via Cloudflare Tunnel (heimdall.gille.ai)

### What it monitors

| Category | Metrics | Source |
|----------|---------|--------|
| System Health | CPU temp, memory usage, load average | Both Pis (local + SSH) |
| Temperature History | Temp trend, alert thresholds | Collected samples |
| Disk Usage | SD card + NAS drive capacity/used/trend | `df` on both Pis |
| Backup Freshness | TM last backup, Munin backup age | NAS filesystem |
| Service Health | HTTP health endpoints | munin-memory, mimir, heimdall, hugin |
| MCP Health | Munin MCP transport probe | MCP endpoint |
| Hugin Dispatcher | Heartbeat, uptime, active task | Munin heartbeat entry |
| Hugin Task History | Completed/failed tasks, timing | Munin SQLite (direct read) |
| Deploy Drift | Service version vs git remote | `/health` + `git ls-remote` |

### Design principle

**Heimdall answers one question: "Is the system healthy?"** Green/yellow/red for every service, backup, and resource. It does not try to be the UI for every service — no Munin browser and no task submission. Skuld is the exception by design: Heimdall renders the latest briefing from Munin because Skuld has no standalone web surface.

### Data collection

Pull model with systemd timers:
- `heimdall-collect.timer` — periodic collection of metrics from both Pis
- `heimdall-maintain.timer` — database maintenance and retention cleanup

### Planned additions

- Skuld briefing status (last run, success/failure)
- Deploy drift UI — collector exists, needs dashboard wiring

---

## Skuld — Daily Intelligence Briefing

Skuld is the oracle. Named after the Norn of the future, it generates a daily intelligence briefing by synthesizing calendar events, project state, and (future) financial data through Claude's API.

### Architecture

- **Runtime:** Node.js 22+, TypeScript (strict mode)
- **Interface:** CLI / oneshot systemd service; no standalone web server
- **AI:** @anthropic-ai/sdk (Claude API direct)
- **Data sources:** Google Calendar (ICS), Munin (SQLite direct read), Fortnox (future via noxctl)
- **Deployment:** Pi 1, co-located with Munin for low-latency SQLite reads
- **Repo:** `Magnus-Gille/skuld` (private)

### How it works

1. **Collect** — Fetches calendar events (ICS feed), queries Munin for active projects/client statuses/weekly plan/recent logs
2. **Assemble** — Builds a `BriefingContext` with structured data from all sources
3. **Synthesize** — Sends context to Claude API with a narrative system prompt ("trusted chief of staff" persona)
4. **Deliver** — Outputs briefing to stdout (formatted) and Munin (`briefings/daily/{date}` / `briefings/latest`); Heimdall renders the web view from Munin

### Briefing sections

- **Day Overview** — what's scheduled, what phase projects are in
- **Attention Needed** — blockers, stale projects, overdue items
- **Preparation** — what to prepare for upcoming meetings/deadlines
- **Looking Ahead** — week/month view

### Output channels

| Channel | Access |
|---------|--------|
| CLI (`skuld briefing`) | Direct on Pi |
| Heimdall (`/briefing`) | Web view rendered from Munin |
| Munin (`briefings/daily/{date}`) | Any Claude environment |

### Roadmap

Phase 1 (MVP) is complete. Phases 2-8 extend from Fortnox financial awareness through commitment tracking, meeting prep cards, relationship heat maps, weekly ritual automation, and Hugin scheduled runs.

---

## Verdandi — Audit Log

Verdandi is the accountability layer. Named after the Norn of the present, it records what agents did, what humans decided, and the reasoning behind both — as a tamper-evident event log.

### Architecture

- **Runtime:** Node.js 22+, TypeScript (strict mode, ESM)
- **Framework:** Fastify 5
- **Database:** SQLite with WAL mode
- **Deployment:** systemd on Pi 1 (:3036), localhost only (accessed via Tailscale)

### Design principles

- **Server-authoritative** — all derived fields (timestamp, identity, hash chain) are recomputed server-side; client values are advisory only.
- **Fail-open for operations, fail-loud for audit** — Verdandi never blocks business operations, but every audit gap is recorded and surfaced.
- **Redact before persist** — a 14-rule secret redaction pipeline strips sensitive data at intake before any write.
- **Honest about evidence** — two grades: `mechanism` (proven/automatic) and `convention` (unverified/self-reported).

### Ingest pipeline

Events flow through a 10-stage atomic pipeline: auth → validation → redaction → override → classification → canonicalization → queue → atomic append → idempotency → optional debug layer.

Hash chain integrity uses SHA-256 over RFC 8785 deterministic JSON canonicalization, with a single append worker to prevent race conditions.

### Endpoints

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /health` | None | Health check + event count |
| `POST /api/events` | Bearer (per-component key) | Ingest single event |
| `POST /api/events/batch` | Bearer | Batch ingest (up to 1000) |
| `POST /api/events/hook` | Bearer | Claude Code hook payload ingestion |
| `GET /api/events` | Bearer | Query with filters (trace_id, type, component, severity, time range) |
| `GET /api/events/:eventId` | Bearer | Single event retrieval |
| `GET /api/verify` | Bearer | Hash chain integrity verification |

### Event taxonomy

Events are classified by severity (`critical`, `significant`, `routine`, `debug`) and retention class (`accounting` 7y, `security` 12m, `operational` 6m, `debug` 1-3m). Per-component API keys provide identity attribution.

---

## Fortnox MCP / noxctl — Accounting

noxctl is a CLI and MCP server for Fortnox, the Swedish accounting platform. It handles invoices, customers, bookkeeping, and VAT.

### Architecture

- **Runtime:** Node.js 20+, TypeScript (strict mode)
- **Interfaces:** CLI (`commander`) + MCP server (`@modelcontextprotocol/sdk`)
- **Auth:** OAuth2 with secure credential storage (OS keychain)
- **Deployment:** Installed globally via npm on laptop. CLI preferred in Claude Code, MCP server for Desktop/Web/Mobile.

### Capabilities

- Customers: list, get, create, update
- Invoices: list, get, create, update, send, bookkeep, credit
- Bookkeeping: vouchers, accounts (chart of accounts)
- Tax: VAT report (informational)
- Company: info
- Utility: init (setup wizard), doctor (validate), logout

### Output

Table on TTY, JSON when piped. Mutation operations prompt for confirmation on interactive terminals; non-interactive requires `--yes` or `--dry-run`.

---

## Security Model

Every network-exposed service uses the same two-layer authentication pattern:

### Layer 1: Edge authentication (Cloudflare Access)

A reverse proxy sits in front of every public endpoint. Requests must present a valid service token. This layer terminates TLS, authenticates, blocks unauthenticated traffic, and provides DDoS protection.

### Layer 2: Origin authentication

Each service requires its own Bearer token (timing-safe comparison) or OAuth 2.1 access token. Even if the edge were bypassed, the origin rejects unauthenticated requests.

### Application hardening

- **Secret scanning** — Munin rejects writes containing API keys, tokens, private keys, or passwords
- **Input validation** — strict regex for namespaces, keys, tags; content size limits
- **Path traversal prevention** — Mimir resolves and jails all file paths
- **systemd sandboxing** — `ProtectSystem=strict`, `NoNewPrivileges=true`, read-only except explicitly allowed paths
- **Security headers** — CSP, HSTS, X-Frame-Options, X-Content-Type-Options on all responses
- **Database permissions** — SQLite files created with `0600`

### Backup strategy

| What | Frequency | Mechanism | Destination |
|------|-----------|-----------|-------------|
| Munin SQLite DB | Hourly | `sqlite3 .backup` + integrity check + rsync | NAS Pi |
| Mimir artifacts | Hourly | rsync to external disk | NAS external disk |
| MacBook | Continuous | Time Machine via Samba | NAS external disk (1.5 TB) |

### Automated security scanning

A weekly security scan runs across all Grimnir repos via `scripts/security-scan.sh` in the `grimnir` repo. This was chosen over a dedicated "Syn" service after an adversarial debate concluded that Phase 1 doesn't justify a separate component.

| Property | Value |
|----------|-------|
| Script | `grimnir/scripts/security-scan.sh` |
| Schedule | Weekly, Sunday 03:00 (systemd timer: `grimnir-security-scan.timer`) |
| Host | Pi 1 (huginmunin) |
| Checks | `npm audit` (dependency vulnerabilities), secret detection (regex on git-tracked files) |
| Results | Munin (`security/scans/<date>`, `security/repos/<repo>`) + stdout |
| Dashboard | Heimdall deploy status card (timer type: last run, next run, exit status) |

**Munin schema:**

| Namespace | Key | Type | Purpose |
|-----------|-----|------|---------|
| `security/scans/<YYYY-MM-DD>` | `summary` | state | Full scan results for all repos |
| `security/repos/<repo>` | `latest` | state | Per-repo current security posture |
| `security/` | — | log | Append-only scan event history |

**Future expansion** (not committed, requires validation of Phase 1 signal quality):
- AI-powered STRIDE analysis on architecture changes (not scheduled — triggered manually or on significant changes)
- Security header probes on running services
- Autonomous low-risk fix PRs via Hugin (dependency bumps only, never auto-merged)

---

## Cross-Cutting Concerns

### The two-layer state model

- **Local files** hold the full detail — source code, documents, build artifacts. Accessed directly by the runtime executing the work.
- **Munin entries** hold the summary — project status, document summaries, task results. Accessible from any environment, including mobile.

This isn't just convenience; it's necessity. Claude.ai and Claude Mobile can access Munin (via MCP) but cannot read local files. By maintaining summaries in Munin, every environment stays informed.

### Access matrix

| Environment | Munin | Mimir | Hugin (tasks) | Ratatoskr | Heimdall | Skuld | Verdandi | noxctl |
|-------------|-------|-------|---------------|-----------|----------|-------|----------|--------|
| Claude Code (laptop) | HTTP Bearer | HTTPS Bearer | Submit via Munin | — | Browser | — | HTTP Bearer | CLI |
| Claude Desktop | HTTP Bearer (mcp-remote) | — | Submit via Munin | — | — | — | — | MCP |
| Claude Web/Mobile | HTTP OAuth 2.1 | — | Submit via Munin | — | — | — | — | MCP |
| Telegram (phone) | — | — | Via Ratatoskr | Send message | — | — | — | — |
| Claude Code (Pi/Hugin) | HTTP Bearer (localhost) | HTTPS Bearer | IS the dispatcher | — | — | — | HTTP Bearer | — |
| Ratatoskr | HTTP Bearer (localhost) | — | Submit via Munin | IS the router | — | — | — | — |

### Deployment patterns

All services follow the same deployment model:

1. **Build locally** — `npm run build` compiles TypeScript to `dist/`
2. **Deploy via script** — `scripts/deploy.sh` reads `services.json`, syncs or pulls the target tree, uses `npm ci --omit=dev` when a lockfile exists, installs every declared systemd unit, restarts services, and enables then restarts timers after daemon reload so changed schedules actually take effect. `.env` files are preserved on the Pi and never overwritten.
3. **Acceptance markers fail unknown** — before either rsync or git-pull mutates a remote tree, the script logs any prior accepted full SHA and removes `.deployed-commit`. Only successful unit and HTTP health gates create the new marker. Recurring timers must be active with a concrete next trigger; registry-declared one-shot timers are restarted but may legitimately be active/elapsed after firing. Heimdall's boot check is recurring: `OnBootSec=90` schedules its initial run and `OnUnitInactiveSec=5m` schedules later alert-lifecycle reconciliations. A failed deployment therefore remains markerless/unknown; rollback means redeploying the logged prior SHA from a clean worktree.
4. **systemd manages the process or schedule** — services use `Restart=always` where appropriate; timer components run oneshot jobs on schedule.
5. **Health endpoints** — long-running HTTP services expose `/health` for Heimdall monitoring; timer-only components are validated through systemd state and their Munin outputs.
6. **Deploy modes differ by component** — most services deploy by rsync; `grimnir` uses `git pull --ff-only` because its canonical checkout is also the registry source.

GitHub Actions runs shellcheck and the repository regression suite on pull requests and `main`.
Deployment remains manual and intentional; CI success never deploys a host.

### The debate/review process

Architecture decisions are stress-tested through a structured debate process:

1. **Claude** (Opus) drafts the proposal
2. **Codex** (GPT) provides adversarial review
3. The debate produces a resolution document capturing what changed and why
4. Key amendments are recorded in the relevant `CLAUDE.md`

### GitHub ownership

- **Magnus-Gille** owns all repos
- **grimnir-bot** is a dedicated machine account for the Pi — added as collaborator on repos Hugin pushes to
- Pi authenticates to GitHub exclusively via grimnir-bot (SSH key `grimnir-bot.pub`)

---

## What's Next

### Close the production-task learning loop

Adopt LearningTaskContract v1 in Hugin and `gille-inference`, prove the same exact pre-orchestration
raw-task identity with cross-repository fixtures, retain failures and late product labels durably,
and package one governed production candidate plus its complete joined evidence bundle into a
one-axis experiment. Only independently verified evidence may enter the
M5 capability ledger; any route/prompt/harness change remains reviewed and reversible. The ordered
roadmap and measurable meanings of “continuous” are in
[observability-and-improvement.md](observability-and-improvement.md) and
[learning-task-contract.md](learning-task-contract.md).

### Heimdall completeness
Deploy drift UI needs wiring (collector exists).

### Fortnox integration in Skuld
Phase 2 of Skuld: invoice aging, revenue pulse, payment status — pulling data from Fortnox via noxctl.

### Notification delivery
Task completion notifications are delivered via **Telegram** (Ratatoskr's `POST /api/send` endpoint). Email delivery via Heimdall (March 2026) was **retired** in June 2026 — Microsoft's consumer-account abuse block (AADSTS70000 on `grimnir-bot@outlook.com`) made it unreliable, so the dead MS-Graph notify path was removed (heimdall #23). All task notifications now route through Telegram (Ratatoskr).

### The north star

**Tell Grimnir to do X and go to sleep.** Wake up to a summary of what happened, what succeeded, what needs attention. The pieces are in place — memory, files, task execution, monitoring, briefings. The next system milestone is not merely collecting more traces: it is one governed real task travelling through exact identity, product review, independent experiment, reviewed application, and post-change evidence.

---

*Built by Magnus Gille, with Claude and Codex. Running on two Raspberry Pis in Mariefred, Sweden.*
