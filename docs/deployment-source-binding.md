# Deployment source binding

Every deployment invocation must name the source selected by the orchestrator
and its immutable full commit SHA. A clean checkout is necessary but not
sufficient: it can still be the wrong worktree or a stale commit.

The expected SHA must come from the accepted release decision (for example the
merged PR result), not from `git rev-parse HEAD` in whichever checkout happens
to be current at deploy time.

## Authorization and revision evidence

Global `claude-config/AGENTS.md` owns authorization. Either exact-revision confirmation or an
explicit bounded release mandate may cover the action. In both cases the execution still needs
the exact accepted revision and all checks below. Ordinary repair changes the evidence that must
be regenerated; it does not automatically cancel an otherwise valid task mandate. A changed
release effect or target requires the authorization delta specified by that policy.

A merge, push or tag that automatically deploys or installs is the release trigger. Prepare and
bind the candidate before that action; when a future merge SHA is not yet available, use an
accepted candidate binding and verify the resulting integration receipt before manual rollout.
An executor unable to enforce that binding must leave its trigger pending. This document does
not change executor behavior, grant automatic deployment, or arm ADR-008 coverage.

## Centrally deployable components

`scripts/deploy.sh` requires one bound request for every selected component:

```text
component[=/absolute/worktree]@FULL_COMMIT_SHA
```

Use the registered checkout with `component@FULL_COMMIT_SHA`, or bind an
isolated worktree explicitly:

```sh
make deploy ARGS="heimdall=/private/tmp/heimdall-release@<accepted-full-sha>"
```

Multiple components may be selected, but each gets its own source and SHA:

```sh
make deploy ARGS="heimdall=/private/tmp/heimdall-release@<heimdall-full-sha> mimir=/private/tmp/mimir-release@<mimir-full-sha>"
```

Bare component names and no-argument deploys fail closed. Before any selected
component builds, invalidates a marker, syncs, pulls, or restarts, Grimnir
validates the complete request set. It prints:

```text
Expected source: /absolute/worktree @ <expected-sha>
Actual source: /absolute/worktree @ <actual-sha>
```

The selected directory must itself be the resolved Git worktree root; a
subdirectory is rejected. Detached worktrees are supported. Existing
component cleanliness, unit-source, rendering, marker, restart, and health
checks remain additional gates.

For `deploy_mode: git-pull`, Grimnir also resolves `origin/main` read-only with
`git ls-remote` and requires it to equal the expected SHA before remote marker
invalidation. The remote checkout repeats the equality check after fetch and
requires its final `HEAD` to equal the same expected SHA.

## Owning-repository deploy commands

Some repositories use their own deploy entry point and are intentionally not
in the centrally deployable component set. Run those commands through
Grimnir's generic guard:

```sh
cd /private/tmp/owning-repo-release
/absolute/path/to/grimnir/scripts/guarded-deploy.sh \
  /private/tmp/owning-repo-release \
  <accepted-full-sha> \
  -- ./scripts/deploy.sh
```

The guard compares the explicit expected path and SHA with the caller's
physical current directory, resolved Git worktree root, and actual `HEAD`.
The command after `--` is executed only when all identities match. This keeps
the owning repository's own deploy checks intact; the Grimnir guard is an
outer source-identity boundary, not a replacement for them.

Use this wrapper for any component-local deployment, including repositories
listed only under `repository_authority.additional_repositories` and peers
with `deploy: false`.
