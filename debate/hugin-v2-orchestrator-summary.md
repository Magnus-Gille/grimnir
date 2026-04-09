# Debate Summary: Hugin v2 Pipeline Orchestrator

**Date:** 2026-04-02
**Participants:** Claude Opus 4.6, Codex GPT-5.4
**Rounds:** 2
**Debate type:** Architecture + Priority/Product

## Concessions accepted by both sides

1. **Three sequential bets, not one roadmap.** The workflow engine, routing policy, and methodology templates are separate investment decisions. Validate each before starting the next.

2. **Markdown compiles to typed IR.** Markdown is the authoring surface; a validated JSON IR is the execution contract. Hugin never executes raw markdown.

3. **Templates start in git, not Munin.** Versioned, immutable files. No sub-pipeline nesting, no self-modification in v1. Template value exists even without runtime integration.

4. **Router is opt-in.** Explicit runtimes remain the default. `Runtime: auto` enables routing. Existing tasks are unaffected.

5. **Success criteria defined.** One fixed 4-phase pipeline runs unattended, uses validated IR, supports cancellation/resume, gates side effects, produces a review-ready artifact, and records operational metrics.

## Defenses accepted by Codex

- The core orchestration idea (parent/child joins + pipeline DAG) is not overengineered.
- Fan-out as serial queueing is acceptable if documented honestly — becomes real parallelism when a second worker arrives.
- Templates as versioned methodology have standalone value even without runtime expansion.

## Key amendments to the original plan

### Revised roadmap (agreed)

1. **Parent/child joins** (already specced)
2. **Pipeline IR + decomposer** — compile markdown to validated JSON, explicit runtimes only, no conditions yet
3. **Structured results + pipeline timeout + cancellation + resume** — conditions become possible only after this ships
4. **Human gates** for side-effecting phases (git push, PR, deploy)
5. **Sensitivity classification** — monotonic propagation (phase sensitivity >= max sensitivity of all inputs), covers prompt + data source + tool egress
6. **Router** (opt-in only via `Runtime: auto`)

**Deferred:**
- OpenRouter runtime
- Eval-driven routing table
- Mac Studio integration (hardware, not software)
- Mutable templates and sub-pipeline expansion

### New hard rules (from Round 2)

- **Monotonic sensitivity:** A phase may only run on a runtime allowed by the maximum sensitivity of everything it can read. No phase-level downgrade below inherited/input sensitivity.
- **No conditions before structured results:** Step 2 must explicitly forbid conditional execution until Step 3's result schemas exist.
- **No autonomous side effects without gate semantics:** Authority requires typed side-effect contracts, not just metadata tags.

## Unresolved disagreements

- **Authority enforcement model:** Both sides agree authority matters, but the enforcement mechanism (what counts as a side effect, how gates work, how resume after approval works, idempotency rules) is not yet designed. Codex flags this as the path to policy sprawl if done loosely.

- **Information-flow completeness:** Codex's final verdict is that the biggest remaining risk is an unsound information-flow model — sensitivity must propagate from context refs, tool outputs, and upstream artifacts, not just prompt text. Claude conceded the direction but hasn't defined the propagation rules.

## Final verdict (Codex)

> The single most important remaining risk is an unsound information-flow model. As long as sensitivity can be overridden per phase without strict propagation from inputs, context, tool outputs, and upstream artifacts, the system's privacy guarantee is aspirational rather than real.

## Action items

1. **Update the architecture plan** to reflect the revised roadmap, pipeline IR requirement, monotonic sensitivity, and success criteria.
2. **Design the pipeline IR schema** (JSON, with Zod validation) as the first concrete deliverable after Step 1.
3. **Define structured result contract** — what a phase must write for downstream conditions to work.
4. **Design human gate semantics** — representation, resume protocol, notification flow (Telegram via Ratatoskr).
5. **Define sensitivity propagation rules** — how context refs, tool outputs, and upstream artifacts contribute to effective phase sensitivity.

## All debate files

- `debate/hugin-v2-orchestrator-snapshot.md` — frozen artifact
- `debate/hugin-v2-orchestrator-claude-draft.md` — Claude's position
- `debate/hugin-v2-orchestrator-claude-self-review.md` — Claude's self-review
- `debate/hugin-v2-orchestrator-codex-critique.md` — Codex Round 1 critique
- `debate/hugin-v2-orchestrator-claude-response-1.md` — Claude Round 1 response
- `debate/hugin-v2-orchestrator-codex-rebuttal-1.md` — Codex Round 2 rebuttal
- `debate/hugin-v2-orchestrator-critique-log.json` — structured critique log
- `debate/hugin-v2-orchestrator-summary.md` — this file

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1 (attempt 1) | ~3m (failed — couldn't find Hugin source) | gpt-5.4 |
| Codex R1 (attempt 2) | ~4m | gpt-5.4 |
| Codex R2 | ~3m | gpt-5.4 |
