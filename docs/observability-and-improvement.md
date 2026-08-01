# Grimnir — Observability and the Self-Improving Loop

> Architectural status and roadmap for evidence-driven task delegation.
> Last updated: 2026-07-26.

## Purpose

Grimnir's self-improvement goal is to learn, from governed evidence, which model, route, prompt,
harness, and tool policy produces useful outcomes for a bounded task. The normative cross-repository
join is [LearningTaskContract v1](learning-task-contract.md); the meaning of “improve models” is
settled by [ADR-006](adr-006-learning-improvement-scope.md).

This document replaces the older assumption that all components participated in one generic
`trace → score → reflection → few-shot/routing` pipeline. The core Hugin↔`gille-inference` loop is
implemented and has been exercised, while producer coverage, ground-truth breadth, and operating
cadence still have explicit maturity gaps.

## Telemetry strategy

Grimnir uses four deliberately separate record classes. A shared identifier can correlate them, but
storage or visualization does not transfer authority:

The operational-telemetry plane's record shape is normative in
[`operational-observability-contract.md`](operational-observability-contract.md): closed
observation states, authority-bound expected-inventory aggregation, consumer-owned freshness caps,
collector/exporter meta-slots, content-blind trace joins, and deny-by-default serialized
attributes live there rather than in Heimdall tickets or dashboards.

| Record class | Authoritative producer and facts | Aggregation and consumers | Current boundary |
|---|---|---|---|
| **Operational telemetry** | Each service owns its application health, latency, queue, throughput, and error facts; systemd owns unit lifecycle; Brokkr owns substrate observations. Consumers own collector freshness caps and collector/exporter meta-observation requirements. | Heimdall collects derived health time series and alerts for the operator. Skuld may consume an explicitly derived health summary, not raw logs or a new verdict. | Basic host/service/backup and Hugin task-health collection exists. Queue depth, Munin request rates, model-load timing, and cross-service throughput trends remain uneven or absent. |
| **Task and product evidence** | Hugin owns task/source identity, attempt lifecycle, execution/repository/publication outcomes, Quality Receipts, corrections, and macro-routing experiments. | Munin stores and exposes some Hugin records; Heimdall may render task status; governed evaluators, the autonomy controller, and the operator consume complete Hugin-owned facts. | The append-only all-outcome registry, native-v2 correction path, proposer, candidate packager, controlled experiments, and cadence tick are implemented. Product labels and certified intake coverage remain uneven across task surfaces. |
| **Capability evidence** | `gille-inference` owns gateway request/exposure identity, effective model/runtime configuration, verifier results, the capability ledger, and micro-routing. | The gateway ledger aggregates per-model capability facts. Hugin and the autonomy controller may consume only compatible, independently verified evidence through the LearningTaskContract seam. | Authenticated stamp/echo, exposure/accounting, experiment import, routing lifecycle, watchdog, calibration, and autonomy controller are implemented. Refreshed served-model evidence and final production-shaped reviewer evidence remain open. |
| **Consequential-mutation receipts** | The mutating component or authoritative external system owns intent, observed outcome, final-state reference, and reversal evidence. A future accepted Verdandi receipt may bind those references without replacing them. | The operator, incident review, and autonomous-action gate consume minimal receipts and source references. This is accountability, not health monitoring or model evaluation. | Reversal conventions and some component provenance exist, but Verdandi production is recovery-gated and its narrow receipt purpose remains proposed. Do not claim a live fleet-wide receipt path. |

### Purpose and data flow

| Purpose | Producer → aggregator/joiner → consumer | Rule |
|---|---|---|
| **Debug — what went wrong?** | Owning service/systemd/Hugin attempt record → owner-local logs or an on-demand correlation view → operator and owning-repo maintainer | Preserve exit status, duration, bounded diagnostic context, and last known activity at the source. A dashboard summary links back; it does not become the forensic authority. |
| **Monitor — is the system healthy?** | Service and Brokkr health signals → Heimdall → operator, alerts, and an explicitly bounded Skuld summary | Calculate uptime, rates, counts, percentiles, backlog, resource use, and staleness deterministically. Alert correctness and collection freshness are themselves monitored. |
| **Governed improvement — what should change?** | Hugin task/product facts plus `gille-inference` capability facts → versioned LearningTaskContract join/evaluator → autonomy controller, operator, and owning route/prompt/harness policy | A complete, governed, independently verified bundle may support an experiment and a mechanically gated proposal or adoption. The armed controller is at Tier 0, so it currently records proposals but auto-adopts nothing. Operational correlation alone never becomes a capability or product verdict. |
| **Accountability — what consequential mutation occurred and how is it reversed?** | Mutating authority plus authoritative readback → minimal receipt binding when implemented → operator, recovery tooling, and policy gate | Receipts reference action authority, observed effect, and reversal evidence; they do not ingest generic tool, session, or telemetry streams. |

