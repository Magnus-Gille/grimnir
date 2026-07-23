# Multi-agent worktree and deployment hygiene (issue #87)

> Status: adopted. Extends the canonical-checkout guard from issue #47
> (`docs/role-separation.md`, `scripts/lib/registry-checkout.sh`) to the full
> worktree lifecycle, adds a narrow deploy-target role check, and verifies
> canonical local origins against repository authority. Read-only
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
- **Repository-authority drift** — a canonical local checkout's `origin`
  still points at an archived predecessor, fork, or unrelated repository. A
  plain fetch can then look successful while returning stale or
  non-canonical history.

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
6. **Treat remote reconciliation as an operator action.** The audit compares
   normalized GitHub `owner/repo` identities from
   `services.json.repository_authority`; it never changes fetch/push URLs.
   Before reconciling a finding, inspect local branches and worktrees and
   preserve a useful predecessor under an explicit archival remote name.

### Canonical-origin reconciliation runbook

An audit finding is only a **candidate for investigation**, not permission to
change `origin`. Use this procedure only when the declared repository, its
history, and its active GitHub workflow all agree. It changes remote
configuration only: it does not check out, merge, reset, delete, or push
anything.

1. Inspect before changing state. In particular, capture the working-tree
   state, every linked worktree, and both fetch and push configuration:

   ```bash
   git -C /path/to/checkout status --short --branch
   git -C /path/to/checkout worktree list --porcelain
   git -C /path/to/checkout remote -v
   git -C /path/to/checkout config --get-regexp '^remote\.' || true
   ```

   Stop when a conflicting archival remote name already exists, the declared
   authority is ambiguous, or active work makes a remote-name change unsafe.
   Do not use this runbook for an excluded active repository.

2. Verify the declared repository's ownership before trusting its name. Check
   its GitHub archive state and current pull-request/issue workflow, then do
   the same for the checkout's current `origin` when the two differ:

   ```bash
   git ls-remote --heads https://github.com/OWNER/REPOSITORY.git main
   gh repo view OWNER/REPOSITORY --json nameWithOwner,isArchived,defaultBranchRef,url
   gh pr list --repo OWNER/REPOSITORY --state all --limit 10
   gh issue list --repo OWNER/REPOSITORY --state all --limit 10
   ```

   Stop if the declared target is archived, has a different active workflow
   from the predecessor, or otherwise does not own the work being reconciled.
   A matching `owner/repo` string alone does not establish operational
   authority.

3. Fetch the candidate tip without changing branch configuration, then prove
   the ancestry relation. A candidate is safe only when it is identical to
   `main` or already contains `main`; a candidate behind `main` would accept
   an ordinary fast-forward push, and an unrelated history makes migration a
   separate, explicit project.

   ```bash
   git -C /path/to/checkout fetch --no-tags https://github.com/OWNER/REPOSITORY.git main
   candidate="$(git -C /path/to/checkout rev-parse FETCH_HEAD)"

   if test "$(git -C /path/to/checkout rev-parse main)" = "$candidate"; then
     echo 'safe: identical histories'
   elif git -C /path/to/checkout merge-base --is-ancestor main "$candidate"; then
     echo 'safe: candidate contains local main; local checkout is stale'
   elif git -C /path/to/checkout merge-base --is-ancestor "$candidate" main; then
     echo 'STOP: candidate is behind local main; an ordinary push would advance it'
     exit 1
   else
     echo 'STOP: histories are unrelated; plan a migration instead'
     exit 1
   fi
   ```

   Do not replace either stop condition with a rebase, force-push, or an
   improvised history transplant. Preserve both remotes and escalate the
   registry/ownership decision instead.

4. Only after those preconditions pass, preserve the old `origin` under an
   explicit name before adding the canonical one. Replace the URL and branch
   with the registry's declared values:

   ```bash
   git -C /path/to/checkout remote rename origin archive-predecessor
   git -C /path/to/checkout remote add origin https://github.com/OWNER/REPOSITORY.git
   git -C /path/to/checkout fetch origin
   git -C /path/to/checkout branch --set-upstream-to=origin/main main
   ```

   `git remote rename` retains the predecessor URL and its tracking refs under
   `archive-predecessor`; it does not discard the old history. Use a more
   specific archival name if that name is already legitimately occupied.

