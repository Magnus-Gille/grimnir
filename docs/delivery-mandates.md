# Delivery mandates and instruction ownership

Owner decision: 2026-10-11. Implement the approved bounded mandate model across the existing
instruction structure. Reuse the harness layer and Hugin where supported; no new factory service.

## Sources and responsibilities

| Surface | Responsibility |
|---|---|
| `claude-config/AGENTS.md` | Portable authority: mandate scope/lifetime, mutation tiers, approval deltas, protected actions and trust boundaries |
| Owning repository `AGENTS.md` | Local acceptance, checks, deployment and recovery contracts; cannot weaken global floors |
| `claude-skills/ship-it` | One delivery procedure, self-review and independent-review stages, fresh evidence, repair/resume and batch coordination |
| `ticket-fleet` | Compatibility redirect preserving the old PR-only endpoint; no executable parallel delivery engine |
| Private `deploy` and `submit-task` | Thin adapters to owning deployment tools and actual Hugin contracts |
| Harness permissions, CI, deploy guards, Hugin | Enforce capabilities and execution gates; prose is not isolation |
| Handoff / Munin | Authorization provenance and execution evidence; never new authority |

A task records the requested endpoint: local, PR, merge or verified production. Selecting a skill
cannot increase it. The global policy defines what an explicit production mandate covers.
Normal diagnosis, scoped corrections, rebase, fresh checks and review continue within that mandate.
Changed effects, targets or privileges require the appropriate delta approval. A blocked branch
must not halt independent authorized work. Unknown external outcomes require reconciliation.

## Review and verification

Self-review is the implementing agent's own diff/acceptance check. Independent review uses the
current `ship-it` review defaults and an authorized constrained route after deterministic checks.
Architecture debate is a separate activity when the actual design requires it. None substitutes
for the others or for hosted checks and release identity. New behavior, instructions or changed
gates require review of that change; a new SHA alone is not a new task authorization request.

The migration's acceptance scenarios are: stale-base repair; grounded review corrections;
isolated build dependencies versus host installation; one transient retry then diagnosis;
unknown production outcome reconciliation; scope/privilege expansion; deployment-triggering
merge; and preserving a PR-only endpoint. Structural tests catch drift; isolated agent exercises
provide behavior evidence, and neither proves future model compliance or runtime enforcement.

## Activation, rollout and reversal

Source changes travel through owning-repository PRs with review and checks. Installed behavior
is a separate fact: inspect the actual host links and sync configuration before publishing a
release trigger. Existing automatic pulls of configuration or skills can make merge an installation.
Do not assume a merged PR is installed, or that a clean source tree proves every harness sees it.

Prepare one owner approval package for installation with the exact candidate/merge bindings,
named hosts and links, preserved local changes, verification commands and reversal. Read back
installed hashes/link destinations and exercise routing after activation. Preserve dirty canonical
checkouts; never stash, overwrite or discard their changes to force sync. A host with overlapping
local changes remains pending until reconciled in its owning context.

Every autonomous mutation leaves an audit event and reversal recipe. Source rollback uses a
reviewed revert PR for the specific change; installed rollback restores the recorded prior
revision/link through its authorized host path and verifies it. Never restore data destructively
as part of code rollback. Unknown or partial activation stays unresolved until readback.

The existing Hugin handoff or constrained fresh-session requirement remains in force after
untrusted input. This migration does not arm the ADR-008 autonomy controller, install signing
keys, alter protected lanes or authorize unattended maintenance. Those retain their own contracts.
