# Autonomous self-improvement — design v0.1

**Status:** adopted direction (owner decision, 2026-07-20). Implementation tracked in
grimnir#88 Phase 4.
**Owner ask:** *"design this thing so that a human in the loop is not needed. rely only on
automatic self improvement, data driven, based upon facts being harvested by using the
system."*

This document designs the removal of the human **approval** step from the operating loop.
The system continuously improves itself from harvested production facts; the owner is
*on* the loop (visibility, veto, kill switch) but never *in* it — no progress ever waits
on a person.

## 1. Scope and the one axiom

**In scope — the operating loop:** model selection (routing tables), usage policy
(delegation/verifier policy), harness choice (one-shot vs `code_loop`/opencode lanes),
and served-model roster changes.

**Out of scope (non-goals):**

- Autonomous modification of the repos' *code* — development stays PR + review under the
  house rules. This program automates operating decisions, not software changes.
- Irreversible actions: harvest-data deletion (live retention pruning), key material,
  external publication. These stay owner actions — not because improvement needs
  approval, but because the axiom below cannot be satisfied for them.

> **Axiom — autonomy over reversible mutations only.** The system may autonomously
> perform any improvement mutation for which it can **(a)** prove admissible evidence
> mechanically and **(b)** hold a tested reversal recipe
> (`docs/failure-recovery.md`, grimnir#46). Irreversible ⇒ not autonomous.
> "Human approves" is replaced by "system proves, and can undo."

## 2. Replace the reviewer with proofs

Everything the human reviewer checked during the first live adoption (2026-07-20) becomes
a machine-verifiable predicate. A change **auto-adopts iff every predicate passes**; any
unprovable predicate fails closed and the change remains a *standing proposal* — visible,
durable, waiting for **data**, never for a person.

| The human asked | Mechanical replacement | Exists? |
|---|---|---|
| Is the evidence trustworthy? | Admissibility: verifier-backed/deterministic classes always; organic-judge evidence only under **auto-calibration GO** (§3) | #6 gate + `gateAdmitsOrganicEvidence` live; label source changes (gi#48) |
| Is the improvement real, not noise? | Conservative CI bound of challenger beats incumbent by margin **δ** at **n≥N**, evidence within freshness TTL | #234 proposer's z-test machinery; thresholds move into policy (gi#49) |
| Will it break serving? | The #7 `validateCandidate` stage: taxonomy completeness, served-model availability, downgrade guards, policy epoch | Live (`routing-lifecycle.ts`) |
| Is the blast radius sane? | Risk budget: ≤K changes/window, one axis per change, per-route cooldown, protected lanes (§5) | gi#49 |
| What if it is wrong anyway? | Canary (live) + post-adoption **watch window with auto-revert and quarantine** (§4) | Canary live; watchdog is gi#47 |

## 3. Ground truth without a human

Three anchor classes, none requiring human labels:

1. **Deterministic verifiers** — tests, execution-graded outputs, the seeded-bug
   review corpora with independent recall/precision/confabulation (gi#12). Truth by
   construction. First-class evidence from day one.
2. **Harvested production outcomes** — error, retry, escalation, verifier-fail rates;
   completion; latency; cost — the ledger facts (2,700+ delegation rows and growing).
   These are the *guard metrics* the watchdog defends (§4).
3. **Adjudicated judgment** — for task types with no verifier (rewrite, qa-factual), a
   **family-diverse adjudicator** (frontier model, never the same family as the judged
   candidate) whose own agreement with anchor class 1 is continuously measured on
   overlap items. Organic-judge evidence is admissible only while rolling anchored
   agreement ≥ κ. Below κ, or on a stale sample → the existing fail-closed HOLD.

gi#48 swaps the **label source** of the #6 calibration gate to these anchors; the
HOLD/GO machinery, non-bypassable enablement, and fail-closed defaults are reused
verbatim. Human labels remain *supported* as an optional extra anchor — never required.

## 4. Every mutation wears a parachute

Adoption pipeline (per mutation): `snapshot → validate → adopt → reload → canary →`
**watch window** (new, gi#47): for W hours / T affected tasks, compare guard metrics on
the changed routes against the pre-adoption ledger baseline.

- **Breach ⇒ auto-revert** to the exact snapshot + audit event + reversal record +
  Ratatoskr notification, and **quarantine**: that axis returns to propose-only until a
  fresh experiment passes with a stronger margin (hysteresis δ′ > δ) and a per-route
  cooldown elapses.
- Reverts are not failures of the design — they *are* the design. Each costs one bounded
  window of degraded routing; that is the price of not needing a human, and it is paid
  in a currency the system can afford (reversible time, not lost data).
- Watch-window state is durable across restarts and deploys (the gi#44 discipline:
  runtime state never lives where a deploy can clobber it).

## 5. Protected lanes — the loop must not improve away its own brakes

Hard deny-list, never auto-mutated: auth/keys, owner-priority policy, the safety-gate
parameters themselves (calibration thresholds κ, promotion margins δ/N/K, watchdog
config), retention/erasure enablement, deploy tooling. The loop may *propose* changes
here; only the owner adopts. This is an engineering necessity, not a philosophical
hedge: a system able to relax its own measured gates can trivially game every predicate
in §2, and the whole evidence chain loses its meaning.

## 6. The autonomy ladder — autonomy itself is promoted on evidence

The loop earns wider autonomy the same way models earn routes: from its own harvested
operating record. Tier state is computed, not configured.

| Tier | What auto-adopts | Unlock condition (computed from the operating record) |
|---|---|---|
| **0** (today) | Nothing — propose-only | — |
| **1** | Verifier-backed routing changes within risk budget | gi#44 fixed **and** C1 consecutive healthy scheduled cycles (valid proposal or clean no-op, zero infra failures) |
| **2** | Adds organic-evidence-driven changes (auto-calibrated per §3) | Anchored agreement ≥ κ sustained over window R **and** Tier-1 revert rate ≤ r with no unexplained canary failures |
| **3** | Roster/serving promotion behind the gi#12 serving gates + shadow eval + VRAM/disk budget | Tier-2 record **and** one demonstrated automatic model rollback |

**Demotion is automatic and symmetric:** breach of a tier's invariants (revert storm,
watchdog blind spot, agreement collapse) drops the tier without human action. The
recursion is deliberate — the loop that improves M5 also measures and improves *its own
license to act*.

Proposed defaults (tunable at implementation, recorded in gi#49): K=3 changes/week,
δ=5 pp at the 95% conservative bound, W=72 h or 50 tasks, κ=0.85, C1=10 cycles, r=20%.

## 7. Owner on the loop, never in it

No step ever awaits approval. The owner retains:

- **Kill switch** — one env/flag checked before every autonomous adopt; pauses all
  autonomous mutation instantly (proposals continue accumulating).
- **After-the-fact notification** — every adoption/revert pushes a Ratatoskr message
  with the diff and a one-command revert.
- **Audit trail** — Verdandi/Munin audit events (gi#14) + the reversal recipe per
  mutation (grimnir#46 convention).
- **Off-ramp** — the succession checklist and system-ROI off-ramp (#65/#67) apply
  unchanged.

Silence never blocks the loop; a veto is always one command.

## 8. Failure modes → defenses

| Failure mode | Defense |
|---|---|
| Benchmark gaming | Versioned, rotated corpora + seeded bugs (gi#12); production guard metrics must corroborate bench wins before Tier promotion |
| Reward hacking on a single metric | Multiple independent guard metrics with a must-not-regress set; watchdog breaches on any |
| Judge–candidate collusion / self-grading | Family-diverse adjudicator + continuously measured anchored agreement (gi#48) |
| Drift (stale evidence, stale models) | TTLs on evidence and calibration; #7 re-validation at adopt time |
| Oscillation / thrash | Hysteresis (δ′ > δ after revert) + per-route cooldown + quarantine (gi#47) |
| State loss reverting improvements | gi#44 durability + the worktree/deploy hygiene audit (#87) |
| Runaway mutation | Risk budget + automatic tier demotion + kill switch |

## 9. Preconditions and build order (grimnir#88 Phase 4)

1. **gi#44** — adoption survives deploys (HIGH, in flight). Hard blocker: autonomy over
   improvements that a deploy silently reverts is theater.
2. **gi#46 / hugin#266 / hugin#267** — the cadence: scheduled route regeneration,
   experiment orchestration, standing sampled harness-lane harvest (filed 2026-07-20).
3. **gi#47** — regression watchdog + auto-revert + quarantine.
4. **gi#48** — verifier-anchored judge auto-calibration.
5. **gi#49** — autonomy controller: promotion predicates, risk budget, protected lanes,
   tier ladder, kill switch.
6. Enable **Tier 1**; the ladder takes it from there — by construction, on evidence.

## 10. What changed from the previous posture

The 2026-07-20 cadence note ("continuous evidence + measured gates + human-reviewed
promotion") is **superseded by owner decision** for the operating loop: promotion is now
mechanical wherever the §1 axiom holds. The human-review posture remains only where the
axiom fails (irreversibles, protected lanes) and for software development itself — a
scope boundary, not an approval gate on improvement.
