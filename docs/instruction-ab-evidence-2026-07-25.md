# Instruction-file A/B evidence — 2026-07-25

Evidence note for the `AGENTS.md` → `docs/index.md` progressive-disclosure split (grimnir#143).

Method: a frozen probe set run through headless Claude Code in two git worktrees differing only in
their instruction files. Harness `scripts/tests/ab-instructions-eval.sh`; probes
`tests/fixtures/instruction-probes/probes.json`, committed before the split was authored so they
could not be written to match the new index.

Model: `sonnet`. Arms: `before` = unmodified `AGENTS.md`, `after` = split. Raw JSONL streams were
retained locally under `outputs/` and are **not** committed (18 MB); the per-run summaries below are
the durable record.

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
went from 1273 to 698 words.

## Iteration history

| run | pointer | before | after | note |
|---|---|---|---|---|
| 1 | v1, sample enumeration | 92% | 74% | two probes to ~0; 6 runs made zero tool calls |
| 2 | v2, categorical | 92% | 84% | `session-posture` 0/3→3/3, `failure-recovery` 1/3→3/3 |
| 3 | v2, power-up on 4 unstable probes (n=5) | — | — | pooled with run 2: before 56/56, after 52/56 |
| 4 | v3, entity names added | parity | parity | `skuld-gate`, `succession`, `role-separation` recovered |

Runs 1–3 rates are restated under the corrected detector (see below), not as originally reported.

## Findings

**The failure mode of progressive disclosure is confabulation, not slow retrieval.** In run 1, six
runs made *zero tool calls*: the agent did not search and come up empty, it produced a confident and
well-structured invented account of the recovery convention. The inline descriptions had been
signalling *that a recorded answer exists*, not merely where it lives.

**Partial enumerations read as exhaustive.** v1's pointer listed a sample of topics; the
worst-scoring probes were exactly those absent from the list. This recurred one level down: v2 named
topics but no components, and the residual misses were all entity-phrased queries ("is *Skuld* worth
keeping", "restart *Verdandi*"). Naming the component decision records closed the gap.

**A constraint moved inline stops being retrieved, correctly.** `verdandi-restart` shows doc-hit
3/3 → 0/3 in run 4 while `assert` holds 3/3. With the not-authorized status stated in `AGENTS.md`,
the agent declines immediately and cites the instruction file. Scored on the metric that applies to
it, that is an improvement; scored on doc-hit alone it reads as a regression.

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
