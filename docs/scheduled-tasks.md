# Scheduled Tasks Registry

> All automated tasks running on Grimnir infrastructure.
> Last updated: 2026-03-30.

---

## Overview

All scheduled tasks run on Pi 1 (huginmunin) via systemd timers, except where noted. Timer units live in each service's repo under `systemd/`. Heimdall monitors all timers via its Deploy Status card.

---

## Tasks

### Heimdall Metric Collection

| Field | Value |
|-------|-------|
| **Schedule** | Every 5 minutes |
| **Unit** | `heimdall-collect.timer` / `heimdall-collect.service` |
| **Repo** | `heimdall` |
| **Purpose** | Collect CPU, memory, disk, temperature, service health, and backup status from both Pis |
| **Output** | SQLite (`~/.heimdall/heimdall.db`) — `metrics`, `events`, `alerts` tables |
| **Why it exists** | Core data pipeline for the Heimdall dashboard |

### Heimdall DB Maintenance

| Field | Value |
|-------|-------|
| **Schedule** | Daily 03:00 |
| **Unit** | `heimdall-maintain.timer` / `heimdall-maintain.service` |
| **Repo** | `heimdall` |
| **Purpose** | Rebuild indexes, prune old metrics (retention policy), vacuum SQLite |
| **Output** | Modified SQLite DB (smaller, faster queries) |
| **Why it exists** | Without pruning, the metrics table grows unbounded on the Pi's SD card |

### Skuld Daily Briefing

| Field | Value |
|-------|-------|
| **Schedule** | Daily 06:00 UTC (+5 min jitter) |
| **Unit** | `skuld.timer` / `skuld.service` |
| **Repo** | `skuld` (grimnir-bot org) |
| **Purpose** | Synthesize calendar, project state, and Munin context into a morning briefing via Claude API |
| **Output** | Munin: `briefings/daily/{date}`, web UI at :3040 |
| **Why it exists** | Morning orientation — what's on today, what changed overnight, what needs attention |

### Hugin Daily Journal Analysis

| Field | Value |
|-------|-------|
| **Schedule** | Daily 07:00 UTC (+5 min jitter) |
| **Unit** | `hugin-daily-analysis.timer` / `hugin-daily-analysis.service` |
| **Repo** | `hugin` |
| **Script** | `scripts/submit-daily-analysis.sh` |
| **Purpose** | Summarize Hugin's invocation journal from the last 24h — task counts, success rates, durations, costs, anomalies |
| **Runtime** | ollama (`qwen2.5:3b`) with Claude fallback |
| **Output** | Munin task: `tasks/{id}-daily-analysis` |
| **Why it exists** | Daily canary for the ollama runtime pipeline + operational visibility into Hugin activity |

### Security Scan

| Field | Value |
|-------|-------|
| **Schedule** | Weekly, Sunday 03:00 UTC (+10 min jitter) |
| **Unit** | `grimnir-security-scan.timer` / `grimnir-security-scan.service` |
| **Repo** | `grimnir` |
| **Script** | `scripts/security-scan.sh` |
| **Purpose** | Run `npm audit` and secret detection across all Grimnir repos |
| **Output** | Munin: `security/scans/{date}`, per-repo results in `security/repos/*` |
| **Why it exists** | Automated dependency vulnerability and secret leak detection |

### Claude CLI Update

| Field | Value |
|-------|-------|
| **Schedule** | Daily 04:00 local time |
| **Trigger** | cron (not systemd) |
| **Purpose** | Keep Claude CLI on the Pi up to date |
| **Output** | syslog (`hugin-update` tag) |
| **Why it exists** | Hugin tasks depend on a recent Claude CLI; manual updates are easy to forget |

---

## Adding a new scheduled task

1. Create the script in the relevant repo's `scripts/` directory.
2. Create `systemd/{name}.service` (Type=oneshot) and `systemd/{name}.timer` in the same repo.
3. Add the timer to Heimdall's `heimdall.config.json` as a `"type": "timer"` service entry.
4. Update this document.
5. Deploy: copy units to `/etc/systemd/system/`, `daemon-reload`, `enable --now`.
