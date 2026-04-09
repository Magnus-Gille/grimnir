# Debate Summary: Hugin Optimization Signals

**Date:** 2026-03-28
**Participants:** Claude Opus 4.6, Codex gpt-5.4
**Rounds:** 2
**Topic:** What optimization signal should Hugin have, and where should it be computed?

## Outcome

**Original proposal (Hugin self-computed success rate) rejected.** Heimdall already computes task success rate. The next signal should be **timeout calibration**, computed in Heimdall from existing Munin task data.

## Concessions accepted by both sides

1. **Heimdall already has success rate** — `getTaskSuccessRate()` exists and renders a badge. Hugin-side duplication withdrawn.
2. **Journal can't support the proposed schema** — missing type tags, parse failures not journaled, stale-recovery failures not journaled.
3. **Schema was over-designed** — 9 analytic concepts for ~20 data points in a 2-day-old journal.
4. **Thermometer reframing is valid** — dispatcher emits raw facts, monitor computes trends. Hugin owns analytics only when it has an actuator to consume them.
5. **Timeout calibration > success rate** as the next signal — closer to a real control loop, uses data already collected.

## Defenses accepted by Codex

1. **Munin as publication layer** — valid for cross-environment access (Skuld, Desktop, Mobile). Accepted as distribution, not computation.

## Unresolved / Deferred

1. **Journal fidelity** — adding type tags and journaling all failure modes. Valid cleanup but not prerequisite for timeout calibration.
2. **Existing Heimdall metric bug** — `getTaskQueueMetrics()` parses runtime tag as duration. Should be fixed before adding new metrics.
3. **Munin summary metadata** — any published summary needs `computed_at`, `window`, `sample_size`, `source`.

## Final agreed plan

**Single most important next step:** Choose Munin task state/result as the authoritative input and implement the smallest Heimdall-side timeout-calibration metric.

Concrete steps (in order):
1. **Fix existing bug** — `getTaskQueueMetrics()` runtime parsing in Heimdall
2. **Add timeout calibration metric** — read duration/timeout from Munin task results (existing data), compute: timeout ratio, over-80% tasks, under-20% tasks
3. **Display on Hugin card** — extend existing dashboard widget
4. **Optional: publish to Munin** — write compact summary to `infrastructure/hugin-signals` with metadata
5. **Deferred:** Hugin journal expansion (type tags, failure journaling) — revisit when a specific metric needs it
6. **Deferred:** Hugin-local signal computation — revisit when an actuator (auto-timeout adjustment) is designed

## Debate files

- `debate/hugin-signals-claude-draft.md`
- `debate/hugin-signals-claude-self-review.md`
- `debate/hugin-signals-codex-critique.md`
- `debate/hugin-signals-claude-response-1.md`
- `debate/hugin-signals-codex-rebuttal-1.md`
- `debate/hugin-signals-critique-log.json`
- `debate/hugin-signals-summary.md`

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1   | ~3m             | gpt-5.4       |
| Codex R2   | ~3m             | gpt-5.4       |
