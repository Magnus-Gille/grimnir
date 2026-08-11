# Scheduled Tasks Registry

> All automated tasks running on Grimnir infrastructure.
> Last updated: 2026-07-13.

---

## Overview

All scheduled tasks run on Pi 1 (huginmunin) via systemd timers, except where noted. Timer units usually live under `systemd/`, but root-level `{name}.service` / `{name}.timer` files are also supported by `scripts/deploy.sh`. Declared timer inventory lives in `services.json`.

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

### Heimdall Boot and Alert Reconciliation

| Field | Value |
|-------|-------|
| **Schedule** | Initial `OnBootSec=90`, then `OnUnitInactiveSec=5m` after each reconciliation run becomes inactive |
| **Registry semantics** | Recurring (default) — restarted on deploy and accepted only with a concrete next trigger |
| **Unit** | `heimdall-boot-check.timer` / `heimdall-boot-check.service` |
| **Repo** | `heimdall` |
| **Purpose** | Probe required services after startup settles, then reconcile the alert lifecycle every five minutes |
| **Output** | Heimdall events/alerts in `~/.heimdall/heimdall.db` |
| **Why it exists** | Detect failed services after boot and keep subsequent failure/recovery alerts current |

### Skuld Daily Briefing

| Field | Value |
|-------|-------|
| **Schedule** | Daily 06:00 UTC (+5 min jitter) |
| **Unit** | `skuld.timer` / `skuld.service` |
| **Repo** | `skuld` (Magnus-Gille) |
| **Purpose** | Synthesize calendar, project state, and Munin context into a morning briefing via Claude API |
| **Output** | Munin: `briefings/daily/{date}` and `briefings/latest`; Heimdall renders `/briefing` |
| **Why it exists** | Morning orientation — what's on today, what changed overnight, what needs attention |

### Retired: Hugin Daily Journal Analysis

The legacy LLM journal-summary workload was retired by
[hugin#325](https://github.com/Magnus-Gille/hugin/pull/325), merged as Hugin `a782c6b`. On
2026-07-26 the system-scope units were disabled and stopped on `huginmunin`, both unit files were
removed, and systemd was reloaded. Post-change evidence was:

- `systemctl is-enabled hugin-daily-analysis.timer` → `not-found`
- `systemctl is-active hugin-daily-analysis.timer` → `inactive`
- timer file: absent (`/etc/systemd/system/hugin-daily-analysis.timer`)
- service file: absent (`/etc/systemd/system/hugin-daily-analysis.service`)

Grimnir now omits the timer from `services.json`; the matching placement fixtures describe only the
surviving Hugin service. This retirement closes the owner action filed as
[hugin#324](https://github.com/Magnus-Gille/hugin/issues/324). The workload was not a telemetry
aggregation or self-improvement mechanism: structured operational health belongs to Heimdall, while
governed task and inference evidence follows
[`observability-and-improvement.md`](observability-and-improvement.md) and the
LearningTaskContract.

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

The service must have an authoritative Git checkout for every `scan: true`
repository beneath its configured checkout root. The scanner materializes each
checked-out commit into a private snapshot and audits that snapshot; it does
not scan deployment trees or claim deployment/runtime integrity. A missing
checkout, unreadable commit, or unusable audit result makes the entire run
incomplete and non-zero rather than silently omitting a repository.

### Claude CLI Update

| Field | Value |
|-------|-------|
| **Schedule** | Daily 04:00 local time |
| **Trigger** | cron (not systemd) |
| **Purpose** | Keep Claude CLI on the Pi up to date |
| **Output** | syslog (`hugin-update` tag) |
| **Why it exists** | Hugin tasks depend on a recent Claude CLI; manual updates are easy to forget |

---

> **OS patching and maintenance reports** (OS Maintenance Report, npm Dependency Report,
> unattended-upgrades config and setup) have moved to the **brokkr** repo. The timers
> `brokkr-maintenance-os` (daily 07:00) and `brokkr-maintenance-deps` (Mon 02:10) now run
> on huginmunin from `brokkr/`. See `brokkr/CLAUDE.md` and `brokkr/scripts/`.

## Adding a new scheduled task

1. Create the script in the relevant repo's `scripts/` directory.
2. Create `systemd/{name}.service` (Type=oneshot) and `systemd/{name}.timer` in the same repo, or root-level `{name}.service` / `{name}.timer` if that repo already uses root-level units.
3. Add the timer to the owning component's `systemd_units` in `services.json`.
4. Update this document.
5. Deploy the owning component — `scripts/deploy.sh` installs every declared unit, runs `daemon-reload`, and enables timers automatically. No manual systemctl step should be needed.
