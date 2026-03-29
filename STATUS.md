# Grimnir System — Status

**Last session:** 2026-03-29
**Branch:** main

## Completed This Session

### Skills sync investigation
- Confirmed skills live in `~/.claude/skills/` (separate `claude-skills` git repo), not in grimnir
- Verified Pi (`huginmunin.local`) has grimnir repo — was 4 commits behind, pulled up to `800f6d5`
- Compared all 13 skills between laptop and Pi — all match
- Discussed symlinking skills into grimnir for unified sync — **parked** (existing `claude-skills` repo already provides git tracking)
- Ran `/insights` — 69 sessions over 9 days, top friction: wrong initial approach (22 events), recurring git drift on Pi

## Security Review — Remaining Items

| # | Recommendation | Status |
|---|---|---|
| 1 | Hugin task submitter allowlist | Done (`c6f9dd8`) |
| 2 | Harden secret detection regex | Done (`c611213`) |
| 3 | Per-service Munin tokens | Open — architecture change across repos |
| 4 | Redact Tailscale IPs | Done (`2a4ccc5`) |
| 5 | Harden shell interpolation | Done (`2a4ccc5`) |

## Next Session — Recommended Order

### 1. Persona interview #2 — verify MCP injection (15 min)
Submit a persona interview targeting Munin read/write. The main question: do task-spawned agents now get native MCP tools? If yes, the #1 finding from interview #1 is resolved. If no, debug the SDK `mcpServers` option.

### 2. Timeout calibration check (5 min)
Check Heimdall dashboard — is the calibration row showing data? If parsing is wrong (no tasks with Duration in result), fix the regex in `getTimeoutCalibration()`.

### 3. Implement Hugin timeout actuator (if calibration data looks good)
The debate concluded: "revisit Hugin-local signals when an actuator exists." If calibration shows many under-utilized tasks, build a simple default timeout recommender. This closes the loop from signal → action.

### 4. Skuld systemd timer
Skuld currently runs on-demand. A `skuld.timer` for daily 06:00 runs is the next operational step (from architecture.md roadmap). Skuld could also reference timeout calibration in briefings.

### 5. Per-service Munin tokens (security #3)
Scope Munin API keys per service (read-only for Heimdall, read-write for Hugin). Requires Munin-side changes first.

### 6. Extend auto-deploy to remaining services
Hugin and Heimdall have path watchers. Munin, Ratatoskr, Skuld, and Mimir don't. Same pattern.

### Lower priority
- If pursuing Syn, implement a minimal deterministic scan from `grimnir/scripts/` and write provenance-rich results to Munin before considering any separate component
- Munin query error messages — small fix, improves agent DX
- Fortnox integration in Skuld (Phase 2 of Skuld roadmap)

## Blockers
None