**Structured calculation comes first.** Counters, rates, averages, percentiles, durations, threshold
comparisons, and joins are computed by deterministic code over typed records. An LLM may interpret
the resulting bounded summary and propose an investigation or experiment, but that interpretation is
advisory: it cannot fabricate missing facts, change a producer verdict, close an evidence gap, or
authorize a mutation. The retired Hugin daily journal-prose experiment is not an aggregation layer.

**Correlation is by reference, not payload replication.** Propagate opaque task, attempt, receipt,
and trace identifiers across allowed boundaries. Derived views do not copy prompts, outputs,
documents, or raw error payloads merely to make a join convenient. Keep sensitive diagnostics in
their authoritative store, expose the minimum bounded summary needed by the consumer, and remember
that a content hash is not anonymization. Classification, correction, erasure, and expiry follow
[the data lifecycle map](data-lifecycle.md); this strategy does not create another retention policy.

**No new generic observability service.** The system already has authoritative producers, Heimdall
for operational health aggregation, Munin for some task-record storage/discovery, the M5 capability
ledger, and narrowly scoped accountability work. The missing work is instrumentation, typed
contracts, correlation, trustworthy joins, retention enforcement, and consumers that act on the
result. Another database or prose-analysis daemon would duplicate storage while weakening ownership.

