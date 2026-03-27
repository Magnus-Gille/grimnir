# Grimnir System — Status

**Last session:** 2026-03-27
**Branch:** main

## Completed This Session

### Heimdall — Projects Tab (Pi task)
- New `/projects` page pulling from Munin `projects/*` namespace
- Groups by lifecycle (active, maintenance, stopped, completed, archived)
- Parses structured markdown sections (Vision, Current Work, etc.)
- 5-minute Munin cache, HTMX auto-refresh
- Commit `6ee2f49` on heimdall

### Heimdall — Deployments Tab (Pi task)
- New `/deployments` page with full Pi audit
- Services grid (6 Grimnir services, incl. mimir via SSH to Pi 2)
- Git repo status, node process audit, orphan detection
- Cleanup suggestions (stale scratch, old logs, merged branches)
- 10-minute collection cycle
- Commit `bbaaeb6` on heimdall

### Architecture Generator (Pi task)
- `scripts/generate-architecture.sh` in grimnir repo
- Generates `docs/full-architecture.md` (2121 lines, 77KB)
- Pulls from all 7 component repos, Munin, systemd, env files
- `make docs` convenience target
- Commit `16f8bb9` on grimnir (Pi local — not yet on GitHub)

### Munin Project Status Formalization
- All 13 active project entries updated with structured headers: `## Vision`, `## Current Work`, `## Blockers`, `## Next Steps`, `## Roadmap`
- Tombstoned `projects/jarvis-architecture` (duplicate of grimnir)
- Tombstoned `projects/fortnox-mcp` (canonical is noxctl)
- Fixed `projects/mimir` conflicting lifecycle tags → maintenance
- Fixed `projects/munin-memory` → maintenance

### Configuration
- Added WebFetch/WebSearch auto-accept to global settings
- Added model selection guidance to CLAUDE.md (haiku/sonnet/opus tiers)

## Pending Tasks (submitted to Pi)
- `20260326-080000-heimdall-projects-polish` — Visual redesign of projects page
- `20260326-080000-heimdall-action-buttons` — Fix/restart/deploy/clean buttons on deployments page

## Blockers
- Pi task `16f8bb9` (arch generator commit) is on Pi's local grimnir repo but not pushed to GitHub — Pi may have different remote URL. Need to verify and push.

## Next Steps
- Check results of pending Heimdall polish + action buttons tasks
- Verify arch generator commit lands on GitHub
- Formalize remaining project statuses (playdate-game, hackathon-web, sovereign-ai-compliance) — low priority, already structured
- Re-run `make docs` after Heimdall changes land to get updated architecture doc
