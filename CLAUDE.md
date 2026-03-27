# Grimnir — CLAUDE.md

## What this is

This is the **system-level** documentation repository for the Grimnir personal AI infrastructure. It contains architecture docs, conventions, and cross-project references.

No service code lives here — each component has its own repo.

## Component repos

| Component | Repo | Role |
|-----------|------|------|
| Munin Memory | `munin-memory` | Persistent memory MCP server |
| Hugin | `hugin` | Task dispatcher |
| Mimir | `mimir` | Authenticated file server |
| Heimdall | `heimdall` | Monitoring dashboard |
| Ratatoskr | `ratatoskr` | Telegram router + concierge |
| Skuld | `skuld` (grimnir-bot org) | Daily intelligence briefing |
| Fortnox MCP | `fortnox-mcp` | Accounting CLI + MCP |

## Key documents

- `docs/architecture.md` — Full system architecture guide (topology, components, security, data flow)
- `docs/full-architecture.md` — Auto-generated comprehensive doc (run `make docs` or `scripts/generate-architecture.sh` to regenerate)
- `docs/conventions.md` — Naming, deploy paths, GitHub ownership, port assignments
