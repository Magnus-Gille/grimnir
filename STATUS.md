# Grimnir System — Status

**Last session:** 2026-06-11
**Branch:** feat/tallriksvis-sandbox (PR #19 still DRAFT, pending Pi-side verification)

## Completed This Session (2026-06-11)

### Merged PR #20 — user-scoped systemd units in deploy.sh
- `fix(deploy): support user-scoped systemd units` — squash-merged to `main` (`c5f5303`), branch `fix/deploy-user-units` deleted
- Adds optional `systemd_units[].scope` (`"user"` for `hugin`/`verdandi`, `"system"` default); `registry.js` emits a 7th `unit_scope` field; `deploy.sh` syncs user units to `~/.config/systemd/user` and restarts via `systemctl --user` — no sudo, no destructive stop/disable
- Fixes the live bug where `deploy.sh hugin` took Hugin offline mid-deploy (`5/NOTINSTALLED`)
- Verified before merge: 7-field registry output correct (hugin/verdandi=user, rest=system), `bash -n` clean
- NOTE: local working branch is `feat/tallriksvis-sandbox`; the merge landed remotely, so local `main` is behind until pulled

## Prior Session (2026-05-29)

### Investigation: telemetry/measurement landscape
- Mapped what's actually running vs. just designed across Grimnir:
  - **Munin retrieval measurement**: real and active — `retrieval_events` + `retrieval_outcomes` + live `memory_retrieval_feedback` tool, benchmark harness with 30 reports
  - **Grimnir-wide Execute→Trace→Score→Reflect loop**: design-only (`docs/observability-and-improvement.md`, 2026-04-02) — no trace writer, no `traces/<agent>` data, not built
  - **Hugin task telemetry**: planned (Step 4 of obs doc), not built — Hugin is still on orchestration plumbing (#68 artefact delivery, #77 crash-recovery liveness bug)

### munin-memory eval harness: closed #19, created #70
- Audited #19 checklist: Phases 1 (static benchmark) and 2 (live monitoring) fully shipped — scorer, runner, snapshot script, curated query sets, `npm run benchmark`, report schema v2, `production_ranker` parity, LongMemEval/LoCoMo/BEIR adapters, retrieval_feedback table and tool, `memory_insights` health metrics
- Closed #19 with summary comment
- Created follow-up **munin-memory #70**: "Retrieval eval harness — Phase 3 + CI regression gate"
  - P1: CI regression gate (wire benchmark into ci.yml with pass/fail threshold — highest value)
  - P2: ground-truth pipeline (derive/curate/synthetic query scripts)
  - P3: stretch (memory_retrieval_report tool, LLM-as-judge)
- Added #70 to roadmap board, logged decision to Munin

## Blockers
- **grimnir PR #19** (tallriksvis sandbox): DRAFT, blocked on 4 Pi-side TODOs — confirm static vs backend, read live Caddyfile, confirm deploy path, notify wife of URL change. Cloudflare Access policy must be created before DNS flip.
- **munin-memory synthesis entry**: still tagged `blocked` (paused at PR 4 hard checkpoint from quality-metrics loop) — separate from #19/#70, review when picking up munin-memory work.
- **Hugin #77**: crash-recovery liveness bug (delivery crash + auto-restart doesn't auto-reconcile) — blocks declaring #68 e2e fully green.

## Next Steps

1. **munin-memory #70 P1** — Wire benchmark into CI (`.github/workflows/ci.yml`) with a committed baseline report and pass/fail threshold on R@5/nDCG@5
2. **grimnir PR #19** — SSH to huginmunin, fill in the 4 TODOs, create CF Access policy, then un-draft and merge
3. **Hugin #77** — fix crash-recovery liveness, re-run S3, then close #68 e2e
4. **Hugin next** — enable broker (scripts/enable-broker.sh), register hugin-mcp, dogfood /delegate
5. **Grimnir obs loop Step 1** — trace writer library (shared module) is unbuilt; nothing downstream of it works until it exists
6. Verify grimnir-validate.timer installed on Pi (`systemctl list-timers | grep grimnir-validate`)
7. grimnir#7 — Write cross-service contracts section in `docs/architecture.md`
