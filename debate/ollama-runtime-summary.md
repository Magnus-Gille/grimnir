# Debate Summary: Ollama Runtime for Hugin

**Date:** 2026-03-30
**Participants:** Claude (Opus 4.6), Codex (GPT-5.4)
**Rounds:** 2
**Topic:** Implementation plan for adding ollama as a third Hugin runtime

## Outcome

**The plumbing design is ready to implement with revisions. The experiment design needs tightening before the harder task is run.**

Both sides agree on the overall direction: extend Hugin with an ollama executor, don't build a new service. The debate improved six concrete design decisions.

## Concessions Accepted by Claude

1. **Measure Pi RAM before building** — transient overlap (ollama model + Claude SDK subprocess) is the real risk, not steady-state daemon RSS. Gate on measurement.
2. **Fallback only for infra failures** — auto-fallback restricted to unreachable/5xx/DNS. Semantic inadequacy is an experiment result, not a retry condition.
3. **Lazy host resolution** — no background polling. Pi is static; laptop resolved lazily with 3s timeout + 5min negative cache.
4. **Streaming** — match Hugin's existing operational contract (incremental logs, partial capture on timeout).
5. **Journal analysis = smoke test** — not the portability experiment. A harder task must follow.
6. **Context-refs in task schema** — task producer names specific Munin entries to inline; Hugin does mechanical fetch-and-paste, no semantic policy.

## Defenses Accepted by Codex

1. **Deferring full executor refactoring** — build ollama executor as clean reference, don't refactor SDK/spawn in same PR. Valid scope control.
2. **Keeping laptop support** — lazy resolution is trivial; removing it entirely loses the "bigger model when available" test.

## Unresolved / Acknowledged for Implementation

1. **Name the harder experiment task before implementation** — Codex insists this shapes what metadata the runtime must preserve. Candidate: Munin stale-status review using conventions + project context.
2. **Context-refs contract** — needs precise spec: ref syntax, serialization order, missing-ref behavior, truncation logging.
3. **RAM admission rule** — measurement alone isn't enough; the runtime should check available memory before loading a model (or at minimum, log it).
4. **Journal schema** — needs: `host_requested`, `host_effective`, `model_effective`, `context_refs_requested`, `context_refs_resolved`, `truncation_status`.
5. **Laptop usage discipline** — keep Pi-only for the first experiment batch; laptop explicitly opt-in and clearly logged.

## Key Design Principle from Debate

> **"Do not blur the experiment with hidden policy."**
> No silent semantic fallback, no implicit host switching, no opaque context assembly. If the runtime succeeds or fails, the system must be able to say exactly which host, model, and context bundle produced that result.

## All Debate Files

- `debate/ollama-runtime-claude-draft.md`
- `debate/ollama-runtime-claude-self-review.md`
- `debate/ollama-runtime-codex-critique.md`
- `debate/ollama-runtime-claude-response-1.md`
- `debate/ollama-runtime-codex-rebuttal-1.md`
- `debate/ollama-runtime-critique-log.json`
- `debate/ollama-runtime-summary.md`

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1   | ~3m             | gpt-5.4       |
| Codex R2   | ~2m             | gpt-5.4       |
