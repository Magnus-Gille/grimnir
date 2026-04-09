# Debate Summary: Seidr — Agent Context Server

**Date:** 2026-03-30
**Participants:** Claude (Opus 4.6), Codex (GPT-5.4)
**Rounds:** 2
**Topic:** Whether to build Seidr as the next Grimnir component for agent context portability

## Outcome

**Seidr is not the right next step.** Both sides agree the problem is real (Grimnir is too Claude-shaped) but the timing is wrong. The next step should be empirical: build one concrete non-Claude worker, learn what portability actually requires, then decide on the abstraction.

## Concessions Accepted by Claude

1. **Seidr is premature** — building an abstraction boundary before having a second consumer means choosing the shape blind. (Self-review caught this but underweighted it.)
2. **"Portable skills" as proposed are fake portability** — execution strategies are scaffolding-specific. Only intent, constraints, and capability requirements are truly portable. The YAML-skill idea was a category error.
3. **MCP-only contradicts model-agnosticism** — if a portability layer ever exists, it should be HTTP REST with MCP as an adapter, not MCP-only.
4. **Munin can carry conventions for now** — no new service needed to make conventions visible outside Claude Code.
5. **Multi-agent coordination belongs in Hugin** — the execution layer owns leasing, ownership, cancellation. Seidr was conflating context distribution with coordination semantics.

## Defenses Accepted by Codex

1. **The warning is valid** — Grimnir is Claude-shaped and context portability will eventually matter.
2. **SCION and Seidr are orthogonal** — different problem classes, not competing priorities (though SCION has higher near-term observed value).
3. **Context distribution is distinct from coordination** — "who am I" is a different problem from "who owns this task."

## Unresolved Disagreements

1. **Experiment design** — Codex pushed hard that the first non-Claude worker must exercise real portability boundaries (conventions, capability discovery, tool discipline), not just easy tasks like summarization. Claude acknowledged but hasn't committed to specific experiment criteria.
2. **Decision gates** — No explicit criteria defined for when findings would justify Munin-only vs shared library vs Hugin extensions vs Seidr.

## New Issues from Round 2

- Model independence (ollama) and scaffolding independence (non-Claude worker) are different categories of evidence — the plan initially conflated them.
- A weak first experiment could produce false confidence; experiment selection matters.
- Skills audit should be grounded by implementation experience, not done as a desk taxonomy first.

## Final Agreed Next Steps

1. **Build one concrete non-Claude worker** for one real Grimnir task, end-to-end, using Munin + repo docs directly. No new abstraction layer.
   - The worker IS the experiment (ollama is just the model supply)
   - Task must exercise: context bootstrap, conventions, capability assumptions, task execution discipline
2. **Document exactly what broke** — what had to be duplicated, what could stay as documents, what genuinely wanted runtime support
3. **Measure Pi 1 headroom** under real Hugin load
4. **Define decision gates** — explicit criteria for what findings justify which abstraction level
5. **Then decide** — Munin documents, shared library, Hugin extension, or Seidr

## Skill Portability Taxonomy (from debate)

| Layer | Portable? | Examples |
|-------|-----------|---------|
| Intent | Yes | "review this PR", "draft an email", "check calendar" |
| Constraints | Yes | "use conventional commits", "never commit .env files" |
| Capability requirements | Yes | "needs file read", "needs shell", "needs network" |
| Execution strategy | No | "use Edit tool to modify X", "spawn Agent subagent" |

## All Debate Files

- `debate/seidr-architecture-claude-draft.md`
- `debate/seidr-architecture-claude-self-review.md`
- `debate/seidr-architecture-codex-critique.md`
- `debate/seidr-architecture-claude-response-1.md`
- `debate/seidr-architecture-codex-rebuttal-1.md`
- `debate/seidr-architecture-critique-log.json`
- `debate/seidr-architecture-summary.md`

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1   | ~2m             | gpt-5.4       |
| Codex R2   | ~2m             | gpt-5.4       |
