# Debate summary: How many humans would the last 6 months of output have taken?

**Date:** 2026-07-13
**Participants:** Claude (Fable 5) vs. Codex (`gpt-5.6-sol`, reasoning effort: high)
**Rounds:** 2
**Question:** For everything built 2026-01-12 → 2026-07-12, how many developers and other roles
would be needed to produce the same output without AI?

---

## Final answer

> **~6 full-time engineers' worth of productive output over six months** — which in practice means
> **hiring 6–10 people**, because nobody runs at 100% utilization.
>
> Against a **measured ~0.5 FTE** of Magnus's own time. Order-of-magnitude labor multiplier
> (~12×, treated as a hypothesis, not a measurement).
>
> This is a **low-confidence Scenario-B estimate**: reproduce the artifacts that exist, at
> personal-project quality, with requirements handed over on day one. It is not a measurement.

**The number depends on the question, and the honest band is 3–12:**

| Scenario | The team is asked to… | FTE |
|---|---|---|
| **A — Outcome equivalence** | Deliver the same *useful outcomes* to one user: consolidate services, buy/reuse OSS, drop the dead experiments | **3–4** |
| **B — Artifact reproduction** *(the literal question)* | Rebuild what actually exists, personal-grade, spec supplied free on day one | **~6** (6–10 hired) |
| **C — Historical replay** | Start from January with no spec: discover, take the wrong turns, and *operate the fleet live* for 6 months | **10–12** |

Composition at Scenario B: 4–5 engineers (one staff-level, one LLM-infra, one or two
backend/full-stack, one embedded/DSP generalist), 1 DevOps/SRE, ~0.5 security, ~0.5 technical
writer, ~0.5 PM, ~0.25–0.5 QA/eval, plus fractional research-analyst and ops/EA capacity for the
non-repo output.

## Measured corpus (frozen, reproducible)

Re-derive with `scripts/output-audit.py`; every repo's HEAD SHA is pinned in
`team-equivalent-6mo-manifest.json`.

| | |
|---|---|
| Repos | **44** (all created *inside* the window) |
| Commits | **2,634** — Magnus 2,481 · agents 137 · CI 10 · other humans 6 |
| **Magnus+AI share** | **99.4%** |
| Standing artifact | **670,879 lines** (526,233 source + 144,646 docs), vendored excluded, blob-deduped |
| Magnus's own input | **~556 h** (512–608 h) ≈ **0.5 FTE** ≈ 3.2 person-months; 332 sessions, 145 active days of 182 |

## What each side got wrong

**Codex's decisive round-1 finding was false.** It claimed "TantRagnar" was a second human whose
commits invalidated the Magnus+AI attribution — inferring a third party from a surname in an email
address, without checking. Verification (Claude co-author trailers on 59/63 commits, repo
ownership, the Feb 2026 git-config switch, and the owner's direct confirmation) established
TantRagnar as Magnus's own former identity. Real non-Magnus contamination: **6 commits of 2,634
(0.2%)**. Codex retracted in full in round 2 and named the failure precisely: *"I treated author
metadata as conclusive while arguing that author metadata needed auditing."*

**Claude's flagship self-criticism was arithmetically broken.** The LOC cross-check — offered as
the strongest evidence *against* its own headline — was wrong by a factor of ten (120–180k lines at
50–100 LOC/day is 60–180 person-months, not the "6–16 developer-months" claimed). Corrected, it
doesn't support the low end at all; it points *above* the 37-PM table. Withdrawn entirely. The
awkward consequence: removing Claude's best objection to its own number made that number **more**
robust.

**Claude also took credit for Codex's work.** The headline moved from 8 FTE to 6 because of
Codex's arithmetic criticism (37 PM ÷ 6 months = 6.2), not because of Claude's git forensics. The
line "the audit did that, not the argument" was self-flattering and false. The audit validated the
*corpus*; it never validated the *effort table*.

## Concessions accepted by both sides

- The counterfactual was never fixed; the draft asserted "80% wouldn't have been built" (an
  invented figure, withdrawn) and then priced full reproduction anyway. Now split into A/B/C.
- The original counts were never author-filtered — repos were filtered, commits were not.
- "300–500k real lines" was a guess. Measured: 670,879 (the guess was ~40% low).
- 8 FTE never reconciled with a 37-PM table. It doesn't. It's 6.2.
- The "Brooks's law" appeal was lazy — this portfolio is 44 near-independent repos, so coordination
  overhead is *lower* than a normal 8-person team, an argument that cut against Claude's own number.
- **Caveats that don't move the estimate are decoration.** Codex's sharpest point, and the standard
  the revision was held to.

## Unresolved (and where both sides agree the work is)

**There is no deliverable/acceptance ledger.** Components are priced by what was *built*, not by
what actually *runs*. Live state cuts both ways: Grimnir/Hugin/Heimdall have passing suites and
verified deployments, while Verdandi is dead after a data-path failure and 97,000+ restarts. Until
each of the 44 repos is tagged deployed / exercised / prototype / abandoned, the 37-PM numerator
stays uncalibrated expert judgment. **Both sides expect that ledger to move the estimate down.**

Also unresolved: the 37-PM table itself has no work-breakdown structure, no reference class, and no
independent estimator. It never moved during the debate.

## Verdict

Both models converged on the same number and the same confidence level. Codex: *"About 6 productive
FTE for six months to reconstruct the frozen, personal-grade functionality from supplied
requirements — explicitly a low-confidence Scenario-B midpoint, not a measurement."* Claude agrees.

**Do not quote "6 FTE" or "12×" stripped of the scenario label.** Round numbers become anchors and
caveats get dropped in retelling.

## Action items

| # | Action | Owner |
|---|---|---|
| 1 | Build the deliverable/acceptance ledger: tag all 44 repos deployed / exercised / prototype / abandoned, then re-estimate the 37-PM numerator against it | grimnir |
| 2 | Keep `scripts/output-audit.py` as the single source of truth for output-volume claims | grimnir |
| 3 | Fix Verdandi (dead, 97k+ restarts) — it is both an operational bug and the clearest datapoint that "built" ≠ "works" | verdandi |

## Files

- `team-equivalent-6mo-claude-draft.md`
- `team-equivalent-6mo-claude-self-review.md`
- `team-equivalent-6mo-codex-critique.md` (round 1)
- `team-equivalent-6mo-claude-response-1.md`
- `team-equivalent-6mo-codex-rebuttal-1.md` (round 2)
- `team-equivalent-6mo-claude-response-2.md` (final)
- `team-equivalent-6mo-critique-log.json` (19 points)
- `team-equivalent-6mo-manifest.json` (frozen corpus)
- `scripts/output-audit.py` (canonical, reproducible)

## Costs

| Invocation | Wall-clock | Model |
|---|---|---|
| Codex R1 | ~6 min | gpt-5.6-sol (high effort) |
| Codex R2 | ~7 min | gpt-5.6-sol (high effort) |

## Scorecard

19 critique points. **14 valid, 2 partially valid, 3 invalid.** Self-review caught 6 of 19 (32%) —
its worst miss was the LOC arithmetic error, which it *originated*. Codex's two round-1 criticals
included its single worst error (TantRagnar) and its single best (the FTE arithmetic). The
cross-model gap paid for itself: neither model would have caught its own flagship mistake.