**Current gaps:** operational coverage is uneven; some desired metrics have no owning emitter;
Heimdall does not supply learning verdicts; certified external Codex/Pi producer rollout remains
incomplete under [#90](https://github.com/Magnus-Gille/grimnir/issues/90) and
`claude-config#11`; refreshed served-model identity (`gille-inference#11`) and reviewed
production-shaped ground truth (`gille-inference#13`) remain open; and the consequential-receipt
path is not live. The core Hugin↔gateway join is live, but uncovered task paths fail closed instead
of being counted as complete evidence. **Future work** stays in the owning repositories: services
add bounded emitters, Heimdall adds health collectors/views, external surfaces complete certified
adapters, the Tier-0 controller accumulates the required healthy-cycle record, and Verdandi remains
unavailable until its recovery and purpose gates are separately satisfied.

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
Hugin task + canonical raw-task identity
       |
       +--> execution/repository/publication outcome
       |             |
       |             +--> immutable Quality Receipt / correction
       |
       +--> authenticated request stamp <--> gateway echo
                         |
                         +--> M5 exposure + exact served-model identity
                         |
                         +--> capability evidence (verified or shadow)

joined, governed candidate
       --> independent verifier + frozen sample
       --> one-axis champion/challenger experiment
       --> mechanically gated reject, proposal, or adoption
       --> exact reversible change + canary/watchdog
       --> subsequent production evidence checks the result
```

The core path has completed one live human-approved routing adoption, and the autonomous controller
is armed on M5 at **Tier 0** with its kill switch off. Tier 0 proposes and records only; Tier 1
self-unlocks after the configured healthy-cycle predicate. This proves the Hugin↔gateway loop, not
universal fleet coverage: direct external surfaces, raw loopback, unsupported task types, and
missing/stale producer evidence remain uncovered and fail closed.

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
| Hugin task/outcome registry and managed-repository evidence | Implemented | Append-only attempts, outcomes, failures, publication recovery, corrections, and period closes are durable; successful completion is still not product quality. |
| Hugin Quality Receipts v1/v2 | Implemented | Concurrency-safe receipts preserve v1 artifacts and support native-v2 attempt/rubric/correction binding. Human review remains supported but is not required by the operating controller. |
| Hugin proposer, candidate packager, experiment store, and cadence | Implemented | Qualified candidates can enter frozen one-axis experiments; the reusable corpus and certified producer coverage are not universal. |
| M5 exposure registry and cross-owner accounting | Implemented; coverage partial | Declared gateway lanes and authenticated external receipt intake fail closed. Direct loopback and the still-incomplete Codex/Pi adapters under #90 remain outside complete coverage. |
| M5 capability ledger, verifiers, and experiment import | Implemented; ground truth partial | Capability truth and admissible Hugin imports are live. Served-model refresh (`gille-inference#11`) and reviewer adoption evidence (`gille-inference#13`) remain. |
| M5 organic-judge calibration | Implemented, mechanically gated | Verifier-anchored rolling calibration controls admissibility; stale or below-threshold evidence holds automatically and cannot affect routing. |
| Hugin↔M5 authenticated preflight/stamp/echo | Implemented and exercised | A live joint smoke passed the authenticated five-gate path. Unstamped or incompatible traffic fails closed rather than joining post hoc. |
| Immutable pipeline accounting | Implemented on both owners | Hugin and `gille-inference` own append-only registries, natural keys, retries, complete partitions, and fail-closed period closes. This does not prove every external task emitted a receipt. |
| Routing lifecycle, watchdog, and autonomy controller | Implemented; armed Tier 0 | Reviewed lifecycle, durable adoption, canary, auto-revert/quarantine, protected lanes, kill switch, and tier ladder are live. Tier 0 auto-adopts nothing while healthy-cycle evidence accumulates. |
| Model-weight training | Future, outside v1 | Requires the separate gates in ADR-006. |

## What a trustworthy observation requires

The required fields and owner are normative in
[LearningTaskContract v1](learning-task-contract.md). In summary, a decision-driving observation
must bind:

- one stable task/source instance, distinct transport principal/content owner, and canonical task taxonomy version;
- the typed exact pre-orchestration raw input/fingerprint plus Hugin envelope, gateway canonical
  envelope, and runtime chat-template render as distinct exact-byte identities;
- exact execution attempt, input/output/repository references and hashes;
- effective serving runtime, provider, model artifact manifest, effective runtime config, and
  post-default/post-clamp sampling digests with reproducible canonicalization;
- origin prompt/harness/tool config plus effective gateway harness/tool config and separate macro-
  and micro-routing policy/decision identities;
- execution, repository, publication, immutable late product review, and capability outcomes without
  collapsing them;
- failure/correction/successor and authenticated reviewer provenance; and
- an authenticated fresh preflight, Hugin request stamp, gateway echo, and ordered attempt/admission/model clocks for joined traffic;
- exact typed per-source/derivative governance or explicit policy-unavailable denial; and
- immutable source-document refs and owner/delegation attestations verified through a separately
  trusted validation context for every governed derivative;
- append-only pipeline accounting when no valid learning record exists; and
- a complete joined governance/provenance/exposure/verifier/quality/lineage bundle for evaluation
  admission; and
- the reduced content-removal tombstone only after all store readbacks, exact idempotent
  occurrence-month denominator-membership tokens from each counter owner, and backup expiry complete.

A missing field remains missing. An inference, successful exit, changed file, model self-report, or
uncalibrated judge does not fill an owner-controlled product or capability verdict.

## Evaluation and improvement rules

### Deterministic and anchored evidence first

Use deterministic verifiers where a bounded task has a real oracle. Human product review provides
valuable optional correction evidence, but it is not required by the operating loop. Store a
governed correction/successor reference, not merely a score. LLM judgments affect routing only while
the family-diverse adjudicator's rolling agreement with deterministic/verifier anchors clears the
versioned automatic calibration gate; otherwise they remain held. Capability admission additionally
requires an independent passing verifier and a versioned policy epoch; policy changes append/regrade
rather than rewrite history.

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

### Promotion is mechanical and reversible

The operating controller adopts only reversible route/roster/prompt/harness changes after every
admissibility, confidence, risk-budget, protected-lane, canary, and tier predicate passes. Every
adoption holds an exact rollback and enters a watchdog window with automatic revert/quarantine.
Today the controller is armed at Tier 0, so no proposal can auto-adopt until the Tier-1 healthy-cycle
predicate is satisfied. Software changes, protected-lane policy, and irreversible actions remain
owner-controlled; see [the autonomous-improvement design](autonomous-improvement-design.md).

ADR-008 now supplies the cross-domain supervision floor: mechanical promotion is only for an
explicitly covered, digest-bound class with a domain journal and a disarming recovery worker.
Heimdall is read-only and Verdandi is an optional receipt projection; neither can admit or actuate.
The historical “promotion-ready, then operator applies” records retain their provenance: they remain
the required posture outside ADR-008's seven future armed classes and while W0 is disarmed.

## Delivered core loop and remaining maturity

| Capability | State | Remaining boundary |
|---|---|---|
| LearningTaskContract seam, canonical identity, authenticated stamp/echo | Implemented and live-smoked | Compatibility and missing evidence still fail closed; this is not proof of every producer path. |
| Hugin receipts, all-outcome registry, corrections, candidate packaging, experiments | Implemented | Product-review and task-type breadth depend on available verifier/label evidence. |
| Gateway exposure/accounting, capability import, routing lifecycle | Implemented and exercised | Exact served-model refresh and final ground-truth reviewer work remain under `gille-inference#11/#13`. |
| Experiment/sampling cadence and autonomy controller | Implemented and armed at Tier 0 | Tier 1 waits for the configured healthy-cycle record; later tiers require their own operating evidence. |
| External Codex App/CLI and Pi producers | Partial | Hugin/gateway intake exists, but installed/certified adapters remain open under #90 and `claude-config#11`. |
| Consequential-mutation receipts | Future/recovery-gated | Verdandi cannot be claimed live until its separate recovery and purpose gates pass. |

The core loop is closed and exercised, and the autonomous controller is armed. “Continuous” remains
a measured coverage/cadence claim: incomplete producer epochs, insufficient eligible candidates,
ground-truth gaps, or failed tier predicates are reported as such rather than promoted into evidence
of continuous improvement.

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
7. **Mechanical, reversible operating promotion.** The tiered controller may adopt only after every
   proof and rollback gate passes; Tier 0 currently auto-adopts nothing. Code, protected lanes, and
   irreversible actions remain owner-controlled.
8. **No hidden model training.** Evaluation/routing data is not a training dataset; ADR-006 governs
   any future exception.
