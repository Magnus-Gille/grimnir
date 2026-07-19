# Grimnir — Observability and the Self-Improving Loop

> Architectural status and roadmap for evidence-driven task delegation.
> Last updated: 2026-07-19.

## Purpose

Grimnir's self-improvement goal is to learn, from governed evidence, which model, route, prompt,
harness, and tool policy produces useful outcomes for a bounded task. The normative cross-repository
join is [LearningTaskContract v1](learning-task-contract.md); the meaning of “improve models” is
settled by [ADR-006](adr-006-learning-improvement-scope.md).

This document replaces the older assumption that all components already participated in one generic
`trace → score → reflection → few-shot/routing` pipeline. The implemented system has three evidence
planes and important gaps between them.

## The three evidence planes

| Plane | Owner | Authoritative facts | It does not own |
|---|---|---|---|
| Task and product | Hugin | Hugin-origin task/source identity, lifecycle and retries, repository/publication outcome, immutable Quality Receipts and experiment product ratings, corrections/successors, prompt/harness experiments and macro-routing | Direct M5 request identity, effective M5 model/config, exposure, capability verdict, or micro-routing |
| Inference and capability | `gille-inference` | Direct gateway-origin identity, gateway exposure/render, effective served model/artifact/config, deterministic/calibrated verifier evidence, capability ledger, model roster and micro-routing | Hugin task/product truth, human corrections, or prompt/harness promotion |
| Contract seam | Grimnir contract, produced by both | Field ownership, canonical raw-task join, version compatibility, governance and producer/consumer conformance | A new evidence database or authority to overwrite either producer |

Munin is storage and discovery for some Hugin records; it is not a fourth scoring authority. Heimdall
may visualize these planes; it does not create their verdicts.

## The actual loop

```text
Hugin task + raw-task identity
       |
       +--> execution/repository/publication outcome
       |             |
       |             +--> immutable Quality Receipt / correction (manual today)
       |
       +--> authenticated request stamp <--> gateway echo
                         |
                         +--> M5 exposure + exact served-model identity
                         |
                         +--> capability evidence (verified or shadow)

joined, governed candidate
       --> independent verifier + frozen sample
       --> one-axis champion/challenger experiment
       --> reviewed reject or promotion-ready decision
       --> owning repo applies exact change and records rollback
       --> subsequent production evidence checks the result
```

The middle join and candidate-to-experiment path are future work. Therefore the loop is not yet
operationally closed, even though substantial evidence capture and experiment machinery exists.

## Evidence maturity vocabulary

These labels are the target cross-system vocabulary. Grimnir uses them now; component docs,
dashboards, and status writers migrate through the implementation tickets and must map any older
local terms explicitly until adoption:

- **Implemented:** code emits or enforces the mechanism on its intended production path. This does
  not claim healthy live volume or complete coverage.
- **Shadow:** production traffic may produce evidence, but the result cannot change normal routing
  or the champion. Shadow outcomes are not verified savings.
- **Manual:** a human must make or apply the decision. Manual is a deliberate safety boundary, not
  an implementation defect.
- **Future:** the contract or roadmap specifies the capability, but no complete operational path
  exists. Documentation must not describe it in present tense.

### Current mechanism map