5. If the checkout already has the declared canonical remote under another
   name, swap names rather than creating a duplicate. This also preserves the
   old `origin` and rewrites branches that tracked the existing canonical
   remote to track the new `origin`:

   ```bash
   git -C /path/to/checkout remote rename origin archive-predecessor
   git -C /path/to/checkout remote rename canonical origin
   git -C /path/to/checkout fetch origin
   git -C /path/to/checkout branch --set-upstream-to=origin/main main
   ```

6. Verify both directions and rerun the read-only authority audit:

   ```bash
   git -C /path/to/checkout remote get-url origin
   git -C /path/to/checkout remote get-url --push origin
   git -C /path/to/checkout remote get-url archive-predecessor
   git -C /path/to/checkout rev-parse --abbrev-ref main@{upstream}
   scripts/worktree-hygiene-audit.sh
   ```

   The full hygiene audit can still report unrelated dirty, stale, or prunable
   worktrees. A clear `canonical checkout origin:` section proves only that
   the configured name matches the registry. It is not a substitute for the
   ownership and ancestry preconditions above.

#### Resolved authority discrepancy: Skuld

On 2026-07-23, GitHub evidence showed that `Magnus-Gille/skuld` is the private
active repository: it contains `grimnir-bot/skuld`'s `main` history and has the
current pull-request workflow. `grimnir-bot/skuld` is also private and
unarchived, but its `main` and GitHub activity stopped in March. The registry
therefore names the active `Magnus-Gille/skuld` repository. Preserve the older
remote as an explicitly named predecessor where it exists; do not retarget an
active checkout toward the stale repository merely to satisfy an old registry.

Never replace this procedure with `git remote remove`, an unrecorded
`set-url`, a reset, or a checkout in a dirty canonical tree. Those operations
either destroy the predecessor reference or expand a configuration repair into
an unreviewed source-state change.

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

For canonical-origin checks, component checkout names come directly from
`services.json.components[].repo`; the default GitHub owner, owner exceptions,
and non-component repositories come from `services.json.repository_authority`.
A checkout absent on the current host is skipped because hosts intentionally
carry only part of the ecosystem. When a checkout exists, a missing,
non-GitHub, archived, or wrong `origin` is a finding. Output includes only
normalized public GitHub identities (or `<missing>`/`<non-github>`), never raw
remote URLs.

When retaining an unrelated archive checkout is intentional, keep it in a
separately named directory and preserve its remotes and history there. The
declared canonical directory keeps its repository name; the audit never
rewrites that global contract to suit one host.

The worktree-lifecycle portion is also wired into
`scripts/generate-architecture.sh --validate` (the `grimnir-validate` timer),
where its findings fold into the existing `PASS`/`FAIL` tally alongside the
#47 registry-checkout check and per-component deployment-freshness checks.
Origin-authority findings currently belong to the standalone local audit.

Unit and fixture tests: `make test-worktree-hygiene` (also part of
`make test`), exercised against constructed fixture git repos — never against
the real, live repos. See `scripts/tests/worktree-hygiene.test.sh`.

### Default-branch resolution

The audit resolves each repository's default branch independently. It reads
the local `refs/remotes/origin/HEAD` first and, when that is absent, performs
only the read-only `git ls-remote --symref origin HEAD` query. It never fetches,
switches branches, or updates refs while auditing. If neither source can prove
the branch, it reports an unresolved default branch rather than assuming
`main`. Operators that need a deterministic compatibility fallback may supply
`--default-branch <safe-branch>` (or `GRIMNIR_DEFAULT_BRANCH`); the output marks
that choice as a fallback. Remote resolution is bounded to eight seconds by
default (`GRIMNIR_WORKTREE_REMOTE_TIMEOUT_SECONDS`, valid range 1–60): timeout
is reported as unresolved and never allows the validation timer to hang.

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
| `missing-origin` / `non-github-origin` / `archived-origin` / `wrong-origin` | The canonical checkout's `origin` does not match repository authority | Inspect branches, worktrees, and fetch/push URLs; reconcile manually while preserving useful predecessor history under an explicit archival remote. |

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

The same boundary applies to remotes: the audit reads
`remote.origin.url`, normalizes supported GitHub transports for comparison,
and reports a verdict. It never executes `git remote set-url`, adds/removes
a remote, fetches, or pushes.

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
