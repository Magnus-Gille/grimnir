# Grimnir System — Status

**Last session:** 2026-03-29
**Branch:** main

## Completed This Session

### 1. Security review of grimnir repo
- Full 3-phase security review: threat model, vulnerability scan, validation
- 2 confirmed findings, 2 theoretical, plus architectural observations
- Produced prioritized remediation list (5 items)

### 2. Hugin task submitter allowlist (security fix #1)
- Added `HUGIN_ALLOWED_SUBMITTERS` env var — rejects tasks from unknown submitters
- Default allowlist: `claude-code,claude-desktop,ratatoskr,claude-web,claude-mobile,hugin`
- Restricted `resolveContext` absolute paths to `/home/magnus/` (was unrestricted)
- Fixed pre-existing SDK executor test (hardcoded Pi-only path)
- Hugin commit `c6f9dd8`

### 3. Hardened secret detection regex (security fix #2)
- Expanded `generate-architecture.sh` secret scan to catch JWT, base64 Bearer, GitHub/GitLab/Slack/AWS tokens
- Fixed unescaped glob in exclusion filter
- Grimnir commit `c611213`

### 4. Redacted Tailscale IPs (security fix #4)
- Removed internal Tailscale IPs from `docs/architecture.md` ahead of making repo public

### 5. Hardened shell interpolation (security fix #5)
- `munin_tool_call` now passes variables via `process.env` instead of shell string interpolation
- Grimnir commit `2a4ccc5`

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
- Reconcile Syn proposal with critique: if pursued, scope to deterministic Phase 1 task first
- Munin query error messages — small fix, improves agent DX
- Fortnox integration in Skuld (Phase 2 of Skuld roadmap)

## Blockers
None
