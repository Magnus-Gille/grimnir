# Grimnir System — Status

**Last session:** 2026-04-01
**Branch:** main

## Completed This Session

### Centralized deploy contract hardening
- Fixed the Grimnir centralized deploy model to match the documented rsync-from-laptop flow instead of remote `git pull`
- `services.json` now carries explicit `deploy_path` values for deployable services, including real exceptions:
  - `munin-memory` -> `/home/magnus/munin-memory`
  - `mimir` -> `/home/magnus/mimir-server`
- Corrected `needs_build` flags for services that run from untracked `dist/` artifacts:
  - `munin-memory`, `hugin`, and `ratatoskr` now marked `true`
- `scripts/deploy.sh` now:
  - reads `repo`, `host`, `deploy_path`, `unit_type`, `needs_build` from the registry
  - deploys the local working tree via `rsync` instead of relying on whatever branch is checked out on the Pi
  - runs local builds for `needs_build` services before syncing
  - preserves `.env` on the target host and restarts primary service units after sync
  - resolves `.local` hosts with a Tailscale fallback, mirroring the repo-local Munin deploy behavior
  - accepts per-invocation source overrides such as `munin-memory=/tmp/munin-memory-awesome` so worktree deploys are explicit and deterministic
- Updated `docs/conventions.md` and `docs/authority.md` so deploy paths and the rsync-based centralized flow are the documented contract
- Verified with:
  - `bash -n scripts/deploy.sh`
  - `REGISTRY_PATH=services.json QUERY=deploy node --input-type=commonjs scripts/lib/registry.js`
  - `./scripts/deploy.sh munin-memory=/tmp/munin-memory-awesome`
  - `ssh magnus@huginmunin curl -s http://127.0.0.1:3030/health` -> `{"status":"ok"}`

### Centralized service registry (services.json)
- Created `services.json` at repo root — single source of truth for all 8 Grimnir components
- Created `scripts/lib/registry.js` — proper Node.js helper (env vars, error handling, --input-type=commonjs)
- Refactored `deploy.sh`, `security-scan.sh`, `generate-architecture.sh` to read from registry
- Zero hardcoded service lists remain in scripts
- Updated `authority.md`: services.json owns ports, hosts, units, component inventory
- Updated `conventions.md`: removed duplicated port table and deploy paths, references registry
- Debated with Codex (2 rounds): resolved fortnox-mcp modeling question, node -e safety, authority split
- Commit 5f0b865

### Daily registry validation (--validate)
- Added `--validate` flag to `generate-architecture.sh`: read-only, host-aware (SSH for Pi 2), writes results to Munin
- Created `systemd/grimnir-validate.timer` + `.service` — daily at 04:30 before Skuld's 06:00 briefing
- Added `grimnir-validate` to Heimdall config (`heimdall.config.json`) for dashboard visibility
- Debated with Codex (2 rounds): killed hourly sync timer, killed standalone validator, narrowed to generator --validate mode
- Commits: 5f0b865 (grimnir), 68b214d (heimdall)

### Key decisions (from debates)
- Registry covers ALL components (not just deployed services) — fortnox-mcp included with null host
- No hourly git pull — measure staleness first, choose cadence from data
- No standalone validate-registry.sh — reuse generator's collection path
- Heimdall still has its own config (heimdall.config.json) separate from services.json — long-term alignment deferred
- Auto-remediation deferred — detect + report first

## Next Steps

1. **Deploy grimnir to Pi** — ship the centralized deploy-script fix itself
2. **Install grimnir-validate timer on Pi** — `sudo systemctl enable --now grimnir-validate.timer`
3. **Retry Ollama laptop task** on stable WiFi — verify end-to-end streaming works
4. **Measure grimnir staleness** — collect data from validation runs before choosing sync cadence
5. **Heimdall registry alignment** — long-term: have Heimdall read from services.json instead of its own config
6. **Hugin host metrics in Heimdall** — surface invocation-journal data (Phase 1 from debate)
7. **Hugin portability audit** — remove Pi-only paths, portable Git identity (Phase 2)
8. **Run Qwen3.5 judges** — quality scores still missing
9. Multi-principal Munin Phase 1
10. Skuld Phase 4: meeting prep cards

## Blockers
- WiFi instability affecting Ollama streaming over Tailscale (transient)
- grimnir-validate.timer not yet installed on Pi (needs deploy + enable)
