# LearningTaskContract v1

> **Status:** proposed v1; effective only after recorded Hugin and `gille-inference` owner reviews.
> **Contract id:** `grimnir.learning-task/v1`.
> **Machine schema:** [`learning-task-contract-v1.schema.json`](learning-task-contract-v1.schema.json).
> **Review gate:** Hugin owner — pending; `gille-inference` owner — pending.

## Purpose and boundary

This contract is the evidence seam between Hugin tasks and M5 gateway inference. It lets a consumer
join task, execution, exposure, capability, experiment, and late human-review facts without making
either repository the owner of the other's truth. It is an export projection, not a replacement for
Hugin's task/result, Quality Receipt, or experiment stores, nor for `gille-inference` exposure,
owner-log, code-loop, capability, and routing stores.

The seam is content-governed. It carries opaque identifiers, exact hashes, classifications, and
owner-controlled references. Hashes are content-derived metadata, not anonymization. A consumer
MUST NOT dereference content unless the authenticated principal, allowed use, sensitivity ceiling,
retention, and erasure state permit it.

Normative terms **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used as in RFC 2119.

## Record model

The JSON Schema is normative for types, object shape, closed enums, and per-kind fields. A native
representation is conforming only when its projection validates losslessly. Active records use
`lifecycle_state: "active"`; content removal uses the deliberately smaller
`content-removed-tombstone` projection.

| `record_kind` | Active section | Producer | Origin |
|---|---|---|---|
| `task-outcome` | `outcomes` | Hugin | Hugin |
| `inference-exposure` | `exposure` | `gille-inference` | Hugin or direct gateway |
| `capability-evidence` | `capability` | `gille-inference` | Hugin or direct gateway |
| `experiment-observation` | `experiment` | Hugin | Hugin |
| `quality-receipt` | `quality_receipt` | Hugin | Hugin |
| `experiment-product-rating` | `experiment_product_rating` | Hugin | Hugin |

Late product judgments are immutable record kinds. `task-outcome` MUST NOT acquire a
`product_quality` scalar and `experiment-observation` MUST NOT acquire a `product_outcome` scalar.
This prevents a review arriving later from rewriting an execution or experiment observation.

Unknown is never bare `null`. Where the schema permits absence, it uses:

```json
{ "value": null, "unknown_reason": "not-applicable | not-observed | legacy | producer-error | redacted | erased | expired | not-admitted | policy-unavailable", "detail": "optional" }
```

Unknown fields do not erase known owner stamps and do not make a record evaluation-eligible.

### Immutable review records and summaries

`quality-receipt` preserves Hugin's native Quality Receipt identity and vocabulary: `qr-…`
`receipt_id`, native schema version, task/attempt binding, rating, disposition, retries, reviewer,
rubric, reason digest, and task/result/repository hashes. `experiment-product-rating` binds an
`epr-…` rating to the immutable experiment-observation `record_id`, experiment/run, exact
configuration fingerprint, reviewer, rubric, reason digest, and review time.

Multiple receipts or ratings MAY target one binding. They are different evidence, not conflicting
replays, provided their own record and native receipt/rating ids are unique. Consumers derive a
summary per exact binding and rubric version as follows:

1. no applicable record is `unrated`;
2. one Quality Receipt yields its full `(rating, disposition)` tuple; one experiment rating yields
   its `product_outcome`;
3. multiple records with the same full result yield that result plus every contributing immutable id;
4. disagreement in either Quality Receipt rating or disposition (or in experiment product outcome)
   is `conflicted` and cannot support admission or promotion; and
5. a new rubric/version is a separate cohort. Newest-wins and destructive re-rating are forbidden.

The derived summary is a query result, not a scalar written back into the older record.

## Identity, provenance, and integrity

### Task and source

The origin owns `task.instance_id`, the full source tuple, and task-type assignment. The source tuple
is `component`, `system`, `id`, `created_at`, `accepted_at`, and the source `principal`
(`id`, authentication method, and owner/service scope). `task.origin_component` MUST equal
`task.source.component`; creation precedes acceptance.

A legacy source MAY use a qualified unknown principal rather than fabricate authentication. Such a
record MUST use `policy-unavailable`, permits no use, and is evaluation-ineligible. Source principal
and authenticated transport caller are separate identities: the former identifies who originated
the task; the latter proves which service called the gateway.

