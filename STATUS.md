# Grimnir System — Status

**Last session:** 2026-04-02
**Branch:** main

## Completed This Session

### Hugin v2 pipeline orchestrator plan
- Designed architecture for evolving Hugin from flat task dispatcher to multi-phase pipeline orchestrator
- Researched landscape: Portkey Gateway, LiteLLM, RouteLLM, LangGraph, Conductor, CrewAI, AutoGen, etc.
- Key finding: no single project covers all needs; privacy-aware routing is unsolved in open source
- Investigated Pi AI HAT+ — rejected for LLMs (CPU outperforms the accelerator)
- Created initial plan: `docs/hugin-v2-pipeline-orchestrator.md`
- Debated with Codex (2 rounds, 15 critique points, 33% self-review catch rate)
- Major amendments from debate:
  - Three sequential bets (workflow → routing → methodology) instead of one 8-step roadmap
  - Markdown compiles to validated JSON IR (not executed directly)
  - Monotonic sensitivity propagation (no phase-level downgrades)
  - Authority model added alongside confidentiality (side effects are gated by default)
  - Router is opt-in (`Runtime: auto`), not a replacement of all dispatch
  - Templates versioned in git, not mutable Munin state
  - Success gates defined per bet
  - OpenRouter, eval routing, Mac Studio deferred
- Updated plan with all debate outcomes

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

### Deployment completion
- Deployed `grimnir` from `main` to `huginmunin` via `./scripts/deploy.sh grimnir`
- Installed and enabled `grimnir-validate.timer`; next scheduled run is Thu 2026-04-02 04:30 CEST
- Smoke-tested the on-host registry query from `/home/magnus/repos/grimnir`

## Next Steps

1. **Hugin Step 1: parent/child joins** — implement the already-specced dependency tracking
2. **Hugin Step 2: pipeline IR + compiler** — Zod schema, markdown→JSON compilation
3. **Retry Ollama laptop task** on stable WiFi — verify end-to-end streaming works
4. **Measure grimnir staleness** — collect data from validation runs before choosing sync cadence
5. **Heimdall registry alignment** — long-term: have Heimdall read from `services.json` instead of its own config
6. **Hugin host metrics in Heimdall** — surface invocation-journal data (Phase 1 from debate)
7. **Hugin portability audit** — remove Pi-only paths, portable Git identity (Phase 2)
8. **Run Qwen3.5 judges** — quality scores still missing
9. Multi-principal Munin Phase 1
10. Skuld Phase 4: meeting prep cards

## Blockers
- WiFi instability affecting Ollama streaming over Tailscale (transient)
