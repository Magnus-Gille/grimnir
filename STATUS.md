# Grimnir System — Status

**Last session:** 2026-03-29
**Branch:** main

## Completed This Session

### Heimdall deploy drift UI wiring (`d29e3fc` in heimdall)
- `getDriftHistory()` query in db.js — window ROW_NUMBER() over service_versions, last N samples per service
- `deployDriftHistoryCard()` in html.js �� collapsible `<details>` per service, last 2h of 5-min samples with status badges
- Wired into `/deployments` page via `deploymentsFullCard(data, driftRows)`
- Sustained-drift alerting in collector.js — fires warning alert when service behind for 3+ consecutive checks (~15 min), auto-resolves
- 5 files changed, 88 insertions

## Also Discussed

### SCION patterns reassessment
- Reviewed Hugin task history: 50+ tasks in 2 weeks (Mar 14–23), including 1 timeout kill (7200s) and long-running tasks (12-22 min)
- Black-box problem IS real at current usage volume — previous assessment that "it's not happening yet" was wrong
- SCION Phase A1+A2 (phase transitions, ~6h) would be high-value next step for observability

## Security Review — Remaining Items

| # | Recommendation | Status |
|---|---|---|
| 1 | Hugin task submitter allowlist | Done (`c6f9dd8`) |
| 2 | Harden secret detection regex | Done (`c611213`) |
| 3 | Per-service Munin tokens | Open — architecture change across repos |
| 4 | Redact Tailscale IPs | Done (`2a4ccc5`) |
| 5 | Harden shell interpolation | Done (`2a4ccc5`) |

## Next Session — Recommended Order

### 1. SCION Phase A1+A2 — Agent state model (Phase transitions)
High value given task volume. Define phase enum + Munin entry format (A1), emit phase transitions from Hugin lifecycle (A2). ~6h. Plan at `docs/GRIMNIR_DEVELOPMENT_PLAN.md`.

### 2. Review first timer-triggered security scan results (after April 5)
Check Munin for `security/scans/2026-04-05` — verify the timer ran and results were written.

### 3. Triage scan findings
- 10 high-severity dependency vulns across repos — likely shared deps, investigate and bump
- 7 secret findings in munin-memory test files — confirm test fixtures, consider test file allowlist

### 4. Skuld Fortnox integration
Phase 2 of Skuld: invoice aging, revenue pulse, payment status via noxctl.

### Lower priority
- Per-service Munin tokens (security #3)
- Extend auto-deploy to remaining services
- SCION Phase B (worktree isolation) — after A is proven
- SCION Phase C (template chain) — after B

## Blockers
None