`gille-inference` owns the closed task taxonomy id/version. Both origins hash the canonical raw
task bytes using exactly `trim-utf8-sha256-v1`: apply JavaScript-compatible `String.trim()` to the
raw UTF-8 text and SHA-256 the resulting UTF-8 bytes. There is no Unicode normalization, JSON
rewriting, prompt rendering, or chat-template application. Multi-turn traffic emits one observed
event per user turn using that turn's raw bytes.

### Three prompt stages and configuration provenance

The three prompt identities are separate facts:

| Field | Bytes identified | Owner |
|---|---|---|
| `execution.prompt_identity.hugin_envelope` | Hugin task envelope after Hugin context/system wrapping | Hugin |
| `gateway_canonical_envelope` | Canonical gateway request after gateway orchestration | `gille-inference` |
| `runtime_chat_template_render` | Exact bytes after the runtime chat template | Effective serving owner |

For direct gateway traffic, only the Hugin stage is `not-applicable`; gateway and runtime stages
remain required. Joined consumers MUST NOT collapse any two stages even if their digests match.

`execution.origin_config` binds the origin prompt, harness, and tool policy as versioned identities
with config digests. `execution.effective_gateway_config` separately binds the gateway harness and
tool policy after defaults and policy application. Effective serving uses `runtime_id:
"llama-swap"` for the current M5 path and records provider/model plus:

- an artifact-manifest digest;
- an effective runtime-config digest; and
- an effective sampling digest after defaults and clamps.

These use JCS RFC 8785 canonical JSON, UTF-8, SHA-256, an explicit source type, and source schema
version. Labels, aliases, requested values, or a model name alone are not reproducible provenance.
Fixtures calculate their raw and prompt hashes from declared source strings; they are not decorative
64-character constants.

Repository base/head commit ids are symmetric lowercase hexadecimal strings of 40–64 characters or
a qualified unknown. A correction reference MUST name a correction artifact in the same record.
Reviewer identity and review time are known together or unknown together. All clocks use RFC 3339
UTC; source creation ≤ acceptance ≤ execution start ≤ execution end ≤ `recorded_at`. Exposure,
review, rating, policy, and erasure clocks have their analogous bounded ordering.

## Executable Hugin ↔ M5 transport join

The Hugin-owned macro decision includes an explicit `target` and `service`. That makes transport a
closed state machine instead of inferring M5 use from whichever fields happen to exist:

| `transport.state` | Macro/origin | Required evidence |
|---|---|---|
| `not-m5` | Hugin macro target is not M5 | Hugin stamp and gateway echo are `not-applicable`; gateway envelope/micro/config are also `not-applicable`. |
| `m5-not-admitted` | Hugin macro target is M5 | Hugin request stamp is known; echo is absent with `not-admitted`, `transport-auth-failed`, or `producer-error`; gateway/runtime/micro/serving facts carry that same missing-echo reason. |
| `m5-admitted` | Hugin macro target is M5 | Known Hugin stamp and exact authenticated gateway echo. |
| `direct-gateway` | Direct `gille-inference` origin | Hugin-only stamp, envelope, and macro fields are `not-applicable`; gateway execution facts are known. |

Thus a non-M5 attempt and an M5 admission/authentication failure remain valid Hugin task outcomes in
the capture/join denominators. Neither fabricates a gateway observation or model execution.

An admitted joined inference uses this stamp-and-echo handshake:

1. Hugin creates `transport.hugin_request_stamp` before dispatch. It contains task instance,
   attempt, client, idempotency key, request id, the full Hugin-owned source tuple, task type, raw
   fingerprint, Hugin envelope, origin config, macro decision, retry identity, and
   `contract_request`. The request names the exact contract major, schema revision, and four required
   features; it MUST match the record and the gateway's returned capability set.
2. The gateway authenticates the actual caller independently. It MUST bind that principal to the
   request/idempotency/task stamp's `expected_transport_principal_id` and emit
   `principal_binding_digest`; a body-supplied principal is not authentication. For the current path
   this authenticated caller is the Hugin service principal, not necessarily the original source
   principal. The binding digest is SHA-256 over JCS canonical JSON containing
   `authenticated_principal_id`, `expected_transport_principal_id`, `client_id`, `idempotency_key`,
   `request_id`, `task_instance_id`, `attempt_id`, and the complete `contract_request`, with version
   `gateway-principal-request-binding-jcs-v1`.
