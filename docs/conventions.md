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
| **Verdandi** | Norn of the present | Carves what is happening now | Tamper-evident audit log |
| **noxctl** | — (not Norse) | — | Fortnox accounting CLI + MCP server |

## Port assignments, hosts, and deploy paths

> **Source of truth:** [`services.json`](../services.json) in the repo root.
> All scripts (`deploy.sh`, `security-scan.sh`, `generate-architecture.sh`) read from it.
> To add or change a service, edit `services.json` — no other files need updating.

Remote install paths live in `services.json` as `deploy_path`. Most services live under `~/repos/<service-name>/`, but a few have intentional exceptions such as `munin-memory` (`~/munin-memory`) and `mimir` (`~/mimir-server`).

Deploy selectively from the laptop with an explicitly bound source and full commit SHA, for example `make deploy ARGS="heimdall=/private/tmp/heimdall-release@<accepted-full-sha>"`. Bare service names and no-argument deploys fail closed. The centralized script validates every selected source before any component mutation, deploys via rsync or the registered git-pull mode, runs a local build when `needs_build: true`, installs production dependencies on the target host, and restarts primary service units. Declared units are install-ready by default. A component may opt into the bounded host renderer with `systemd_runtime`; see [`systemd-runtime-rendering.md`](systemd-runtime-rendering.md) for the registry contract, preflight, migration, and rollback procedure.

For owning-repository deploy commands outside the centrally deployable set, use `scripts/guarded-deploy.sh` as the outer source-identity boundary. See [`deployment-source-binding.md`](deployment-source-binding.md) for both contracts and examples.

## GitHub ownership

> **Source of truth:** `services.json.repository_authority`, combined with
> each component's `repo` field. It also records local checkout-name
> exceptions for ecosystem repositories that are not deployed components.

- **Magnus-Gille** — default owner
- **grimnir-bot** — dedicated machine account for Pi. Added as collaborator
  on repos Hugin pushes to. Pi authenticates to GitHub exclusively via its SSH
  key; it is not repository authority for Skuld.

## Repo naming

Repos are named after the component, lowercase. The GitHub org normally
matches the operator:
- `Magnus-Gille/munin-memory`
- `Magnus-Gille/hugin`
- `Magnus-Gille/heimdall`
- `Magnus-Gille/mimir`
- `Magnus-Gille/fortnox-mcp`
- `Magnus-Gille/ratatoskr`
- `Magnus-Gille/skuld`

Ecosystem repositories that are not deployed components are listed in
`repository_authority.additional_repositories`; their canonical local
checkout name is explicit so the audit never infers authority from an old
directory or remote name.

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
| `brokkr-maintenance-os.timer` | Daily 07:00 | OS patch status (pending security, reboot-required, disk) across all Pis → Munin + Telegram (brokkr repo) |
| `brokkr-maintenance-deps.timer` | Weekly Mon 02:10 | npm outdated across service repos → Munin (detect+report only) (brokkr repo) |

## Service patterns

Every Grimnir service follows these patterns:
- Node.js 20+, TypeScript strict mode
- SQLite for any local state (via better-sqlite3)
- systemd for process management (Restart=always)
- `/health` endpoint for Heimdall monitoring
- `.env` file on Pi for secrets (never in git, never overwritten by deploy)
- Centralized deploy via `grimnir/scripts/deploy.sh` is preferred; per-repo deploy scripts remain for bootstrap or repo-specific extras and must be invoked through Grimnir's `scripts/guarded-deploy.sh`
