# Hugin Worker Mode — Debate Summary

**Date:** 2026-03-31
**Participants:** Claude Opus 4.6 vs Codex (GPT-5.4)
**Rounds:** 2
**Critique points:** 11 (1 critical, 8 major, 2 minor)
**Self-review catch rate:** 2/11 (18%)

## Outcome

The original plan to build Hugin worker mode was **deferred in favor of a phased approach**. The debate established that the primary use case (laptop Ollama inference) is already served by the existing `OLLAMA_LAPTOP_URL` remote dispatch, and that the worker mode as proposed had underestimated complexity in several areas.

## Key concessions

1. **CAS safety was overstated** — safe in practice due to single-process sync writes, not DB-level guarantees
2. **Remote Ollama already works** — the #1 motivation was already served
3. **Worker mode is more complex than drafted** — head-of-line blocking, heartbeat collision, stale recovery, query strategy, path portability all need addressing
4. **`Worker: pi | laptop` leaks infrastructure** — capability-based routing is the right abstraction when needed
5. **No framework needed** — both sides agree LangChain/CrewAI add nothing here

## Revised plan (agreed)

### Phase 1: Optimize what exists (now)
- Surface invocation journal metrics in Heimdall (host_effective, latency, fallback rates)
- Review real data before changing host selection policy
- Add periodic stale task reaper (currently startup-only)

### Phase 2: Make Hugin portable (next)
- Eliminate hardcoded `/home/magnus/` paths (4+ locations)
- Remove forced `HOME=/home/magnus` in executor environments
- Make Git identity and post-task push portable (not just grimnir-bot)
- Extract `TaskRunner` from monolithic index.ts
- Make `repo:<name>` resolution use `HUGIN_WORKSPACE` consistently

### Phase 3: Worker mode (when operationally needed)
- Gate: remote Ollama proves insufficient, Pi-failure tolerance needed, or non-Ollama off-Pi execution required
- Worker identity + per-worker heartbeats
- Capability-based task routing (not machine names)
- Multi-candidate query strategy
- Worker registration in Munin

## Unresolved

- Whether laptop-first Ollama default is better (needs data from Phase 1 metrics)
- Exact trigger for Phase 3 (hardware arrival alone is not sufficient)

## Framework verdict

No framework adoption. LangGraph is the only one worth revisiting, and only if Hugin evolves toward durable multi-step workflows.

## Debate files

- [Draft](hugin-worker-claude-draft.md)
- [Self-review](hugin-worker-claude-self-review.md)
- [Codex critique R1](hugin-worker-codex-critique.md)
- [Claude response R1](hugin-worker-claude-response-1.md)
- [Codex rebuttal R2](hugin-worker-codex-rebuttal-1.md)
- [Critique log](hugin-worker-critique-log.json)

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1   | ~3m             | gpt-5.4       |
| Codex R2   | ~2m             | gpt-5.4       |
