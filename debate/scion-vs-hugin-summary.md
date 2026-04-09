# Debate Summary: Scion vs Hugin Extension for Local Inference Offload

**Date:** 2026-03-31
**Participants:** Claude Opus 4.6, Codex (GPT-5.4)
**Rounds:** 2
**Topic:** Whether to extend Hugin with a laptop worker mode (Path A) or adopt Google's Scion orchestration platform (Path B) for routing tasks to local laptop inference.

## Key Context

- `docs/GRIMNIR_DEVELOPMENT_PLAN.md` already plans three Scion-derived patterns for Hugin (3D state, worktrees, templates)
- Ollama MLX v0.19 makes laptop inference viable (Qwen3-14B on M4 Air)
- Pi can't run models above 3B parameters (RAM/thermal limits)

## Concessions Accepted by Claude

1. **"Order of magnitude" complexity gap** — withdrawn. Hugin worker mode has comparable complexity to Scion Solo once all coordination pieces are counted.
2. **Reimplementation tension** — conceded. The development plan budgets significant effort to build Scion-like primitives inside Hugin while claiming Scion is overbuilt.
3. **Conceptual mismatch** — softened from "architecturally incompatible" to "adds friction for short tasks."

## Defenses Accepted by Codex

1. **Munin as coordination layer** — embedding scheduler semantics in Munin's existing primitives (tags, CAS, queries) is a real operational simplification, even if logical complexity is similar.
2. **Scion maturity risk** — the platform is self-described as "early and experimental." Bidirectional migration risk is real.
3. **Incremental development** — normal and valid, though not sufficient to skip a comparison spike.

## Unresolved Disagreements

1. **Timing asymmetry of migration cost** — Codex argues Hugin-worker semantics harden fast and make later migration expensive. Claude argues Scion adoption risk is also real. Neither side proved their cost estimate.
2. **Decision trigger criteria** — Claude proposed "<30 min setup." Codex argued this is too narrow — should evaluate state integration, failure handling, and operational burden holistically.

## Final Verdict (Both Sides Agree)

**Run a tightly scoped Scion Solo spike against one real laptop Ollama task before implementing any Hugin-worker claim/routing/heartbeat protocol.**

The spike should evaluate:
- Setup friction (install, init, first task)
- Short-task lifecycle fit (fire-and-forget vs persistent session)
- Whether Munin can remain the operator-visible state layer
- Failure handling and recovery clarity
- Actual operational burden vs Hugin equivalent

If the spike shows Scion Solo can cleanly dispatch to local Ollama with acceptable friction, reconsider Path B seriously. If it requires Hub + container infra for the simple use case, Path A is vindicated.

## Action Items

| # | Action | Owner |
|---|--------|-------|
| 1 | Run Scion Solo spike on laptop (2-4h) | Magnus |
| 2 | Test: install Scion, init grove in a test repo, run one Ollama task | Magnus |
| 3 | Evaluate against criteria above, record findings | Magnus |
| 4 | Decision: Path A, Path B, or hybrid based on spike results | Magnus |

## Debate Files

- `debate/scion-vs-hugin-claude-draft.md`
- `debate/scion-vs-hugin-claude-self-review.md`
- `debate/scion-vs-hugin-codex-critique.md`
- `debate/scion-vs-hugin-claude-response-1.md`
- `debate/scion-vs-hugin-codex-rebuttal-1.md`
- `debate/scion-vs-hugin-critique-log.json`
- `debate/scion-vs-hugin-summary.md`

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1 (attempt 1) | ~3m (no output file) | gpt-5.4 |
| Codex R1 (attempt 2) | ~3m | gpt-5.4 |
| Codex R2 | ~2m | gpt-5.4 |
