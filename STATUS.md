# Grimnir System — Status

**Last session:** 2026-03-31 (late evening)
**Branch:** main

## Completed This Session

### Security patching (all 7 repos)
- `npm audit fix` across munin-memory, hugin, heimdall, skuld, ratatoskr, mimir, fortnox-mcp
- Fixed path-to-regexp (ReDoS) and picomatch (method injection + ReDoS) — both high severity
- All repos at 0 vulnerabilities, committed, pushed, and deployed

### Centralized deploy script
- `scripts/deploy.sh` — deploy all or selective services via SSH
- `make deploy` or `make deploy ARGS="munin-memory hugin"`
- Handles git pull, npm install, build (mimir), systemd restart
- Created `/deploy` skill for Claude Code

### Mimir migration (Pi 2)
- Moved from `~/mimir-server/` (non-git copy) to `~/repos/mimir/` (proper git clone via Pi 1)
- SSH key pair set up between Pi 2 → Pi 1 for git access
- Systemd unit updated, verified healthy

### Global CLAUDE.md cleanup
- Removed stale `meta/workbench` references (replaced March 12 by computed dashboard in `memory_orient`)

### Heimdall alignment check
- All 6 deployable services correctly wired into Heimdall monitoring

## In Progress

### Grimnir benchmark integration
- `src/tasks/grimnir.ts` exists but not wired into `src/tasks/index.ts` or types
- Need to run against GLM, Qwen3-14B, Qwen3.5-35B-A3B + judge the results

## Next Steps

1. **Check Munin outcome data** in ~2 weeks — verify session fix is producing correlated outcomes
2. **Extend prompt capture expiry?** Current hook expires 2026-04-05 (4 days)
3. **Hugin worker mode** — Plan and implement laptop-side Hugin worker
4. **Wire up grimnir benchmark tasks** — add to index.ts, update TaskCategory type, run benchmark
5. **Run Qwen3.5 judges** — quality scores still missing for the MLX model
6. Multi-principal Munin Phase 1 implementation
7. Skuld Phase 4: meeting prep cards
8. Investigate munin-memory secrets scan false positives (7 flagged)

## Blockers
None