3. Before model execution, the gateway verifies supported contract major/revision and the four
   advertised features, assigns gateway request/admission ids, and echoes the complete Hugin stamp.
4. Hugin accepts gateway-owned render/route/serving facts only when the echo is byte-for-byte equal
   to its stamp and the authenticated caller equals the expected transport service principal. The
   original source principal remains unchanged in the echoed source tuple. A mismatch or
   substitution is rejected and recorded as a join failure.

Retry lifecycle is exact:

| Event | Task/attempt/idempotency/request | Counters | Model run |
|---|---|---|---|
| Transient request transport retry | all reused | increment `transport_attempt` | at most the original run under gateway idempotency |
| Deliberate new model execution | task reused; new attempt, idempotency key, and request id | increment `model_execution_ordinal` | yes |
| Contract-record delivery retry | stamp, echo, task, attempt, and model ordinal reused | increment only `transport.record_delivery_attempt` | no |

An idempotency key MUST NOT span different task/attempt/model-execution identities. A record delivery
retry never buys another model run.

Joined records compare exact task/execution plus transport state, Hugin stamp, and gateway echo.
`record_delivery_attempt` is producer-owned delivery telemetry and MAY differ between Hugin and
`gille-inference`; it is not part of shared join identity or model-run idempotency.

Direct gateway records set both Hugin-only stamp/echo fields to qualified `not-applicable`; they do
not invent a Hugin task. A Hugin-origin admitted gateway record cannot use unknown stamp or echo.

## Exposure facts

`inference-exposure` has two mutually exclusive projections:

- `observed-event` is an event actually recorded by one lane, with immutable `event_key`, exact raw
  fingerprint version, lane, and ordered first/last-seen clocks.
- `negative-coverage-query` is a later query result, with its own `lookup_id`, `coverage_epoch_id`,
  query time, exact queried raw fingerprint, task attempt, relevant-task time, and bounded window.

A negative result is valid only when coverage is complete and includes exactly these six lanes:
`chat`, `mcp-ask`, `delegate`, `delegate-disagreement`, `delegate-shadow`, and `code-loop`. The
relevant task time MUST fall inside the window, the window MUST end no later than the query, and the
query MUST precede record creation. An observed event is never rewritten into a negative lookup.

This is exact-hash freshness evidence, not contamination proof. It cannot detect Unicode-normalized
equivalents, paraphrases, translated prompts, or semantic contamination. Raw loopback traffic sent
directly to llama-swap is outside the six authenticated lanes; it must be captured through a
declared authenticated lane or coverage for the affected holdout window is incomplete and the
candidate is excluded. A registry restart or lane-set change mints a new `coverage_epoch_id`; a
negative query cannot bridge epochs to imply uninterrupted history.

Monthly reporting includes coverage-epoch restarts, incomplete-window duration, raw-loopback
detections, eligible candidates, candidates excluded as `exposure-incomplete`, and the resulting
candidate-starvation rate. These measurements bound what was observed; they MUST NOT be described as
proof that semantic contamination did not occur.

## Outcomes, experiments, and capability admission

Hugin owns execution/repository/publication outcome and the closed operational failure mode.
Experiment observations contain mechanical verification and failure only; late product rating is a
separate immutable record.

Outcome/failure pairs are closed: completed task execution uses `not-applicable`; timeout and
cancelled use their matching modes; failed execution uses an operational/repository/publication/
delivery failure; and infrastructure error uses infrastructure, gateway non-admission, or transport
authentication failure. Experiment `pass` uses `not-applicable`; every non-pass has a failure.

`gille-inference` alone owns capability evidence and admission. Evidence is `admissible` only when
the verifier is independent and is deterministic, human, or a calibrated judge carrying a
calibration evidence id. A `pass` uses admission basis `full-pass`; a `partial` can be admissible
only when the versioned policy epoch explicitly yields `policy-qualified-partial`. All other
partials are inadmissible. An advisory judge is always `none-shadow`. Inadmissible evidence uses
basis `none` and cannot use routing effect `admit`. A later policy does not reinterpret old evidence.
Capability pass/partial uses `not-applicable` failure; fail/error/unverified requires a non-NA mode,
and `unverified` pairs specifically with `unverified`. Admissible evidence uses routing effect
`admit`; all other routing effects are inadmissible.

