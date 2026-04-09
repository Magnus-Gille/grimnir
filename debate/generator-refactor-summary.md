# Debate Summary: Generator Refactor

**Date:** 2026-03-28
**Participants:** Claude Opus 4.6, Codex gpt-5.4
**Rounds:** 2
**Topic:** Refactoring `generate-architecture.sh` to separate curated content from live snapshot

## Outcome

**Original proposal rejected. Simpler alternative adopted.**

The `docs/sections/` directory approach was withdrawn in favor of using the existing `docs/architecture.md` as the single curated source, with the generator slimmed to produce only `docs/snapshot.md` (live data), assembled into `docs/full-architecture.md` via dumb concatenation.

## Concessions accepted by both sides

1. **`docs/sections/` is over-engineered** — adds ordering protocol, file-existence checks, and pseudo-templating for a single-maintainer repo (Claude conceded R1, Codex accepted R2)
2. **`{{PLACEHOLDER}}` substitution is templating** — rejected templating engines but re-invented one; withdrawn (Claude conceded R1)
3. **Full CLAUDE.md inlining is bloat** — operational agent instructions, not architecture content (Claude conceded R1, Codex accepted R2)
4. **`docs/architecture.md` should be the single curated source** — self-review identified this, Codex escalated, Claude adopted (both sides agreed)

## Defenses accepted by Codex

1. **Separate snapshot file** — generator should write to `snapshot.md`, not append to `architecture.md` directly. `architecture.md` stays read-only from the generator's perspective. (Codex accepted R2)
2. **Refactor is warranted** — concrete drift between script and curated doc validates the motivation (Codex confirmed R2)

## Unresolved / Deferred

1. **Authority boundary not yet written** — Codex's key R2 point: define which facts belong to `architecture.md` vs `snapshot.md` BEFORE implementing. This is the critical next step.
2. **Dependency appendix** — drop or keep as optional appendix; not resolved.
3. **Curated roadmap vs generated roadmap** — `architecture.md` has "What's Next" sections; `snapshot.md` would have Munin project statuses. These overlap and need explicit ownership rules.

## Final plan (post-debate)

1. **Define authority boundary** — write a short rule set: `architecture.md` owns topology, roles, ports, security, deployment; `snapshot.md` owns timestamped service state, health, commits, Munin excerpts
2. **Strip curated heredocs** from `generate-architecture.sh`
3. **Generator produces `docs/snapshot.md`** — service status, health checks, git versions, Munin project statuses
4. **Assembly:** `cat docs/architecture.md docs/snapshot.md > docs/full-architecture.md`
5. **Drop from generator:** full CLAUDE.md inlining, full deps per component, full systemd units, source file listings, role/port tables (those belong in curated doc)
6. **Keep in generator:** service status table, health checks, git commit/dirty status, Munin project status excerpts
7. **Reconcile existing drift** in `architecture.md` (noxctl naming, GitHub ownership, MacBook node)

## Action items

- [ ] Write authority boundary rules (add to `docs/authority.md` or inline in generator header)
- [ ] Reconcile drift in `docs/architecture.md`
- [ ] Refactor generator
- [ ] Verify `make docs` still works

## Debate files

- `debate/generator-refactor-claude-draft.md`
- `debate/generator-refactor-claude-self-review.md`
- `debate/generator-refactor-codex-critique.md`
- `debate/generator-refactor-claude-response-1.md`
- `debate/generator-refactor-codex-rebuttal-1.md`
- `debate/generator-refactor-critique-log.json`
- `debate/generator-refactor-summary.md`

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1   | ~2m             | gpt-5.4       |
| Codex R2   | ~3m             | gpt-5.4       |
