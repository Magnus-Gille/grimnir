# Grimnir — Failure Recovery & Undo Convention

> Answers the "Failure recovery" open question in [`vision.md`](vision.md):
> *"When Grimnir acts autonomously and gets it wrong, what happens? It must
> undo its own mistakes, or at least make them visible before they propagate
> — prerequisite for phases 3-4."*
>
> This is a **convention**, not a service. No new component is required to
> adopt it — each repo wires it into its own mutation paths. Companion to
> [`observability-and-improvement.md`](observability-and-improvement.md)
> (traces/scores) and the Verdandi section of
> [`architecture.md`](architecture.md) (the audit log this convention writes
> to).

---

## Scope

This convention applies to **autonomous mutations** — any write, made
without a human approving that specific action in the moment, to:

- git repositories (commits, PRs, merges)
- production config or database state
- external systems (calendars, tickets, messages, financial records)

It does **not** apply to read-only operations (health checks, traces,
briefings, searches) — those have nothing to undo. It also does not apply to
mutations a human directly approves synchronously (e.g. Magnus reviewing and
merging a PR himself) — the human *is* the reversal control in that path.
The gap this convention closes is specifically **Phase 2 self-maintaining**
actions Grimnir takes without a human in the loop at the moment of action.

---

## The convention

**Every autonomous mutation must leave two things behind:**

1. A **reversal recipe** — machine-followable instructions for undoing the
   mutation, chosen from exactly three kinds (see below). Exactly one kind
   applies to any given mutation; there is no partial or "best effort" state.
2. A **Verdandi audit event** recording what happened and which reversal
   recipe covers it.

If a mutation happens without both, it is a bug in the actor that made it,
not an acceptable gap. Neither piece is optional — a mutation with an audit
event but no reversal recipe is exactly the gap this convention exists to
close.

### The three reversal recipe kinds

| Kind | When to use | What it records |
|------|-------------|------------------|
| `git_revert` | The mutation landed as one or more git commits (a PR, a direct commit, a merge). | The ref to revert — commit SHA, PR merge-commit SHA, or PR URL. A plain `git revert <ref>` (or closing/reverting the PR) must cleanly undo it. |
| `snapshot` | The mutation changed state that doesn't live in git (a database row, a config file on a live host, a Munin entry). | An addressable pointer to the **pre-mutation** state: a Mimir path, a Munin key + prior value, or a DB backup reference — sufficient to restore what was there before. |
| `irreversible` | Neither applies — the action had an external, non-undoable side effect (an email sent, a Telegram message posted, a paid API call, a financial transaction). | An explicit `irreversible: true` flag plus a short **mitigation** note: how the action is made *visible before it propagates further* (e.g. "posted to #alerts", "flagged in next Skuld briefing") since it cannot be undone outright. |

Picking `irreversible` is not a failure of the convention — it is the
convention working as designed: the vision's fallback ("undo, or at least
make visible before it propagates") is satisfied by the mitigation note, not
by pretending an unreversible action is reversible.

### The Verdandi audit event