Product acceptance is not capability evidence. Hugin cannot promote a route by emitting a
verdict-like task or rating record; `gille-inference` imports qualified evidence through its own
ledger contract.

## Governance

Governance has exactly two states:

- `complete` requires an authenticated, owner-approved policy manifest; one exact typed policy for
  every source, raw derivative, known prompt stage, artifact, repository diff/file list, quality
  binding, and rating reason; and a mechanically derived effective policy.
- `policy-unavailable` contains no policies, allows no use, and is never evaluation-eligible.

The exact typed subject set prevents an unrelated policy from masking a missing derivative. Each
policy preserves the direct content owner. The effective policy is the strictest sensitivity and
erasure state, the intersection of allowed uses, earliest safe expiry, and the complete subject-ref
set. `expires_at: not-applicable` means an explicit owner policy with no expiry; it is not unresolved
and does not by itself block evaluation. An unresolved, legacy, redacted, or producer-error expiry
requires the whole governance projection to be `policy-unavailable` and evaluation-ineligible. A
known expiry must be later than record creation. Erased/expired active content MUST use a tombstone.

`governance.effective.evaluation_eligible` means governance eligibility at emission time only. It
does not make a full candidate eligible. Candidate selection re-evaluates expiry against an explicit
decision timestamp and separately requires complete, reproducible task/execution/prompt/route/
serving/verifier/exposure provenance. Unknown or non-admitted execution provenance therefore remains
candidate-ineligible even when content policy allows evaluation.

For Hugin-origin work, Hugin is the enforcement owner and must supply the authenticated manifest.
For direct traffic, `gille-inference` enforces owner/service scope before capture; it MUST NOT claim
Hugin enforcement. Direct-owner policy lookup has an operational SLO of 99% within 250 ms per
complete UTC month. Timeout or lookup failure emits `policy-unavailable`, never guessed defaults.

## Erasure and expiry protocol

Effective removal deletes the content-bearing projection and all content-keyed copies before a
replacement tombstone is valid. The active record and tombstone MUST NOT coexist in a conforming
dataset. A completed tombstone records an authorized request and final readback receipts for these
exact core stores:

1. Hugin task store;
2. Hugin workspace/log/result artifacts;
3. Munin;
4. `gille-inference` ledger;
5. owner log;
6. exposure registry; and
7. code-loop store.

Before deletion, the producer also creates an opaque artifact-inventory id and expected receipt
count. `artifact_stores` then contains one final receipt with a unique opaque `inventory_entry_id`
for every referenced Mimir,
repository-workspace, or other external artifact store. The tombstone retains the opaque inventory
identity/count and receipts, never the erased locator or content-derived inventory.

Each store is `deleted` or `not-applicable`; `pending` is deliberately invalid. Backup expiry uses
the exact order `requested_at ≤ deadline ≤ verified_at ≤ effective_at`; it is not merely a future
promise. Until every applicable store and backup obligation is complete,
the erasure request remains operationally pending outside the contract and no success tombstone is
emitted.

The tombstone keeps only an opaque new id, producer/kind, recorded/effective clocks, opaque receipt
and superseded id, completed protocol, and optional producer-owned aggregate counter audit.
Counters are preservation-only and only for closed periods. The preserved monthly denominator
survives in the aggregate, not through retained task, source, model, prompt, route, artifact,
classification, locator, review, lineage, or extension data. Tombstone uniqueness and active-record
non-coexistence are scoped by producer plus superseded id.

## Normative ownership

The schema's `x-grimnir-field-owners` map is normative. Important decisions are:

| Fact or decision | Sole owner |
|---|---|
| Contract vocabulary, schema revision, compatibility | Grimnir |
| Hugin-origin task/source, Hugin envelope, origin config, macro decision, lifecycle/repo outcome | Hugin |
| Direct request identity, gateway/runtime prompt stages, effective serving/config, exposure, micro route | `gille-inference` |
| Task taxonomy | `gille-inference` |
| Quality Receipt, experiment design/observation/product rating, correction/successor | Hugin |
| Capability evidence, admission, routing-table generation | `gille-inference` |
| Classification/use/retention/erasure | Direct subject content owner; producer enforces and copies |
| Applying a reviewed prompt/harness/route/roster/config | Human operator of the owning repository |

