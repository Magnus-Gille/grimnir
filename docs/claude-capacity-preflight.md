# Claude capacity preflight

Before assigning a bounded task to Claude, the orchestrator may run:

```sh
scripts/claude-capacity-preflight.sh probe --model sonnet
```

The probe is one non-interactive `--print` request with a fixed `READY` prompt,
no tools, safe mode, no session persistence, and a `0.01 USD` maximum budget
(override only with `CLAUDE_PREFLIGHT_MAX_BUDGET_USD`). It neither creates a
worktree nor enables edits, and does not retry. Its public-safe output records
only the attempted model and a class: `none`, `capacity`, `auth`,
`model_unavailable`, `network`, or `unknown`. It never print or stores Claude
stderr, credentials, or account details.

On any non-zero preflight result, do not loop. Preserve the existing worktree
and commit, then inspect its handoff state before giving the same bounded task
to the configured next agent:

```sh
scripts/claude-capacity-preflight.sh fallback --task-ref grimnir-136
```

The fallback record reports the branch, whether it is ahead of its upstream,
and whether it is dirty, followed by `next_agent`. The orchestrator must hand
off only after recording those fields; it must not discard the worktree or
repeat a `capacity` failure.
