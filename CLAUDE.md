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
- `docs/full-architecture.md` — Ignored, auto-generated comprehensive doc (run `make docs` or `scripts/generate-architecture.sh` on the Pi to regenerate a local snapshot)
- `docs/conventions.md` — Naming, GitHub ownership, service patterns
- `docs/role-separation.md` — Why the canonical grimnir checkout must not double as a deploy target or hugin workspace, and the validate check that alarms on drift (issue #47)
- `docs/observability-and-improvement.md` — How components capture traces, score outputs, and feed the self-improving loop
- `docs/tenant-contract.md` — The minimal agent↔substrate contract any agent must satisfy to act through the substrate (Munin access, gateway routing, safety gating, audit emission) + a cheap validation plan
- `docs/tenant-validation-2026-07-04.md` — Evidence note from the first real non-Claude tenant run (Codex CLI, grimnir#58): seams A/B/C passed on transport, D blocked, per-tenant identity missing everywhere; harness in `scripts/tenant-validation/`
- `docs/failure-recovery.md` — The autonomous-mutation undo convention: every autonomous mutation leaves a reversal recipe (git_revert / snapshot / irreversible+mitigation) + an audit event (issue #46)
- `docs/gap-analysis-2026-07-03.md` — Critic-corrected ecosystem gap analysis vs vision v0.2: ranked gaps, quick wins, cut list, corrections log (the source of the 23-ticket fleet program)
- `docs/threat-model.md` — Consolidated threat model (v0.1): assets, trust boundaries, adversaries, and a T1–T11 key-threats table mapped to owning tickets (from the 2026-07-06 blind-spot audit)
- `docs/roadmap-now-decision-brief.md` — Working brief for the current "now" cluster: succession (#65), GDPR/data lifecycle (#66), system ROI/off-ramp (#67), Skuld revive-or-cut (#69), interactive-session trust posture (#70), and the #58 Verdandi blocker
- `services.json` — **Single source of truth** for component inventory (names, hosts, ports, systemd units). All scripts read from it via `scripts/lib/registry.js`

## Scripts

| Script | Purpose | Run with |
|--------|---------|----------|
| `scripts/deploy.sh` | Deploy services to Pi hosts (all or selective) | `make deploy` or `make deploy ARGS="munin-memory"` |
| `scripts/generate-architecture.sh` | Generate deployment snapshot + full-architecture.md | `make docs` (Pi only) |
| `scripts/security-scan.sh` | Scan all repos for vulnerabilities and secrets | `make security` |

> OS patching (`setup-host-patching.sh`) and maintenance reports (`maintenance-report.sh`) have moved to the `brokkr` repo. Use `make patching` / `make maintenance-os` / `make maintenance-deps` from `brokkr/`.
