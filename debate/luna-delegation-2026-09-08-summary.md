# Luna delegation default — Opus review

On 2026-09-08, Magnus requested aggressive delegation of implementation and other bounded
tasks to Luna High, using Extra High for harder leaves, while retaining conductor accountability.
The portable instructions use native Codex subagents and a gated Codex headless route for
Claude Code and Pi. M5 remains available for explicitly requested local inference or evaluation.

Magnus replaced the requested Fable review with Opus after Fable's account limit prevented a
review. Two read-only review rounds completed using **`claude-opus-5`**, confirmed by structured
`modelUsage`. Extra High was requested; effective effort was not exposed. Reviews used frozen,
scoped source with no tools, MCP, browser, or session persistence.

## Decision

Apply the reviewed instructions locally. Opus's second-round verdict was **no remaining
source-level blockers**. The conductor remains responsible for scope, integration, deterministic
verification, correcting inadequate output, and final quality. This is an instruction-level
default; it does not prove adoption or performance across all hosts.

The first review led to these corrections:

- Put the scope of already-authorized OpenAI task delegation in canonical `AGENTS.md`, including
  exclusions and preservation of provider-specific limits. Keep independent-review authorization
  separate.
- Require explicit verification of child tools, MCP, filesystem, network, environment, and approval
  restrictions. A worktree and a prompt do not establish an access boundary. Fail closed when
  the required restrictions cannot be established.
- Gate headless use on per-host runtime checks. Label the CLI example as routing arguments,
  distinguish requested from observed model/effort, and mark unavailable observations unknown.
- Add regression guards for adapter routing, child boundaries, the Luna High worker source,
  and equality of the installed worker override.

The conductor declined automatic substitution with native Claude workers because the owner
specified Luna. Safe inline execution is the fallback. Broader legacy-wrapper cleanup and host
rollout remain outside this change. Opus accepted these scope decisions in the second round.

## Verification and limits

- Luna High completed the bounded test/audit work; usefulness: **pass**. The complete corrected
  claude-config suite passed **49/49** in an isolated scratch snapshot and again after installation.
- The conductor independently ran the focused suite (**11/11**), scoped instruction audit
  (**0 errors, 0 warnings**), syntax checks, and ShellCheck comparison (**no new diagnostics**).
- Grimnir `make test` passed. Its optional live Claude routing probe was skipped.
- The final full instruction audit reports **61 missing-wrapper errors**: all 60 from the earlier
  baseline plus one unrelated worktree that appeared during the session. The scoped checks and
  negative regressions pass. The full-audit baseline remains a limitation.
- **Headless runtime readiness has not been established.** Claude/Pi must use safe inline
  execution until their host passes the canonical boundary and readiness gates. Native Luna
  delegation was exercised in this session.
- Changes are local and uncommitted; other hosts have not been synced.

Opus also suggested stronger protection of individual policy phrases, an environment-filtering
launcher example, richer per-host readiness receipts, and runtime telemetry checks. These are
nonblocking follow-ups; they are not evidence that the headless route is ready.

## Evidence and reversal

Scoped inputs, both Opus outputs, conductor responses, reviewed hashes, and verification logs
are retained locally under
`~/.local/state/codex/luna-delegation/2026-09-08/opus-review/review/`.
The review corrections have before/after hashes and an audit log in the parent directory.

To reverse the review corrections, run:

```sh
python3 ~/.local/state/codex/luna-delegation/2026-09-08/opus-review/activate.py rollback
```

Only after that succeeds, the original activation can be reversed with:

```sh
python3 ~/.local/state/codex/luna-delegation/2026-09-08/activate.py rollback
```

Both refuse intervening edits. Neither publishes changes or synchronizes another host.