Storage does not transfer authority. Extensions are accepted only beneath
`extensions.<producer.component>` and cannot alter v1 decisions.

## Conflict keys and append-only behavior

The schema's `x-grimnir-conflict-keys` extension is normative:

| Scope | Key |
|---|---|
| Every record | `(producer.component, record_id)` |
| Task outcome | `(task.origin_component, task.instance_id, execution.attempt_id)` |
| Observed exposure | `(exposure.kind, exposure.event_key)` |
| Negative exposure query | `(exposure.kind, exposure.lookup_id)` |
| Capability evidence | `capability.evidence_id` |
| Experiment observation | `(experiment.experiment_id, experiment.run_id)` |
| Quality receipt | `quality_receipt.receipt_id` |
| Experiment product rating | `experiment_product_rating.rating_id` |

Identical replay is idempotent. Different canonical JSON at the same key fails; there is no
last-write-wins. Corrections and regrading append new records/lineage. Effective erasure/expiry is
the only removal exception.

## Compatibility and rollout

An unknown contract major fails closed. Semantic change, field reuse, privacy weakening, or enum
reinterpretation requires `v2` and a parallel migration. `schema_revision` may add optional
producer-namespaced data without changing existing decisions. Both sides pin the canonical schema
and fixtures; two locally invented mocks do not prove compatibility.

The rollout is capability-negotiated and must follow this matrix:

| Phase | Hugin write | Gateway read | Gateway write | Hugin read | Minimum duration and gate | Rollback |
|---|---|---|---|---|---|---|
| 0 baseline | legacy only | legacy | legacy | legacy | Record seven baseline days of request, admission, mismatch, latency, and delivery-retry rates | no change |
| 1 expand readers | legacy | legacy + v1 shadow parse | legacy + shadow v1 echo | legacy + v1 shadow parse | ≥7 complete days; ≥99.9% parse, zero principal substitution accepted, p95 admission overhead <10 ms | disable shadow parse/echo |
| 2 dual write | legacy + v1 stamp when capability advertised | dual read, v1 verify | legacy + v1 echo | dual read/compare | ≥7 complete days and ≥100 real eligible attempts, whichever is later; ≥99.5% exact joins, zero conflict-key mismatch | stop v1 emission, retain dual readers |
| 3 v1 preferred | v1, legacy fallback only for unadvertised peer | dual read | v1 | v1 + legacy fallback | ≥14 complete days; ≥99.9% valid joins, zero auth substitution, <0.1% schema reject, no model-run increase from delivery retry | restore phase 2 writes |
| 4 retire legacy | v1 only | v1 only | v1 only | v1 only | both owner approvals plus 30 complete green days and no legacy traffic for 14 days | redeploy last dual-reader release; do not reinterpret stored v1 |

Capability advertisement is checked before v1 send and includes contract major, schema revision, and
`hugin-request-stamp-v1`, `gateway-echo-v1`, `three-stage-prompt-provenance-v1`, and
`reproducible-serving-digests-v1`. Absence before phase 4 selects the declared legacy path; partial
advertisement fails closed and cannot silently strip fields. Dashboards separately report legacy,
shadow, dual, v1, fallback, rejection, and rollback populations.

## Conformance fixtures and required tests

The canonical schema ships with dependency-free positive and adversarial fixtures under
`tests/fixtures/learning-task-contract/`. CI uses the dependency-free semantic validator. An
optional `jsonschema` Draft 2020-12 check is also supplied for environments that explicitly provide
that dependency; repository CI does not download undeclared packages.

Producer and consumer suites MUST prove:

1. the same Hugin task/attempt has exact `task`, `execution`, and `transport` projections;
2. stamp/echo and authenticated-principal substitution checks fail closed;
3. direct and joined observed events plus a separate six-lane negative query validate;
4. canonical raw/prompt fixture hashes are computed, and effective model/config/sampling digests
   use the declared canonicalization;
