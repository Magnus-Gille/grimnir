# Grimnir System — Status

**Last session:** 2026-04-09
**Branch:** main

## Completed This Session

### Ecosystem review plan — post-debate, committed
- Drafted cross-repo review plan for the 9-repo Grimnir system (divergent MuninClients, heimdall's hand-rolled JSON-RPC call sites, skuld's direct SQLite coupling, missing contract ownership)
- Stress-tested via Codex debate (2 rounds, 15 critique points, 33% self-review catch rate)
- Collapsed original 5-phase program to Step 0 + Phase A + Phase B + conditional Phase C
- Plan committed to `docs/ecosystem-review-plan.md`
- Tracking issue: Magnus-Gille/grimnir#7 (added to Grimnir Roadmap project)
- Munin index entry at `projects/grimnir/ecosystem-review-plan` for cross-environment discoverability

### Debate corpus now tracked in git
- Upgraded `.gitignore` from "ignore all `debate/`" to track `INDEX.md`, `*-summary.md`, `*-critique-log.json`
- Pulled 14 existing debate summaries + critique logs into git history
- Rationale: enables cross-debate pattern recognition (catch-rate trends, severity distribution) without committing raw drafts/rebuttals

### Debate-codex skill updated
- Git Handling section rewritten to match the new default pattern
- Rationale and two exception cases documented
- Change is in the skills repo HEAD (pushed)

### Commits
- `62c3130` docs: commit ecosystem review plan and debate summaries

## Next Steps

1. **Step 0 — Write cross-service contracts section in `docs/architecture.md`** (grimnir#7). This blocks everything else in the ecosystem review program. Named contracts, named owners per contract, regression matrix, evolution rules.
2. **Phase A — Integration fixes** (2-3 sessions). MuninClient copy for Ratatoskr, CommonJS adapter for Heimdall, Skuld interface wrap, three contract tests, per-file contract ownership comments.
3. **Phase B — Targeted `/security-review`** (3 sessions, concurrent with A). munin-memory first (sharded), ratatoskr next, hugin after Phase A #1 stabilizes. Draft `docs/threat-model.md` afterward.
4. **Phase C — Minimum CI floor** (1 session, conditional). Only if Phase A tests aren't already catching drift.
5. Review OpenClaw research spike results (`tasks/20260407-203751-openclaw-vs-grimnir`)
6. **heimdall#7** — Boot health check
7. **hugin#26** — Plan autonomous dependency bump workflow
8. **grimnir#5** — Plan doc drift detection
9. **Hugin security hardening** — issues #7–#13
10. **UPS for both Pis** — grimnir#4

## Blockers
- None
