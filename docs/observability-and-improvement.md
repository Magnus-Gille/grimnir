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
| Task and product | Hugin | Task/source identity, lifecycle and retries, repository/publication outcome, product Quality Receipt, corrections/successors, prompt/harness experiments and macro-routing | Effective M5 model/config, exposure, capability verdict, or micro-routing |
| Inference and capability | `gille-inference` | Gateway exposure, effective served model/artifact/config, deterministic/calibrated verifier evidence, capability ledger, model roster and micro-routing | Hugin task/product truth, human corrections, or prompt/harness promotion |
| Contract seam | Grimnir contract, produced by both | Field ownership, canonical raw-task join, version compatibility, governance and producer/consumer conformance | A new evidence database or authority to overwrite either producer |

Munin is storage and discovery for some Hugin records; it is not a fourth scoring authority. Heimdall
may visualize these planes; it does not create their verdicts.

## The actual loop

```text
Hugin task + raw-task identity
       |
       +--> execution/repository/publication outcome
       |             |
       |             +--> Quality Receipt / correction (manual today)
       |
       +--> M5 gateway exposure + exact served-model identity
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

All architecture, status, dashboards, and issue handoffs use these labels:

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
| Hugin Quality Receipt v1 | Implemented mechanism; manual use | Separates product review from lifecycle; real review volume must be measured, not assumed. |
| Hugin daily candidate factory | Implemented | Content-blind, rolling candidate snapshot only; not a sealed holdout, durable registry, evaluation, or promotion path. |
| Hugin controlled experiment ledger/evaluator | Implemented | One-axis matched evaluation and champion lineage; current reusable runner is narrow. |
| M5 task exposure registry | Implemented | Content-blind coverage for declared gateway lanes; direct loopback calls and incomplete history remain explicit. |
| M5 capability ledger and deterministic verifiers | Implemented | Sole node/model/task capability truth; unverified evidence cannot be promoted by Hugin. |
| M5 organic judge and delegate policy | Shadow | Must remain non-authoritative until representative human calibration and policy versioning pass. |
| Product rating, candidate approval, verifier approval, change deployment | Manual | Human-reviewed by design in v1. |
| Durable all-outcome registry and candidate packager | Future | Required to connect ordinary failures/successes to experiments. |
| Verified Hugin-experiment import and guarded route reload | Future | Required to turn reviewed evidence into operational micro-routing. |
| Model-weight training | Future, outside v1 | Requires the separate gates in ADR-006. |

## What a trustworthy observation requires

The required fields and owner are normative in
[LearningTaskContract v1](learning-task-contract.md). In summary, a decision-driving observation
must bind:

- one stable task/source instance and canonical task taxonomy version;
- the raw task fingerprint, separately from the rendered model prompt fingerprint;
- exact execution attempt, input/output/repository references and hashes;
- effective runtime, provider, model artifact/config and sampling identity;
- prompt, harness, verifier/rubric, tool-policy and routing-policy versions;
- execution, repository, publication, product, and capability outcomes without collapsing them;
- failure/correction/successor and authenticated reviewer provenance; and
- sensitivity, allowed uses, retention/erasure, and exposure coverage.

A missing field remains missing. An inference, successful exit, changed file, model self-report, or
uncalibrated judge does not fill an owner-controlled product or capability verdict.

## Evaluation and improvement rules

### Deterministic and human evidence first

Use deterministic verifiers where a bounded task has a real oracle. Human product review provides
the highest-value correction signal. Store a governed correction/successor reference, not merely a
score. LLM judges are advisory until a representative, versioned human calibration set clears the
predeclared reliability gate; policy changes append/regrade rather than rewrite history.

### One causal axis

An experiment changes one semantic axis: route/roster, prompt, harness, tool policy, or another
predeclared configuration field. Every arm binds immutable configuration and corpus fingerprints.
Matched pairs, independent verification, product coverage, and declared correctness/cost/latency/
human-rescue guards determine the disposition.

### Negative results are learning, not improvement

A challenger that loses leaves the champion unchanged and records the dominant failure plus next
hypothesis. That improves knowledge but not the production baseline. Documentation must not count a
rejected challenger as a deployed improvement.

### Promotion is reviewed and reversible

`promotion-ready` is an evidence state. The owning repository's human operator applies the exact
reviewed prompt/harness/route/roster/config reference, advances the champion, observes the declared
window, and retains a rollback. Neither Hugin nor `gille-inference` may silently deploy a candidate
in v1.

## Roadmap to a closed loop

| Order | Owning repo | Deliverable | Exit evidence |
|---:|---|---|---|
| 1 | Grimnir + both reviewers | Adopt v1 seam and immutable shared fixtures | Hugin and `gille-inference` owner reviews recorded; both consumer suites accept the same fixture. |
| 2 | Hugin + `gille-inference` | Canonical raw-task/exposure identity and taxonomy parity | Real Hugin serialization is captured by M5 and found by Hugin lookup; rendered/raw mismatch test passes. |
| 3 | Hugin | Concurrency-safe, actionable receipts and durable all-outcome registry | Parallel reviews are preserved; failures/no-ops/publication failures and late labels stay joinable. |
| 4 | Hugin | Independent candidate packager | A governed production candidate is rechecked, frozen, independently verified, and imported into a one-axis experiment. |
| 5 | `gille-inference` | Versioned evidence identity and verified experiment import | Exact served-model/config evidence joins the task and only qualified evidence affects capability state. |
| 6 | `gille-inference` | Reviewed routing-table lifecycle | Generate, diff, approve, deploy/reload, canary, and rollback are demonstrated without silent promotion. |
| 7 | Hugin | Read-only next-experiment proposals | Proposals cite evidence and require human approval; they do not mutate prompts/routes/config. |

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