| Mechanism | State | Boundary |
|---|---|---|
| Hugin task/result and managed-repository evidence | Implemented | Captures execution facts; successful completion is not product quality. |
| Hugin Quality Receipt v1 | Implemented mechanism; manual use; concurrency partial | Receipts are native immutable review facts, but the current task-embedded summary can still lose the first pair: two concurrent first writers can both observe no feedback, pass `current?.updated_at` as undefined, and perform unconditional Munin writes. The v1 seam exports each surviving receipt as its own record and never treats the mutable summary as evidence completeness. Closing first-create storage remains required. |
| Hugin daily candidate factory | Implemented | Content-blind, rolling candidate snapshot only; not a sealed holdout, durable registry, evaluation, or promotion path. |
| Hugin controlled experiment ledger/evaluator | Implemented | One-axis matched evaluation and champion lineage; current reusable runner is narrow. |
| M5 task exposure registry | Implemented | Observed events exist for declared lanes. A contract negative-coverage query is a separate bounded assertion over exactly chat, mcp-ask, delegate, delegate-disagreement, delegate-shadow, and code-loop; direct loopback calls and incomplete history remain explicit. |
| M5 capability ledger and deterministic verifiers | Implemented | Sole node/model/task capability truth; unverified evidence cannot be promoted by Hugin. |
| M5 organic judge and delegate policy | Shadow | Must remain non-authoritative until representative human calibration, independent evidence, and versioned admission policy pass. |
| Hugin↔M5 authenticated stamp/echo | Future | Hugin currently sends one unstamped request and the gateway does not yet return the exact authenticated join echo required by v1. Capability-negotiated dual read/write precedes enforcement. |
| Product rating, candidate approval, verifier approval, change deployment | Manual | Human-reviewed by design in v1. |
| Durable all-outcome registry and candidate packager | Future | Required to connect ordinary failures/successes to experiments. |
| Verified Hugin-experiment import and guarded route reload | Future | Required to turn reviewed evidence into operational micro-routing. |
| Model-weight training | Future, outside v1 | Requires the separate gates in ADR-006. |

## What a trustworthy observation requires

The required fields and owner are normative in
[LearningTaskContract v1](learning-task-contract.md). In summary, a decision-driving observation
must bind:

- one stable task/source instance and canonical task taxonomy version;
- the raw task fingerprint plus Hugin envelope, gateway canonical envelope, and runtime chat-template
  render as distinct separately versioned identities;
- exact execution attempt, input/output/repository references and hashes;
- effective llama-swap runtime, provider, model artifact manifest, effective runtime config, and
  post-default/post-clamp sampling digests with reproducible canonicalization;
- origin prompt/harness/tool config plus effective gateway harness/tool config and separate macro-
  and micro-routing policy/decision identities;
- execution, repository, publication, immutable late product review, and capability outcomes without
  collapsing them;
- failure/correction/successor and authenticated reviewer provenance; and
- an authenticated Hugin request stamp and gateway echo for joined traffic;
- exact typed per-source/derivative governance or explicit policy-unavailable denial; and
- the reduced content-removal tombstone only after all store readbacks and backup expiry complete.

A missing field remains missing. An inference, successful exit, changed file, model self-report, or
uncalibrated judge does not fill an owner-controlled product or capability verdict.

## Evaluation and improvement rules

### Deterministic and human evidence first

Use deterministic verifiers where a bounded task has a real oracle. Human product review provides
the highest-value correction signal. Store a governed correction/successor reference, not merely a
score. LLM judges are advisory until a representative, versioned human calibration set clears the
predeclared reliability gate. Capability admission additionally requires an independent passing
verifier and a versioned policy epoch; policy changes append/regrade rather than rewrite history.

### Late reviews append; they do not patch observations

Quality Receipts and experiment product ratings are separate immutable contract records. A reader
groups them by exact binding and rubric version: Quality Receipts compare the full rating plus
disposition tuple, experiment ratings compare product outcome, disagreement summarizes to
`conflicted`, and no records means `unrated`. Newest-wins is not allowed. Neither a task outcome nor
an experiment observation grows a mutable product scalar.

### One causal axis

An experiment changes one semantic axis: route/roster, prompt, harness, tool policy, or another
predeclared configuration field. Every arm binds immutable configuration and corpus fingerprints.
Matched pairs, independent verification, product coverage, and declared correctness/cost/latency/
human-rescue guards determine the disposition.

### Negative results are learning, not improvement

A challenger that loses leaves the champion unchanged and records the dominant failure plus next
hypothesis. That improves knowledge but not the production baseline. Documentation must not count a
rejected challenger as a deployed improvement.

