# Grimnir — CLAUDE.md

## What this is

This is the **system-level** documentation repository for the Grimnir personal AI infrastructure. It contains architecture docs, conventions, and cross-project references.

No service code lives here — each component has its own repo.

## Component repos

> Component inventory (names, hosts, ports, systemd units) is defined in [`services.json`](services.json).
> All scripts read from it — see `docs/authority.md` for the authority map.

| Component | Repo | Role |
|-----------|------|------|
| Munin Memory | `munin-memory` | Persistent memory MCP server |
| Hugin | `hugin` | Task dispatcher |
| Mimir | `mimir` | Authenticated file server |
| Heimdall | `heimdall` | Monitoring dashboard |
| Ratatoskr | `ratatoskr` | Telegram router + concierge |
| Skuld | `skuld` (grimnir-bot org) | Daily intelligence briefing |
| Fortnox MCP | `fortnox-mcp` | Accounting CLI + MCP |
| Brokkr | `brokkr` | Platform/substrate layer — hardware, OS, storage, backups (peer, not a service) |

## Key documents

- `docs/architecture.md` — Full system architecture guide (topology, components, security, data flow)
- `docs/full-architecture.md` — Auto-generated comprehensive doc (run `make docs` or `scripts/generate-architecture.sh` to regenerate)
- `docs/conventions.md` — Naming, GitHub ownership, service patterns
- `docs/role-separation.md` — Why the canonical grimnir checkout must not double as a deploy target or hugin workspace, and the validate check that alarms on drift (issue #47)
- `docs/observability-and-improvement.md` — How components capture traces, score outputs, and feed the self-improving loop
- `docs/tenant-contract.md` — The minimal agent↔substrate contract any agent must satisfy to act through the substrate (Munin access, gateway routing, safety gating, audit emission) + a cheap validation plan
- `docs/failure-recovery.md` — The autonomous-mutation undo convention: every autonomous mutation leaves a reversal recipe (git_revert / snapshot / irreversible+mitigation) + an audit event (issue #46)
- `docs/gap-analysis-2026-07-03.md` — Critic-corrected ecosystem gap analysis vs vision v0.2: ranked gaps, quick wins, cut list, corrections log (the source of the 23-ticket fleet program)
- `services.json` — **Single source of truth** for component inventory (names, hosts, ports, systemd units). All scripts read from it via `scripts/lib/registry.js`

## Scripts

| Script | Purpose | Run with |
|--------|---------|----------|
| `scripts/deploy.sh` | Deploy services to Pi hosts (all or selective) | `make deploy` or `make deploy ARGS="munin-memory"` |
| `scripts/generate-architecture.sh` | Generate deployment snapshot + full-architecture.md | `make docs` (Pi only) |
| `scripts/security-scan.sh` | Scan all repos for vulnerabilities and secrets | `make security` |

> OS patching (`setup-host-patching.sh`) and maintenance reports (`maintenance-report.sh`) have moved to the `brokkr` repo. Use `make patching` / `make maintenance-os` / `make maintenance-deps` from `brokkr/`.
