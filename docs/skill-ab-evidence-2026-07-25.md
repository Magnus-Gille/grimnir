# Skill-description A/B evidence — 2026-07-25

Evidence note for trimming Claude Code skill descriptions, using the same method as the
`AGENTS.md` progressive-disclosure split (grimnir#143) applied to a different surface.

Harness `scripts/tests/ab-skills-eval.sh`; probes `tests/fixtures/skill-probes/probes.json`, frozen
before any description was edited. Model `sonnet`, 25 probes × 2 arms × 2 reps = 100 runs.

## What was measured, and why it is smaller than it looks

A skill's `description` is injected into every session's system prompt and is the sole basis for
routing a request to it. Measured cost of the whole skill surface: **3,679 tokens**. But only the
26 personal descriptions are editable — the rest is name/wrapper overhead plus ~25 plugin and
built-in skills. Addressable material was **6,566 characters**.

MCP was measured and rejected as a target on this harness: munin-memory's 24 tools carry 42,533
characters of description and schema (~10.6k tokens), but disabling every MCP server saved only
**~230 tokens**, because Claude Code defers tool schemas via `ToolSearch` and loads names only.
That inference — schema size implies prompt cost — was wrong, and a direct probe refuted it. It
still holds for non-deferring clients (Codex, opencode, claude.ai).

## Result

| | before | after |
|---|---|---|
| trigger correct | 31/40 | 30/40 |
| control + negative | 10/10 | 10/10 |
| mean prompt tokens | 31,338 | 30,584 |
| errors | 2 | 2 |

**Controls held at 10/10 in both arms.** This was the failure mode most worth guarding: a trim can
raise its trigger rate by making descriptions vague enough to match anything, and only control and
negative probes catch it. They did not fire.

Shipped saving after the reverts below: **2,314 characters, ~578 tokens per session.**

## The one attributable regression, and why it was not fixed

`draft-email` went 2/2 → 0/2, firing `check-calendar` instead. The trim had dropped "structured
proposals, and clear next steps" while the probe says "*proposing* we meet next week" — so with
"proposals" gone, "meet next week" won.

That hypothesis was tested by restoring the vocabulary in compressed form and re-running at n=3. It
**failed**: `draft-email` stayed 0/3 and now also fired `check-email`. The hypothesis was wrong, or
insufficient.

The re-run also showed the **`before` arm dropping to 2/3 on the same probe**, having scored 2/2 in
the main run. The probe is ambiguous by construction — "write something to Anders" is email, "meet
next week" is calendar — so there is no stable baseline to attribute a regression against at this
sample size.

Conclusion: `draft-email` and `debate` were **reverted to their original descriptions**, making them
identical to the control arm and therefore incapable of regressing. That costs 240 characters of
the available saving and needs no further measurement. Chasing the remaining 240 characters through
a rewritten probe would cost more than it returns.

Two probes improved: `issues` 1/2 → 2/2, `share` 0/2 → 1/2. Both within noise at n=2; neither is
claimed as a win.

## Pre-existing routing failures, found incidentally

Three probes failed in the **unmodified** arm. These are properties of the current skill set, not
of the trim, and are the most valuable output of the exercise:

- **`delegate` 0/2.** "Summarise this changelog with something cheaper — no need to spend good
  tokens on it" never routed, although that is precisely the use case its description advertises.
  This is the skill the house rules direct every session to reach for.
- **`find-skills` 0/2.** "Is there something already built that handles this, or do I need to write
  it?" never routed.
- **`magnus-security-review` errored 2/2 in both arms** — the only errors in the run.

Filed as tickets against the owning repositories.

## Method notes for anyone repeating this

**Skills cannot be A/B'd by worktree.** They load from `~/.claude/skills`, a fixed global path, so
the two-worktree isolation used for instruction files does not transfer. `--plugin-dir` loads an arm
but the user skill set loads *as well*, leaving the original descriptions live so the trim is never
exercised. `CLAUDE_CONFIG_DIR` has no credentials; `--bare` cannot authenticate. Repointing the
symlink is the only isolation that measures the real thing, which is why the harness requires
`--i-understand-global-swap` and restores on `EXIT`/`INT`/`TERM`.

**The sandbox took three attempts, and two of them failed silently-ish.** Recorded because the
failure modes are not obvious:

1. `--allowedTools Skill` alone does nothing. `permissions.defaultMode="auto"` in the user settings
   auto-approves everything. A `check-email` probe ran four m365 Graph queries and spawned a
   subagent before the run was killed. `deploy` and `submit-task` were 17 probes later in the sweep.
2. The obvious fix, `--setting-sources project`, **breaks the experiment**: `~/.claude/skills` is
   itself a user-level source, so it removes the skill set under test. Every probe scored zero,
   which reads as a catastrophic regression rather than a broken harness.
3. The working design keeps user settings, disables MCP outright (`hugin_submit` dispatches real Pi
   work and `m5` spends real inference — both were observed executing under auto-approve), and
   disallows the write-capable built-ins. What remains reachable is read-only.

Pinned by `tests/scripts/test-skills-eval-sandbox.sh`, which asserts **both** halves — that nothing
can act, *and* that a skill still fires. Either alone passes while the harness is worthless. It
scores *executed* rather than *attempted* tool calls: a denied `Bash` call still appears as a
`tool_use` block in the stream, and counting attempts produced a false breach on the first pass.

**`claude -p` reads stdin in non-TTY contexts** and stalls 3 seconds before proceeding. Redirect
`< /dev/null`. One probe flaked on this before it was diagnosed.

## Limits

n=2 per probe per arm. That is enough to catch a systematic routing failure and to measure the token
delta, which is near-deterministic. It is **not** enough to resolve single-run differences —
`debate` 2/2 → 1/2 is reported but not interpreted. The two reverted skills are the honest response
to that limit rather than a claim of parity.