Every autonomous mutation emits one event to Verdandi (`POST /api/events`,
per [`architecture.md`](architecture.md#verdandi--audit-log)) carrying the
reversal recipe as structured data:

```jsonc
{
  "type": "mutation",
  "component": "brokkr",          // matches services.json component name
  "severity": "significant",      // per Verdandi's existing taxonomy
  "trace_id": "…",                // ties back to the trace (see below)
  "data": {
    "action": "dependency-bump",
    "target": "hugin:package.json#express",
    "reversal": {
      "kind": "git_revert",
      "ref": "https://github.com/Magnus-Gille/hugin/pull/123"
    }
  }
}
```

For a `snapshot` mutation, `reversal` instead carries `{ "kind": "snapshot",
"snapshot_ref": "munin:meta/routing-table@2026-07-02" }`. For an
`irreversible` one, `{ "kind": "irreversible", "mitigation": "…" }`.

`trace_id` links the audit event to the execution trace defined in
[`observability-and-improvement.md`](observability-and-improvement.md) —
the trace says *what ran*, the Verdandi event says *what it changed and how
to undo it*. They are two views of the same action, not competing records.

### Grading

Per Verdandi's existing evidence grading (`mechanism` vs `convention`): a
reversal recipe that was mechanically captured (e.g. the actor read back the
commit SHA it just pushed) is `mechanism`-grade. One that's self-reported by
the actor without verification (e.g. an agent claims "this is
irreversible") is `convention`-grade until spot-checked. Both are better
than nothing; the grade just says how much to trust it unaudited.

---

## Applying it to the existing Phase-2 actors

Three actor classes were named in the gap analysis that opened this issue.
None of them currently emit a reversal recipe — this section is the adoption
target for each, to be picked up as separate tickets in their owning repos.

### Service deployment pre-state

Separate from the three autonomous actor classes below, `scripts/deploy.sh` mechanically captures a
valid prior `.deployed-commit` SHA in the operator log,
then invalidates that acceptance marker before the first rsync or git-pull tree mutation. It writes
the new SHA only after dependency, unit, restart, and health gates succeed. A failed deployment is
therefore deliberately markerless/unknown, never certified by the old SHA.

- **Reversal recipe:** perform a clean selective redeploy of the captured prior SHA. Rsync is not
  transactional, so marker absence is the signal to rollback or finish a verified redeploy—not a
  claim that the old files are still intact.
- **Transport uncertainty:** if marker invalidation cannot be confirmed, code mutation does not
  begin. If transport fails after later mutation starts, treat live state as unknown and inspect it
  before choosing the captured rollback commit.
- **Rendered systemd units:** opted-in components preserve the prior installed unit as
  `<unit>.grimnir-previous`. Render/path preflight and scope-correct `systemd-analyze verify`
  failures occur before any unit snapshot or install, before restart, and stay markerless.
  A partial multi-unit copy failure restores every destination already replaced and returns before
  daemon reload; an incomplete restore is reported explicitly and requires inspection. If restart
  or boundary health later fails, restore the host-local snapshots and verify the same controller
  and health gates before restoring the captured prior marker. See
  [`systemd-runtime-rendering.md`](systemd-runtime-rendering.md#rollback).

### Auto dependency bumps

Currently: `scripts/security-scan.sh` (this repo) only *detects*
vulnerabilities — it does not open fix PRs yet. `architecture.md` lists
"Autonomous low-risk fix PRs via Hugin (dependency bumps only, never
auto-merged)" as a **future, not-yet-committed** expansion. When that lands:

- **Reversal recipe:** `git_revert` — the PR is never auto-merged (a human
  merges), so the reversal is trivially "close the PR" pre-merge, or a plain
  revert of the merge commit post-merge. This is the easy case.
- **Audit event:** emitted by whichever actor opens the PR (Hugin), with
  `action: "dependency-bump"` and `target` naming the repo + package.

### Hugin task-dispatched code changes

Hugin (separate repo) dispatches agent tasks that produce commits/PRs across
service repos. Today Hugin writes task status/result records to Munin, but
task-level trace instrumentation (the `trace_id`-bearing schema in
[`observability-and-improvement.md`](observability-and-improvement.md)) is
still an open implementation-sequence item there, not shipped — so no
reversal pointer exists on task output today, on either record type.

- **Reversal recipe:** `git_revert` for the overwhelming majority — task
  output is a commit or PR. Until Hugin trace instrumentation lands, the
  Verdandi event should reference the Hugin task id/result ref directly;
  once `trace_id` is implemented, link the event via `trace_id` instead and
  add the commit/PR ref to that same trace record. Either way, adding the
  reversal pointer is the adoption path here, not a new mechanism.
- **Edge case:** a task that calls out to an external system (e.g. sends a
  message, calls a third-party API) as a side effect of an otherwise
  code-only task is `irreversible` for that side effect specifically, even
  though the code portion is `git_revert`-able. Recipes are per-mutation,
  not per-task — one task can emit more than one audit event.

### Doc fixes (documentation-drift repair)

Automated doc-drift fixes (e.g. a future extension of
`grimnir-validate.timer`, which today only detects registry-vs-live drift
and does not yet write fixes) land as commits to a docs-only repo.

- **Reversal recipe:** `git_revert` — same as any other commit. No special
  case needed; documentation mutations are not exempt from the convention
  just because the blast radius is usually lower.

---

## What this convention explicitly does not cover

- **No new service.** This is not a "Syn"-style rollback engine. It is a
  data shape (the reversal recipe) and a rule (emit it to Verdandi). Each
  owning repo implements it in its own mutation path.
- **No automatic rollback execution.** The convention makes undo *possible
  and visible*; it does not decide *when* to actually run a revert. That
  judgment call stays with a human (Phase 2-3) until trust accumulates
  enough to automate it (a Phase 3-4 question, not this one).
- **No retroactive backfill.** Mutations made before an actor adopts this
  convention are not audited retroactively. Adoption is forward-looking,
  tracked per-repo via tickets filed against the owning agent.
- **No cross-repo code changes from this ticket.** This doc is the
  convention; rollout into Hugin, Brokkr, and any other mutating actor is
  separate, per-repo work opened as tickets against those repos' owners.

---

*This document is a companion to [vision.md](vision.md) (the open question
it answers) and [architecture.md](architecture.md) (the Verdandi mechanism
it writes to). Filed against issue #46.*
