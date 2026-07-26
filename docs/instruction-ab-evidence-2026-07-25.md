# Instruction-file A/B evidence — 2026-07-25

Evidence note for the `AGENTS.md` → `docs/index.md` progressive-disclosure split (grimnir#143).

Method: a frozen probe set run through headless Claude Code in two git worktrees differing only in
their instruction files. Harness `scripts/tests/ab-instructions-eval.sh`; probes
`tests/fixtures/instruction-probes/probes.json`, committed before the split was authored so they
could not be written to match the new index.

Model: `sonnet`. Arms: `before` = unmodified `AGENTS.md`, `after` = split. Raw JSONL streams were
retained locally under `outputs/` and are **not** committed (18 MB); the per-run summaries below are
the durable record.

### Post-evidence evaluator hardening

The reported runs predate the sandbox correction added during recovery of this PR. They ran with
user settings active, where `permissions.defaultMode="auto"` meant their `--allowedTools` argument
was not actually a hermetic boundary, and MCP remained available. The retained raw streams were
checked during recovery: they contain shell, read-only GitHub/Munin queries, and read-only SSH
inspection, but no repository, service, or external-system mutation was observed. The runs were not
repeated, so their results remain historical measurement evidence—not sandbox-verified evidence.

The committed harness now uses project-only setting sources so each arm's project
`CLAUDE.md`/`AGENTS.md` remains loaded while user policy cannot widen the tool surface. It also uses
a strictly empty MCP configuration and explicitly denies command, mutation, network, and dispatch
tools, leaving only `Read`, `Grep`, and `Glob`. `tests/scripts/test-instruction-eval-sandbox.sh`,
wired into `make test`, pins those guards and the explicit `sonnet` default for future runs.

## Metrics

- **doc-hit** — did the agent open the document that answers the question, read mechanically from
  the tool-call stream. Primary metric for retrieval probes.
- **assert** — did the answer carry the recorded constraint. Primary metric for policy probes,
  where the correct behaviour may be to answer from the instruction file without opening anything.
- **prompt tokens** — `cache_creation + cache_read + input` on the first assistant iteration.
  Stable across reps regardless of cache warmth, unlike cost.

The control probe (`repo-visibility-CONTROL`) targets House-rules text that is identical in both
arms. Its `doc_hit` is structurally 0 — `AGENTS.md` is injected, never opened as a tool call — so it
is scored on `assert` only, and it passed 3/3 in both arms in every run.

## Final result (run 4, v3 pointer)

| | before | after |
|---|---|---|
| retrieval (doc-hit) | 28/30 | 28/30 |
| policy + control (assert) | 9/9 | 9/9 |
| mean prompt tokens | 41,049 | 38,575 |

Parity holds probe-by-probe. `session-posture` scored 1/3 in **both** arms in this run after
scoring 3/3 in runs 1–2 — unexplained probe variance, not attributable to the change. `AGENTS.md`
went from 1325 to 698 words. Both arms recorded `errors: 0` in all four runs, so no run was scored
as a miss because it failed or timed out.

**Read the denominators carefully.** The table above is the *retrieval-only* slice (10 probes × 3).
The iteration history below quotes *whole-set* rates (all 13 probes × 3), because that is what runs
1–2 were scored on. Under that same whole-set metric run 4 is **before 0.872 / after 0.795** —
numerically below run 2's 0.846. The entire 7.7-point gap is `verdandi-restart` going 3/3 → 0/3,
which is the desirable behaviour described under Findings, not a retrieval loss. Both framings are
stated here rather than only the flattering one.

The `before` arm was built from `7579a6e`, whose `AGENTS.md` is 1273 words. The PR's merge-base is
`1497326` at 1325 words — #141 and #142 added ~52 words of index after the probe freeze. So the arm
measured an instruction file two commits older than the one actually being replaced. No probe
targets the maintenance-policy docs, and the extra 52 words would only widen the token gap in the
change's favour, so the direction of the result is unaffected.

### Per-probe record (run 4)

Reproduced here because `outputs/` is gitignored: without this table the headline numbers are not
checkable from the repository alone, and the raw streams do not survive a fresh checkout.

| probe | kind | before doc-hit | after doc-hit | before assert | after assert |
|---|---|---|---|---|---|
| `repo-visibility-CONTROL` | control | 0/3 | 0/3 | 3/3 | 3/3 |
| `skuld-gate` | policy | 3/3 | 3/3 | 3/3 | 3/3 |
| `verdandi-restart` | policy | 3/3 | 0/3 | 3/3 | 3/3 |
| `data-lifecycle` | retrieval | 3/3 | 3/3 | — | — |
| `deploy-binding` | retrieval | 3/3 | 3/3 | — | — |
| `failure-recovery` | retrieval | 3/3 | 3/3 | — | — |
| `role-separation` | retrieval | 3/3 | 3/3 | — | — |
| `service-inventory` | retrieval | 3/3 | 3/3 | — | — |
| `session-posture` | retrieval | 1/3 | 1/3 | — | — |
| `succession` | retrieval | 3/3 | 3/3 | — | — |
| `tenant-contract` | retrieval | 3/3 | 3/3 | — | — |
| `threat-model` | retrieval | 3/3 | 3/3 | — | — |
| `worktree-hygiene` | retrieval | 3/3 | 3/3 | — | — |

## Iteration history

| run | pointer | before | after | note |
|---|---|---|---|---|
| 1 | v1, sample enumeration | 92% | 74% | two probes to ~0; 6 runs made zero tool calls |
| 2 | v2, categorical | 92% | 84% | `session-posture` 0/3→3/3, `failure-recovery` 1/3→3/3 |
| 3 | v2, power-up on 4 unstable probes (n=5) | — | — | pooled with run 2: before 56/56, after 52/56 |
| 4 | v3, entity names added | parity | parity | `skuld-gate`, `succession`, `role-separation` recovered |

Runs 1–3 rates are restated under the corrected detector (see below), not as originally reported.

## Findings

**The failure mode of progressive disclosure is confabulation, not slow retrieval.** In run 1,
**five `after`-arm runs made zero tool calls against zero in `before`**: the agent did not search and
come up empty, it produced a confident and well-structured invented account of the recovery
convention. The inline descriptions had been signalling *that a recorded answer exists*, not merely
where it lives. (Seven runs made zero tool calls in total, but two of those were the control probe,
where making no tool call is the *correct* behaviour — and the `before` arm did it too. Only the
five are anomalous.)

**Partial enumerations read as exhaustive.** v1's pointer listed a sample of topics; the
worst-scoring probes were exactly those absent from the list. This recurred one level down: v2 named
topics but no components, and the residual misses were all entity-phrased queries ("is *Skuld* worth
keeping", "restart *Verdandi*"). Naming the component decision records closed the gap.

**A constraint moved inline stops being retrieved, correctly.** `verdandi-restart` shows doc-hit
3/3 → 0/3 in run 4 while `assert` holds 3/3. With the not-authorized status stated in `AGENTS.md`,
the agent declines immediately and cites the instruction file. Scored on the metric that applies to
it, that is an improvement; scored on doc-hit alone it reads as a regression.

## What doc-hit cannot see

Independent review of this change found a blind spot in the primary metric, and it is the most
important thing recorded here.

`doc_hit` measures whether an agent *that was asked a question* goes and opens the right document.
It cannot measure an agent that was **never asked**, and therefore never realised a constraint
applied. So a rule that states an *obligation* rather than a *location* loses something real when it
moves behind the index, and the eval reports parity regardless.

Three such rules were caught before merge: the autonomous-mutation reversal recipe **and audit
event** (of which "audit event" had been dropped from both files entirely), the required Hugin
handoff after untrusted input, and the canonical-checkout/deploy-target separation. All three are
now stated inline in `AGENTS.md` and guarded by `REQUIRED_INLINE_RULES` in
`tests/scripts/test-doc-index.sh`.

The general rule for anyone repeating this on another repository: **classify by whether the text
changes what an agent does, not by whether it looks like a table.** Reference material moves;
obligations stay. A metric that only scores retrieval will not warn you.

A second review finding in the same family: an early version of the pointer named Hugin, Munin and
Brokkr among the per-component decision records and instructed the agent to "assume a record
exists". No such records exist. That is the run-1 confabulation defect reintroduced from the
opposite direction — by over-enumeration rather than under-enumeration. Corrected to name only the
records that exist, and to say *check before concluding none exists*.

## Harness defect found mid-flight

The doc-hit detector used `jq -e` over a JSON stream. That exit status reflects only the **last**
emitted value, so a run counted as a hit only when the target appeared in its final tool call. Runs
that opened the right document and then kept exploring scored as misses.

This was not arm-neutral — the `after` arm makes more tool calls, so it was penalised more often,
biasing the comparison against the change under test. Fixed in the harness;
`scripts/tests/ab-rescore.sh` recomputes verdicts from retained raw streams, so the correction cost
one re-score rather than 78 re-runs. Retaining raw streams is what made that cheap, and is why the
harness writes them by default.

## Pre-existing index rot found by the guard

`tests/scripts/test-doc-index.sh` found three documents missing from the **original**
`AGENTS.md` index, unrelated to this change:

- `docs/vision.md` — the v0.2 decision rule the rest of the corpus defers to
- `docs/ecosystem-review-plan.md`
- `docs/GRIMNIR_DEVELOPMENT_PLAN.md` — whose "⛔ SUPERSEDED. Do not execute this plan" marker was
  invisible to anything that reached it by globbing

It then caught #141's two new documents automatically when that merged mid-session.

## Reproducing

```bash
git worktree add /tmp/ab-before <base-sha> --detach
scripts/tests/ab-instructions-eval.sh --before /tmp/ab-before --after . --reps 3
```

Cost roughly $25–30 in Sonnet tokens across the four runs reported here.
