# Multi-agent worktree and deployment hygiene (issue #87)

> Status: adopted. Extends the canonical-checkout guard from issue #47
> (`docs/role-separation.md`, `scripts/lib/registry-checkout.sh`) to the full
> worktree lifecycle, and adds a narrow deploy-target role check. Read-only
> audit; see `scripts/worktree-hygiene-audit.sh` and
> `scripts/lib/worktree-hygiene.sh`.

## The problem

Many agents/sessions operate concurrently across the same repos and
checkouts. Grimnir's own house rule is **one task = one subagent = one
dedicated worktree** (see `AGENTS.md` § House rules — cross-repo delegation),
but that discipline is only as good as its follow-through. Left unaudited,
this class of activity accumulates residue:

- **Stale worktrees** — a task's branch gets merged (or its remote branch is
  deleted after merge/rebase), but the linked worktree that checked it out is
  never removed.
- **Dirty worktrees** — a worktree still holds uncommitted or untracked work,
  sometimes from a session that ended abruptly.
- **Orphaned/prunable worktree registrations** — a worktree's directory was
  removed directly (`rm -rf`) instead of via `git worktree remove`, leaving
  git's own bookkeeping (`.git/worktrees/<name>`) stranded and pointing at
  nothing.
- **A canonical checkout doubling as a deploy target or task workspace** —
  the exact #47 poisoning class: the single path every registry consumer
  reads from goes dirty or gets stranded off the default branch.
- **Deploy drift** — a deployed commit that no longer matches `origin/main`
  (already guarded for `deploy_mode: git-pull` components by
  `scripts/lib/registry-checkout.sh`'s freshness check and for rsync
  components by the `.deployed-commit` marker check), or — the narrower gap
  this issue closes — an **rsync deploy target that has unexpectedly grown a
  `.git` directory**, meaning it is quietly doubling as an ad hoc checkout.

