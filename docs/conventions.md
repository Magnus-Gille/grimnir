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

## Port assignments

| Port | Service | Host |
|------|---------|------|
| 3030 | Munin Memory | Pi 1 |
| 3031 | Mimir | Pi 2 |
| 3032 | Hugin | Pi 1 |
| 3033 | Heimdall | Pi 1 |
| 3034 | Ratatoskr | Pi 1 |
| 3040 | Skuld | Pi 1 |

## Deploy paths on Pi

All services deploy to `~/repos/<service-name>/` on their respective Pi. No exceptions.

```
/home/magnus/repos/munin-memory/   # Pi 1 (huginmunin.local)
/home/magnus/repos/hugin/          # Pi 1
/home/magnus/repos/heimdall/       # Pi 1
/home/magnus/repos/skuld/          # Pi 1
/home/magnus/repos/ratatoskr/      # Pi 1
/home/magnus/repos/mimir/          # Pi 2 (nas.local)
```

Deploy all services from the laptop with `make deploy` (from the grimnir repo), or selectively with `make deploy ARGS="munin-memory hugin"`. The script handles git pull, npm install, build (if needed), and systemd restart.

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

| Timer | Schedule | Host | Purpose |
|-------|----------|------|---------|
| `heimdall-collect.timer` | Every 5 min | Pi 1 | Metric collection across both Pis |
| `heimdall-maintain.timer` | Daily 03:00 | Pi 1 | Database maintenance and retention |
| `skuld.timer` | Daily 06:00 | Pi 1 | Morning intelligence briefing |
| `grimnir-security-scan.timer` | Weekly Sun 03:00 | Pi 1 | Dependency audit + secret scan across all repos |

## Service patterns

Every Grimnir service follows these patterns:
- Node.js 20+, TypeScript strict mode
- SQLite for any local state (via better-sqlite3)
- systemd for process management (Restart=always)
- `/health` endpoint for Heimdall monitoring
- `.env` file on Pi for secrets (never in git, never overwritten by deploy)
- `scripts/deploy-pi.sh` for deployment