5. policy-unavailable, typed complete policy, expiry, erasure, and backup/store receipts fail closed;
6. multiple immutable quality receipts/experiment ratings validate and conflicting summaries do
   not promote;
7. capability admission cannot be driven by self, advisory, uncalibrated, failed, or inadmissible
   evidence; and
8. unknown fields, bad clocks/hashes/commit ids, cross-plane identity mismatch, conflict-key reuse,
   and active+tombstone coexistence fail.

## Adoption and measurable meaning of continuous

The contract describes the target seam, not current deployment. Existing Hugin task/repository,
Quality Receipt, experiment, M5 exposure, capability, verifier, and guarded routing mechanisms are
implemented but do not yet emit this complete projection. Organic judge/delegate evidence is
shadow. Product rating, promotion, deployment, and rollback remain manual. Durable all-outcome
candidate packaging, verified experiment import, and guarded route reload remain future.

“Continuous” uses disjoint complete UTC calendar months with 24-hour close grace:

An **eligible Hugin attempt** is every production Hugin `execution.attempt_id` whose `started_at`
falls in the month. Failed, timed-out, cancelled-after-start, private, no-op, publication-failed,
erased, and unrated attempts remain in the capture denominator. Retries that deliberately start a
new model execution are separate attempts. The only exclusions are `synthetic-test`, declared before
dispatch, and `pre-v1-migration`, started inside the documented compatibility window. Rejection
before Hugin acceptance/execution is not an attempt.

An **eligible M5-backed join** is an eligible Hugin attempt whose Hugin-owned macro decision selected
M5 before execution. Gateway non-admission, authentication failure, missing echo, and schema failure
remain denominator failures. Whether the gateway produced a convenient record cannot redefine the
denominator.

An **eligible direct-owner request** is every authenticated, non-synthetic direct chat, MCP ask,
delegate, delegate-disagreement, delegate-shadow, or code-loop user turn accepted by
`gille-inference` in the month. Policy lookup failure, denial, model failure, and missing exposure
remain in this capture denominator; only a request rejected before authentication/acceptance and
documented `pre-v1-migration` traffic are excluded. This denominator never inflates Hugin capture or
join coverage.

An **eligible evaluation candidate** is a captured task/outcome with evaluation allowed, active
retention, complete just-in-time exposure evidence, a reproducible independent verifier, and unique
source lineage/raw fingerprint. Candidate exclusions are exactly `governance-denied`,
`erased-or-expired`, `exposure-incomplete`, `unreproducible`, and `duplicate-lineage`.

Every missing, late, or rejected capture/join has one persisted code. `not-m5-routed` and the five
candidate exclusions explain boundaries. `gateway-not-admitted`, `transport-auth-failed`,
`policy-unavailable`, `producer-error`, `consumer-error`, `schema-rejected`, `join-mismatch`, and
`late-over-24h` are failures and cannot become exclusions. Unclassified omissions fail the metric.

| Claim | Owner and gate |
|---|---|
| Continuous Hugin capture | Hugin: at least 95% of eligible attempts emit a valid outcome within 24 hours; every remainder has one failure code. |
| Continuous M5 join | Grimnir validator: at least 95% of Hugin attempts macro-routed to M5 join within 24 hours, with zero unresolved identity/conflict mismatch. |
| Continuous direct-M5 capture | `gille-inference`: at least 95% of eligible direct-owner requests emit a valid observed-event exposure within 24 hours; every remainder has one failure code. Report this separately from Hugin join coverage. |
| Continuous evaluation | Hugin: when at least ten unique eligible candidates exist, one frozen batch completes independent verification and a distinct one-axis experiment reaches reviewed disposition. |
| Continuous learning | Grimnir review: the preceding gates pass for three months with different experiments and durable accepted or rejected knowledge. |
| Continuously improving baseline | Owning operator: across those months, at least one reviewed change is deployed, clears declared product/non-regression gates, and has a tested rollback. |

Gateway non-admission, producer/consumer error, schema rejection, join mismatch, and records later
than 24 hours are failures, not exclusions. Governance denial, effective erasure/expiry, incomplete
exposure, unreproducible evidence, and duplicate lineage exclude an evaluation candidate but not an
eligible capture attempt. If every challenger loses, the system learned; the baseline did not
improve.