Exposure freshness is narrower than contamination detection. Exact trimmed-byte hashes do not find
Unicode-normalized equivalents, paraphrases, or semantic leakage. A registry restart starts a new
coverage epoch; raw llama-swap loopback is outside the authenticated six-lane registry and makes the
affected holdout window incomplete until routed through a declared lane. Monthly evaluation reports
epoch restarts, incomplete duration, raw-loopback detections, `exposure-incomplete` exclusions, and
candidate-starvation rate rather than claiming the holdout is contamination-proof.

### Promotion is reviewed and reversible

`promotion-ready` is an evidence state. The owning repository's human operator applies the exact
reviewed prompt/harness/route/roster/config reference, advances the champion, observes the declared
window, and retains a rollback. Neither Hugin nor `gille-inference` may silently deploy a candidate
in v1.

## Roadmap to a closed loop

| Order | Owning repo | Deliverable | Exit evidence |
|---:|---|---|---|
| 1 | Grimnir + both reviewers | Adopt v1 seam and immutable shared fixtures | Hugin and `gille-inference` owner reviews recorded; both consumer suites accept the same fixture. |
| 2 | Hugin + `gille-inference` | Capability-negotiated stamp/echo and canonical raw/exposure identity | Real authenticated Hugin stamp is exactly echoed; substitution and retry-identity tests fail closed; six-lane negative query is separate from observed events. |
| 3 | Hugin + `gille-inference` | Three-stage prompt and reproducible effective-serving provenance | Captured Hugin, gateway, runtime, manifest, runtime-config, and sampling sources recompute to the exported digests. |
| 4 | Both producers | Complete governance/erasure projections | Direct-owner policy lookup meets its SLO; unavailable policy denies; all stores and backup expiry produce readback receipts. |
| 5 | Hugin | Close receipt first-create concurrency; append immutable review records and durable all-outcome registry | Parallel first receipts are preserved; failures/no-ops/publication failures and late labels stay joinable without mutating observations. |
| 6 | Hugin | Independent candidate packager | A governed production candidate is rechecked, frozen, independently verified, and imported into a one-axis experiment. |
| 7 | `gille-inference` | Versioned capability admission and verified experiment import | Only independent calibrated passing evidence affects capability state. |
| 8 | `gille-inference` | Reviewed routing-table lifecycle | Generate, diff, approve, deploy/reload, canary, and rollback are demonstrated without silent promotion. |
| 9 | Hugin | Read-only next-experiment proposals | Proposals cite evidence and require human approval; they do not mutate prompts/routes/config. |

The measurable definitions of continuous capture, evaluation, learning, and baseline improvement
live in the contract. Until their rolling gates pass, use the narrower current state—implemented
capture plus manual/shadow evaluation—rather than “continuous self-improvement.”

## Per-component signals outside the delegation loop

Every component should still expose operational and product signals appropriate to its role, but
those signals do not automatically enter the task-delegation learning contract.

| Component | Primary signal | Boundary |
|---|---|---|
| Skuld | Reviewed briefing usefulness and factual/source coverage | A briefing-specific evaluator, not M5 capability evidence by default. |
| Ratatoskr | Correct routing and first-response resolution | Corrections may create Hugin product evidence only through an explicit task join. |
| Heimdall | Alert accuracy and collection reliability | Observes health; does not grade task quality. |
| Munin | Search relevance and storage correctness | Stores evidence; does not assign capability verdicts. |
| Mimir | Retrieval success and integrity | Artifact owner; references remain governed. |

## Safety principles

1. **One owner per fact and decision.** Storage location does not transfer authority.
2. **Content is governed at every derivative.** Hashing is not anonymization; allowed use is
   explicit and erasure propagates.
3. **Freshness fails closed.** Negative exposure matters only inside complete declared coverage and
   is rechecked immediately before freeze and execution.
4. **Calibrate before policy.** Uncalibrated model judging remains shadow evidence.
5. **Store correction lineage.** A product verdict without the corrective successor cannot support
   the strongest forms of learning.
6. **Independent verification beats model prose.** Self-reported success is never its own oracle.
7. **Manual promotion in v1.** Automation may gather and propose; a human applies consequential
   configuration changes.
8. **No hidden model training.** Evaluation/routing data is not a training dataset; ADR-006 governs
   any future exception.