An audit (2026-07, grimnir#87) found exactly this kind of residue: dozens of
worktrees on the Hugin dispatcher host including prunable and dirty stale
trees, a primary checkout behind `origin/main`, extra worktrees on another
host including a stale deployment tree, and at least one completed commit
stranded off `main` on a branch nobody had cleaned up. Current tests were
green throughout — this is an **operational integrity problem**, not evidence
of source corruption. The risk is inspecting, editing, or deploying the wrong
tree and believing cross-repo work landed when only half of it did.

## The protocol

1. **One task = one subagent = one dedicated worktree.** Already the house
   rule (`AGENTS.md`). A worktree exists for exactly one ticket/task; it is
   not reused across unrelated work.
2. **Clean up after merge.** Once a task's PR merges, its worktree is
   removed (`git worktree remove <path>`) and its branch deleted
   (`git branch -d <branch>`, or `-D` only after confirming the merge landed
   under a different SHA, e.g. squash-merge) — by the agent or operator who
   finished the task, not left for someone else to notice later.
3. **The canonical checkout stays clean, on the default branch, always.**
   Per `docs/role-separation.md`: the canonical checkout that registry
   consumers and validation timers read from is never a scratch workspace and
   never an rsync deploy target. It only ever advances by
   `git pull --ff-only origin main`.
4. **Deploy targets stay in their declared lane.** A `deploy_mode: git-pull`
   target is *supposed* to be a git checkout. Every other (rsync) target is
   *not* — if one grows a `.git` directory, that is a role violation worth
   investigating, not a co-incidence to ignore.
5. **Run the audit, don't just hope.** `scripts/worktree-hygiene-audit.sh`
   (standalone) and the `--validate` wiring in
   `scripts/generate-architecture.sh` (the existing `grimnir-validate` timer,
   issue #47's harness) both report hygiene state read-only. Findings are
   evidence for a human/agent to act on, not something the tooling fixes
   itself.

## Running the audit

Standalone, against the real repo tree on a host:

```bash
scripts/worktree-hygiene-audit.sh
# or with overrides:
GRIMNIR_WORKTREE_AUDIT_ROOT=/path/to/repos \
GRIMNIR_DEFAULT_BRANCH=main \
GRIMNIR_SERVICES_JSON=/path/to/services.json \
  scripts/worktree-hygiene-audit.sh
```

It scans every git repo directly under the repos root, and for each one
prints one line per worktree that has a finding, followed by a summary line
(`Summary: N ok, M issues`) and a non-destructive remediation recipe per
finding. Exit code is `0` when nothing is flagged, `1` otherwise.

It is also wired into `scripts/generate-architecture.sh --validate` (the
`grimnir-validate` timer), where its findings fold into the existing
`PASS`/`FAIL` tally and Munin-persisted validation report alongside the #47
registry-checkout check and the per-component deployment-freshness checks.

Unit and fixture tests: `make test-worktree-hygiene` (also part of
`make test`), exercised against constructed fixture git repos — never against
the real, live repos. See `scripts/tests/worktree-hygiene.test.sh`.

## What the audit reports (and never does)

| Verdict | Meaning | Suggested manual remediation |
|---|---|---|
| `ok` | Active/clean; no finding | — |
| `dirty` | Uncommitted changes present | Inspect (`git status`); commit or `git stash -u`. |
| `stale` | Branch merged into the default branch, or its upstream is gone, but the worktree remains | After confirming no unique unpushed work: `git worktree remove <path>` then `git branch -d <branch>` — operator-confirmed only. |
| `dirty,stale` | Both at once — a merged/gone branch with unsaved work sitting in it | Preserve the work first (commit, stash, or cherry-pick it) **before** any removal. |
| `prunable` | Administrative worktree entry present, but its working directory is gone | Reconcile the registration only: `git worktree prune` (does not touch any other worktree's files). |
| `alert-branch` / `alert-dirty` / `alert-branch-dirty` (canonical only) | The canonical checkout itself has drifted off the default branch and/or gone dirty — the #47 poisoning class | Reconcile manually to the default branch; see `docs/role-separation.md`. |
| `violation-unexpected-git` (deploy target) | A non-`git-pull` deploy target unexpectedly contains a `.git` directory | Investigate manually; do not delete `.git` automatically. |

`classify_deploy_target` trusts `services.json`'s declared `deploy_mode` as the
intended contract, not something it infers from the filesystem. If a
component is genuinely meant to be a git-pull consumer, its registry entry
must say `deploy_mode: "git-pull"` — flagging a `.git` directory under a
component still declared `rsync` is the correct, intended alarm (it surfaces
a registry/reality mismatch, whichever side is wrong), not a false positive.

The audit is **read-only by construction**: nothing in
`scripts/lib/worktree-hygiene.sh` or `scripts/worktree-hygiene-audit.sh`
deletes a worktree, prunes, resets, or checks anything out. Every finding
maps to a remediation *string* for a human or agent to run — consistent with
the repo-wide git-safety rule that destroying uncommitted or untracked work
is never automatic. If a destructive action is ever warranted (e.g. removing
a confirmed-stale worktree), it is an explicit, opt-in, operator-run command
— never something this tooling executes on your behalf.

## Known heuristic limit

`stale` is derived from `git merge-base --is-ancestor <branch> <base>`, which
is also true when a branch's tip is *identical* to the base (a freshly cut
branch with zero commits yet, or a fast-forward-merged branch that was never
advanced further). A worktree created moments ago for a task that hasn't
started committing yet can therefore show up as `stale` on its very first
audit run. This is treated as an acceptable false-positive class rather than
a bug: remediation is always manual and requires the operator to confirm
"no unique unpushed work" before touching anything, so the cost of a
premature `stale` flag is a no-op glance, never a lost commit. If this proves
noisy in practice, a future refinement could suppress the flag for worktrees
younger than some threshold (e.g. via the branch ref's reflog date) — not
implemented here to keep the classifier pure and deterministic for tests.

## What this does not cover

- **Cross-host worktree state.** The audit inspects the local filesystem of
  whatever host it runs on. A full cross-host inventory (e.g. auditing Hugin
  dispatcher worktrees from the laptop) needs either running the audit on
  each host or extending it with the same SSH pattern
  `scripts/generate-architecture.sh` already uses for remote git-checkout
  freshness (`remote_git_checkout_freshness`) — not implemented here to keep
  this change read-only-and-local, matching how issue #47's checkout guard
  itself runs from `huginmunin`.
- **Stranded-but-complete branches with no local worktree at all** (a branch
  that was pushed, has a completed PR, but was never checked out as a
  worktree on this host) are outside worktree scope; that class is closer to
  the "superseded with evidence" cleanup issue #87 also names, and is a
  candidate for a separate branch-inventory check layered on top of this one.
- **Force-deleting anything.** Explicitly out of scope per issue #87's
  non-goals; this audit only ever reports.
