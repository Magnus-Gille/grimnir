# Separating the three roles of `~/repos/grimnir` on huginmunin

> Status: adopted and deployed. Grimnir now advances its canonical checkout by
> guarded `git pull --ff-only`; Hugin uses separate task workspaces. Daily
> validation checks branch/cleanliness plus exact equality with live origin and
> refuses to re-stamp an unproved checkout. The option analysis below is retained
> as the decision history for issue #47.
>
> Issue #87 extends this single-checkout guard to the full multi-agent
> worktree lifecycle (stale/dirty/orphaned worktrees across every owned repo,
> plus a deploy-target role check) — see `docs/worktree-hygiene.md` for the
> protocol and `scripts/worktree-hygiene-audit.sh` for the audit tool.

## The problem

On huginmunin, the single path `/home/magnus/repos/grimnir` is forced to play
three roles that want incompatible things from it:

| Role | Who drives it | What it wants the tree to be |
|------|---------------|------------------------------|
| **Deploy target** | `scripts/deploy.sh` (`make deploy ARGS="grimnir=/absolute/worktree@FULL_COMMIT_SHA"`) advances this checkout only after source binding | A clean `main` checkout matching the explicitly expected `origin/main` revision |
| **Canonical git checkout** | Registry consumers read `services.json` from here; the `grimnir-security-scan` and `grimnir-validate` timers run *from* here | Pristine: on the default branch (`main`), clean, matching `origin/main` |
| **Hugin task workspace** | Hugin (task dispatcher) has historically used this checkout as a working tree, checking out branches per task | A scratch tree it can check out arbitrary branches into and mutate |

These collide directly:

- The rsync deploy (`--delete`, `.git/` excluded) overwrites the tracked files
  with the laptop's copy while leaving `.git` pointing at the committed HEAD —
  so the tree reads **dirty** the moment the laptop worktree differs by even one
  uncommitted line.
- A Hugin task that checks out a feature branch **strands** the checkout off
  `main`. Every consumer that then reads `services.json` reads it from the wrong
  branch.

Either way the registry is silently poisoned: consumers keep reading, none of
them notice the tree is no longer the source of truth they assume it is.

## What actually happened

Two poisoning incidents in two weeks:

- **#33** — first occurrence of the "checkout stranded off `main`" class; the
  issue was closed without a guard, so the class recurred.
- **#44 / #43** — the ecosystem gap analysis (2026-07-03, §1.4) found the
  checkout **stranded on a June-15 hugin task branch** with the tree **one
  deploy behind** — missing exactly #42, the `services.json` stale-node fix.
  So the very file that is this repo's single source of truth was being served
  stale, off-branch, to every consumer.

The root cause is not any one of the three roles — it is that one path owns all
three at once, with nothing watching for drift.

## Options considered

### The deploy-target role

**Option A — grimnir stops being an rsync deploy target; its "deploy" becomes a
`git pull` on `main`. (Recommended.)**
Unlike every other component, grimnir has no build output and no long-running
service — only two timers and a registry file. There is nothing to rsync that
`git pull --ff-only origin main` doesn't deliver more safely. A pull keeps
`checkout == git HEAD == origin/main` *by construction*, which structurally
removes the "dirty after deploy" failure mode. The security-scan/validate timers
already run from a git checkout; they just need it kept current, not mirrored.

**Option B — keep rsync, but move the deploy target to its own path**
(e.g. `/home/magnus/deploy/grimnir`), leaving `~/repos/grimnir` as the pristine
consumer checkout. Rejected: more moving parts (two grimnir trees, timers
repointed) to preserve an rsync path that grimnir doesn't benefit from in the
first place. Worth revisiting only if grimnir ever grows a build step.

### The hugin-workspace role

**Option C — Hugin never uses the canonical checkout as a workspace; task
worktrees move to a dedicated scratch root** (e.g. `~/hugin/workspaces/<task>`),
one git worktree per task. This is the same "one task → one worktree" isolation
rule the rest of the fleet already follows, and it removes the "stranded on a
task branch" failure mode entirely. The workspace root is **hardcoded on the
hugin side**, so this is a hugin change — tracked as **hugin#139**. Not
something this repo can land.

## Recommendation

Separate all three roles; do not let one path own more than the consumer
checkout:

1. **Canonical checkout** — `~/repos/grimnir` stays the single pristine git
   checkout that consumers and timers read. Only ever advanced by
   `git pull --ff-only origin main`. Never an rsync target, never a hugin
   workspace.
2. **Deploy** — retire grimnir's rsync deploy in favour of a `git pull` on
   `main` (Option A). *Deferred — deliberately not in this PR* (see below).
3. **Hugin workspace** — move task worktrees off the canonical checkout to a
   dedicated scratch root (Option C). *Owned by hugin — hugin#139.*
4. **Detection** — regardless of which cleanup lands first, alarm on drift. This
   is what this PR adds, so the poisoned state can never again sit silent.

## What this PR ships

- `scripts/lib/registry-checkout.sh` — a read-only integrity check for the
  canonical checkout: is it on the default branch, and is the working tree
  clean? Pure `classify_registry_checkout` verdict logic + a
  `check_registry_checkout` gatherer, unit-tested in
  `scripts/tests/registry-checkout.test.sh` (`make test-registry-checkout`).
- Wiring into `scripts/generate-architecture.sh --validate` (the daily
  `grimnir-validate` run): the checkout is now a validated line item, counted as
  a failure and pushed to Telegram via `notify.sh` when it drifts off `main` or
  goes dirty. Overridable via `GRIMNIR_REGISTRY_CHECKOUT` /
  `GRIMNIR_DEFAULT_BRANCH`.

## What this PR deliberately does NOT do

- **No change to `scripts/deploy.sh` behaviour.** Retiring the rsync deploy
  (Option A) is a separate, riskier change touching live deploy flow and the
  timers that run from the checkout; it should land on its own once the alarm
  has been observed in production. This PR only makes the drift visible.
- **No hugin change.** Moving hugin task workspaces is hugin#139.
- **No delta/dedup on the alert.** The check alerts on every drifted run.
  Suppressing repeat alerts (reusing `scripts/lib/escalation.sh`) is grimnir#2;
  it is inert until the checkout is reconciled to `main`, so it sequences after,
  not before, this alarm.
