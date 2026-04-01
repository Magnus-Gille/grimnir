# Grimnir System — Status

**Last session:** 2026-04-01
**Branch:** main

## Completed This Session

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

1. **Deploy grimnir + heimdall to Pi** — `make deploy` to activate registry + validation timer
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
