# Grimnir — Conventions

## Norse naming

All components are named after figures from Norse mythology, reflecting their role:

| Name | Figure | Role in myth | Role in system |
|------|--------|-------------|----------------|
| **Grimnir** | Odin (masked) | The all-father | The system as a whole |
| **Munin** | Odin's raven of memory | Flies out, returns with memories | Persistent memory server |
| **Hugin** | Odin's raven of thought | Flies out, returns with knowledge | Task dispatcher |
| **Mimir** | Wisest of the Aesir | Guardian of wisdom's well | File archive |
| **Heimdall** | Watchman of the gods | Sees all from Bifröst | Monitoring dashboard |
| **Skuld** | Norn of the future | Shapes what shall be | Daily intelligence briefing |
| **Ratatoskr** | Squirrel on Yggdrasil | Carries messages between eagle and serpent | Telegram message router |
| **noxctl** | — (not Norse) | — | Fortnox accounting CLI + MCP server |

## Port assignments, hosts, and deploy paths

> **Source of truth:** [`services.json`](../services.json) in the repo root.
> All scripts (`deploy.sh`, `security-scan.sh`, `generate-architecture.sh`) read from it.
> To add or change a service, edit `services.json` — no other files need updating.

Remote install paths live in `services.json` as `deploy_path`. Most services live under `~/repos/<service-name>/`, but a few have intentional exceptions such as `munin-memory` (`~/munin-memory`) and `mimir` (`~/mimir-server`).

Deploy all services from the laptop with `make deploy` (from the grimnir repo), or selectively with `make deploy ARGS="munin-memory hugin"`. The centralized script deploys the local working tree via rsync, runs a local build when `needs_build: true`, installs production dependencies on the target host, and restarts primary service units. For worktree-based deploys, pass an explicit source override such as `make deploy ARGS="munin-memory=/tmp/munin-memory-awesome"`.

## GitHub ownership

- **Magnus-Gille** — owns all repos
- **grimnir-bot** — dedicated machine account for Pi. Added as collaborator on repos Hugin pushes to. Pi authenticates to GitHub exclusively via grimnir-bot SSH key.

## Repo naming

Repos are named after the component, lowercase. The GitHub org matches the operator:
- `Magnus-Gille/munin-memory`
- `Magnus-Gille/hugin`
- `Magnus-Gille/heimdall`
- `Magnus-Gille/mimir`
- `Magnus-Gille/fortnox-mcp`
- `Magnus-Gille/ratatoskr`
- `grimnir-bot/skuld` (exception: created by Hugin task under bot account)

## Systemd timers

> Timer/service unit names and hosts are defined in [`services.json`](../services.json).
> This table documents schedules and purposes (not in the registry).

| Timer | Schedule | Purpose |
|-------|----------|---------|
| `heimdall-collect.timer` | Every 5 min | Metric collection across both Pis |
| `heimdall-maintain.timer` | Daily 03:00 | Database maintenance and retention |
| `skuld.timer` | Daily 06:00 | Morning intelligence briefing |
| `grimnir-security-scan.timer` | Weekly Sun 03:00 | Dependency audit + secret scan across all repos |
| `grimnir-validate.timer` | Daily 04:30 | Registry vs live state validation, results to Munin |

## Service patterns

Every Grimnir service follows these patterns:
- Node.js 20+, TypeScript strict mode
- SQLite for any local state (via better-sqlite3)
- systemd for process management (Restart=always)
- `/health` endpoint for Heimdall monitoring
- `.env` file on Pi for secrets (never in git, never overwritten by deploy)
- Centralized deploy via `grimnir/scripts/deploy.sh` is preferred; per-repo deploy scripts remain for bootstrap or repo-specific extras
