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
| `pipeline-accounting` | `pipeline_accounting` | Counter/event owner | Hugin or `gille-inference` |

Late product judgments are immutable record kinds. `task-outcome` MUST NOT acquire a
`product_quality` scalar and `experiment-observation` MUST NOT acquire a `product_outcome` scalar.
This prevents a review arriving later from rewriting an execution or experiment observation.

Unknown is never bare `null`. Where the schema permits absence, it uses:

```json
{ "value": null, "unknown_reason": "not-applicable | not-observed | legacy | producer-error | redacted | erased | expired | not-admitted | policy-unavailable", "detail": "optional" }
```

Unknown fields do not erase known owner stamps and do not make a record evaluation-eligible.

### Immutable review records and summaries

`quality-receipt` is a future `learning-quality-normalized/v2` projection over an immutable native
Hugin receipt artifact. The native v1 artifact is preserved exactly: content-derived `receiptId`,
`schemaVersion: 1`, task id, rating, **text** `ratingReason`, verification outcome, optional
`retriesCount`, rating clock, reviewer, binding attestation, and task/result/repository hashes.
Native v1 does **not** contain attempt or rubric fields. The normalized projection adds explicit
attempt/rubric facts and a reproducible reason digest; those fields are derived bridge facts, never
misrepresented as native v1 fields. A missing or invalid native artifact fails closed.
`experiment-product-rating` binds an
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

A quality correction uses a **new** future native v2 receipt id, explicitly names the predecessor
native receipt, retains an exact `quality-correction-group-jcs-v1` key over
task/attempt/reviewer/rubric/binding, and targets the predecessor contract record. It never reuses a
content-derived v1 receipt id. Current Hugin v1 deliberately rejects a second verdict from the same
reviewer for the same binding, so correction emission is a future v2 adoption dependency, not a
current native capability. Consumers collapse each valid correction group to its unique
unsuperseded leaf, then compare independent reviewer groups. Independent receipt ids remain separate
and may conflict.

The derived summary is a query result, not a scalar written back into the older record.

`pipeline-accounting` is the immutable denominator and delivery ledger. It carries only opaque
task/attempt/request/record identities, closed stage/disposition/failure codes, and one event—not
raw task, prompt, result, or artifact content. It exists precisely when a missing, rejected, or
late learning record cannot exist. Mutable counters are derived from these events and immutable
period-close snapshots; they never live inside evidence records.

## Identity, provenance, and integrity

### Task and source

The origin owns `task.instance_id`, the full source tuple, and task-type assignment. The source tuple
is `component`, `system`, `id`, `created_at`, `accepted_at`, the source transport `principal`
(`id`, authentication method, and owner/service scope), and a separate `content_owner`
(`id` and authenticated/delegated authority). `task.origin_component` MUST equal
`task.source.component`; creation precedes acceptance.

A legacy source MAY use a qualified unknown principal rather than fabricate authentication. Such a
record MUST use `policy-unavailable`, permits no use, and is evaluation-ineligible. Source transport
principal, content owner, and authenticated gateway caller are three separate identities: service
authentication proves who transported bytes, never who authorized their evaluation.

`gille-inference` owns the closed task taxonomy id/version. Every task binds a typed `raw-input`
source document containing the exact accepted UTF-8 text. For Hugin this is the parsed logical
prompt **before** injected context, system instructions, or Task wrapping; for direct traffic it is
the accepted user turn **before** gateway orchestration. Both origins hash that text using exactly
`trim-utf8-sha256-v1`: apply JavaScript-compatible `String.trim()` and SHA-256 the resulting UTF-8
bytes. There is no Unicode normalization, JSON rewriting, prompt rendering, or chat-template
application. Joined gateway exposure copies the stamped fingerprint. Multi-turn traffic emits one
observed event per user turn using that turn's raw bytes. The shared executable
`raw-fingerprint-vectors.json` fixture recomputes ASCII and non-normalized Unicode examples.

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
tool policy after defaults and policy application. Effective serving records runtime/provider/model
plus:

- an artifact-manifest digest;
- an effective runtime-config digest; and
- an effective sampling digest after defaults and clamps.

Every reproducibility claim binds an immutable `source_ref`, closed `source_type`, source schema
version, JCS RFC 8785 canonical JSON object, UTF-8, and SHA-256. Every prompt-stage source contains
its exact ordered UTF-8 text, byte length, byte SHA-256, task binding, and ordered immutable input
source refs. The validator mechanically checks those inputs against raw input; prior prompt stage;
origin/gateway config component, kind, id, and version; and artifact/runtime/sampling model
identities. Labels such as `hugin-agent:v4`, `task:raw`, or a template alias alone are invalid.
The executable `source-documents.json` fixture contains typed source documents for all three prompt stages; origin
prompt/harness/tool policy; effective gateway harness/tool policy; capability policy; experiment
and rubric configs; artifact manifest; effective runtime config; and final sampling after defaults
and clamps. All admissible examples are conspicuously `fixture_only` and use synthetic
`fixture-model-v1` identities; they make no claim about current Mellum, `/v1/chat`, delegate, LM
Studio, context-window, artifact, or sampling values. A deployed example is admissible only when
captured exactly at its origin. Mutation tests recompute the digest and fail when any source object
changes. The dependency-free canonicalizer is restricted
to I-JSON values, rejects lone Unicode surrogates and non-finite/non-JSON values, uses ECMAScript
number serialization and UTF-16 property ordering, and is checked against the RFC 8785 sample plus
non-ASCII, numeric-boundary, exponent, and negative-zero vectors.

Repository base/head commit ids are symmetric lowercase hexadecimal strings of 40–64 characters or
a qualified unknown. A correction reference MUST name a correction artifact in the same record.
Reviewer identity and review time are known together or unknown together. All clocks use RFC 3339
UTC with zero to three fractional digits; higher precision fails closed so every comparison is exact
at the declared millisecond precision. `execution.started_at`/`ended_at` are the Hugin or direct task-attempt clocks, while
`model_started_at`/`model_ended_at` are runtime clocks or one shared qualified reason when no model
ran. Admitted M5 ordering is source creation ≤ acceptance ≤ attempt start ≤ **request stamp** ≤
gateway admission ≤ model start ≤ model end ≤ attempt end ≤ `recorded_at`. A cached authenticated
preflight may predate the attempt but must remain fresh at stamp time. Direct and non-M5 paths use truthful attempt
and model clocks without inventing gateway admission. Exposure and review/rating clocks are bounded
by source acceptance and their relevant attempt outcome or experiment observation; equality at a
boundary is permitted.
Every dispatched M5 request stamp, including a non-admitted attempt, is also bounded above by the
known attempt end and record creation; the missing gateway echo never permits a post-hoc stamp.

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

The only capability-negotiation authority is authenticated
`GET /v1/capabilities/learning-task` using protocol `learning-task-preflight/v1`. Its response has
an opaque advertisement id, authenticated `service:gille-inference` identity, advertised/expiry
clocks, exact contract id, schema revision **1**, and all four features. Hugin may cache it only
through `expires_at`, for at most 15 minutes. An expired response, unknown revision, missing feature,
partial response, endpoint/identity mismatch, or authentication failure selects no v1 send and
fails closed. A later request stamp embeds both the exact preflight request and accepted response;
the gateway echo therefore proves which advertisement authorized the send.

An admitted joined inference uses this stamp-and-echo handshake:

1. Hugin creates `transport.hugin_request_stamp` before dispatch. It contains task instance,
   attempt, client, idempotency key, request id, the full Hugin-owned source tuple, task type, typed
   raw-input source and fingerprint, Hugin envelope, origin config, macro decision, stamp time, exact accepted preflight,
   and `contract_request`. The request names the exact contract major, pinned schema revision 1, and
   four required features; it MUST match the record, preflight request/response, and gateway echo.
2. The gateway authenticates the actual caller independently. It MUST bind that principal to the
   request/idempotency/task stamp's `expected_transport_principal_id` and emit
   `principal_binding_digest`; a body-supplied principal is not authentication. For the current path
   this authenticated caller is the Hugin service principal, not necessarily the original source
   principal. The binding digest is SHA-256 over JCS canonical JSON containing the actual
   `authenticated_principal_id` and the complete immutable request stamp, with version
   `gateway-principal-request-binding-jcs-v1`.
3. Before model execution, the gateway verifies supported contract major/revision and the four
   advertised features, assigns gateway request/admission ids, and echoes the complete Hugin stamp.
4. Hugin accepts gateway-owned render/route/serving facts only when the echo is byte-for-byte equal
   to its stamp and the authenticated caller equals the expected transport service principal. The
   original source principal remains unchanged in the echoed source tuple. A mismatch or
   substitution is rejected and recorded as a join failure.

Retry lifecycle is exact, but mutable delivery/accounting facts never alter the stamp or learning
record:

| Event | Task/attempt/idempotency/request | Immutable accounting event | Model run |
|---|---|---|---|
| Transient request transport retry | identical stamp/key/attempt/request replayed | `request-retry`, ordinal ≥2, digest of replayed stamp | at most the original run under gateway idempotency |
| Deliberate new model execution | task reused; new attempt, idempotency key, and request id | new attempt denominator decision | yes |
| Contract-record delivery retry | exact record identity reused | `record-delivery-retry`, ordinal ≥2, digest of record identity | no |

An idempotency key MUST NOT span different task/attempt/model-execution identities. A record delivery
retry never buys another model run.

Joined records compare exact task/execution plus transport state, Hugin stamp, and gateway echo.
`transport_attempt`, `record_delivery_attempt`, and similar mutable telemetry are forbidden in that
projection. They live only as append-only `pipeline-accounting` events.

Direct gateway records set both Hugin-only stamp/echo fields to qualified `not-applicable`; they do
not invent a Hugin task. A Hugin-origin admitted gateway record cannot use unknown stamp or echo.

## Exposure facts

`inference-exposure` has two mutually exclusive projections:

- `observed-event` is an event actually recorded by one lane, with immutable `event_key`, the full
  authoritative raw fingerprint equal to `task.raw_fingerprint` (and the Hugin stamp for joined
  traffic), lane, and ordered first/last-seen clocks.
- `negative-coverage-query` is a later query result, with its own `lookup_id`, `coverage_epoch_id`,
  query time, exact queried raw fingerprint, task attempt, relevant-task time, bounded window, and a
  trusted Hugin-issued attempt proof. The proof binds an immutable Hugin task-outcome ref, request
  stamp digest, task/attempt, relevant-task time, and raw fingerprint. A body-only attempt id or a
  proof from another attempt fails.

A negative result is valid only when coverage is complete and includes exactly these six lanes:
`chat`, `mcp-ask`, `delegate`, `delegate-disagreement`, `delegate-shadow`, and `code-loop`. The
source acceptance and relevant task time MUST fall inside the window, the window MUST end no later
than the query, and query/seen clocks MUST be less than or equal to record creation. An observed event
is never rewritten into a negative lookup.

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
`admit`; it additionally requires complete nested prompt/config/serving provenance and an actual
model-running `m5-admitted` or `direct-gateway` transport. An unknown serving wrapper cannot admit a
route even when a verifier says pass. All other routing effects are inadmissible.

Product acceptance is not capability evidence. Hugin cannot promote a route by emitting a
verdict-like task or rating record; `gille-inference` imports qualified evidence through its own
ledger contract.

## Governance

Governance has exactly two states:

- `complete` requires an authenticated, owner-approved policy manifest; one exact typed policy for
  every source, raw derivative, immutable source-document ref, artifact, repository diff/file list,
  quality binding, and rating reason; and a mechanically derived effective policy.
- `policy-unavailable` contains no policies, allows no use, and is never evaluation-eligible.

The exact typed subject set prevents an unrelated policy from masking a missing derivative. Each
policy preserves the direct content owner. The effective policy is the strictest sensitivity and
erasure state, the intersection of allowed uses, earliest safe expiry, and the complete subject-ref
set. Earliest expiry is chosen by parsed RFC 3339 instant, never lexicographic text ordering.
`expires_at: not-applicable` means an explicit owner policy with no expiry; it is not unresolved
and does not by itself block evaluation. An unresolved, legacy, redacted, or producer-error expiry
requires the whole governance projection to be `policy-unavailable` and evaluation-ineligible. A
known expiry must be later than record creation. Erased/expired active content MUST use a tombstone.

`governance.effective.evaluation_eligible` means governance eligibility at emission time only. It
does not make a full candidate eligible. Candidate selection re-evaluates expiry against an explicit
decision timestamp and separately requires complete, reproducible task/execution/prompt/route/
serving/verifier/exposure provenance. Unknown or non-admitted execution provenance therefore remains
candidate-ineligible even when content policy allows evaluation.

`policy_manifest.digest` identifies an executable JCS source document containing the exact contract
and schema revision; manifest id/version/approval clock; the complete owner-attestation set; record
kind/producer; full task/source/content-owner binding; and exact typed policies sorted by UTF-16
code-unit `subject_ref` order. There is exactly one owner attestation per distinct policy
`content_owner`: either that owner authenticated directly, or an explicit unexpired delegation binds
owner, delegate, scope, and approval clock. A source service principal alone cannot authorize
evaluation. Each owner attestation carries an evidence ref into a separately trusted validation
context. That context is authenticated out of band (production may use signatures/PKI); the fixture
uses explicit trust anchors and exact payload digests. Each trusted approval non-circularly binds
the owner's exact sorted policy subset plus manifest identity/approval clock and the exact
producer/kind/task record binding; it does not hash the manifest artifact that embeds the approval
reference. Recomputing the producer manifest or an
attestation body digest is integrity, not authentication, and cannot add an issuer to the trusted
context. A service therefore cannot make itself an owner by asserting an owner-shaped body field.
`content_owner.authority` and the matching attestation mode MUST agree.

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

Every inventoried core or external store is read back as `deleted` or `absent-confirmed`;
`not-applicable` and `pending` are deliberately invalid success states. Core store names, external
inventory ids, and store receipt ids are unique. Backup expiry uses
the exact order `requested_at ≤ deadline ≤ verified_at ≤ effective_at`; it is not merely a future
promise. Until every applicable store and backup obligation is complete,
the erasure request remains operationally pending outside the contract and no success tombstone is
emitted.

The tombstone keeps only an opaque new id, producer/kind, recorded/effective clocks, opaque receipt
and superseded id, completed protocol, an exact denominator basis, its separately trusted
authoritative basis proof, and counter-owner membership
receipts. Before removing denominator-bearing evidence, every applicable counter owner MUST
idempotently confirm the original occurrence-month membership before `effective_at`. At original
denominator capture, the counter owner issues a privacy-safe trusted membership token binding owner,
counter, exact denominator natural-key digest, occurrence month, superseded record id, and issue
clock. The tombstone retains that token/digest—not a raw membership key—plus
`inserted|already-present`, matching delta `1|0`, and confirmation clock. A cross-owner joined
exposure therefore verifies a Hugin-issued token; saying `owner_component: hugin` in a gille body is
not evidence. Repeated erasure is safe and cannot double increment. Closed-period-only logic and
period/basis shifting are forbidden because either can shrink or move a denominator.

The exact required counter set is derived from `denominator_basis`: non-M5 Hugin task = capture;
M5-backed Hugin task = capture plus join; joined exposure = Hugin-owned join; direct exposure =
`gille-inference`-owned direct exposure; and a denominator-decision accounting event = its one named
counter. A gille-produced joined-exposure tombstone therefore legitimately carries a Hugin-owned
join receipt. The basis proof binds superseded producer/kind/id, basis, exact counter set, issuer,
and a valid issue clock no later than erasure request. Membership tokens likewise require a valid
issue clock no later than request and confirmation. Missing or extra receipts fail. Genuinely non-denominator records and non-denominator
accounting events explicitly say `not-denominator-bearing` and carry none. The preserved monthly
denominator survives only in the aggregate, not through retained task, source,
model, prompt, route, artifact, classification, locator, review, lineage, or extension data.
Tombstone uniqueness and active-record non-coexistence are scoped by producer plus superseded id.

## Normative ownership

The schema's `x-grimnir-field-owners` map is normative. Important decisions are:

| Fact or decision | Sole owner |
|---|---|
| Contract vocabulary, schema revision, compatibility | Grimnir |
| Hugin-origin task/source, Hugin envelope, origin config, macro decision, lifecycle/repo outcome | Hugin |
| Direct request identity, gateway/runtime prompt stages, effective serving/config, exposure, micro route | `gille-inference` |
| Task taxonomy | `gille-inference` |
| Quality Receipt, experiment design/observation/product rating, task successor | Hugin |
| Capability evidence, admission, routing-table generation | `gille-inference` |
| Correction supersession | Producer of the corrected record, same record kind and fact domain |
| Capture/join/evaluation accounting | Hugin |
| Direct-exposure accounting | `gille-inference` |
| Record-delivery accounting | Producer delivering the record |
| Classification/use/retention/erasure | Direct subject content owner; producer enforces and copies |
| Applying a reviewed prompt/harness/route/roster/config | Human operator of the owning repository |

Storage does not transfer authority. Extensions are accepted only beneath
`extensions.<producer.component>` and cannot alter v1 decisions.

Hugin is the sole repository-binding authority. Every `gille-inference`-produced learning record
MUST use a qualified unknown repository projection and consumers join the Hugin outcome; it cannot
manufacture commits, diffs, or file lists. Correction lineage uses typed
`(producer, record_kind, fact_domain, record_id)` targets. A correction can supersede only the same
producer's same-kind fact domain. A cross-owner correction is a request/correction artifact for the
owner to consider, never direct supersession.

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
| Quality receipt identity | `quality_receipt.native_receipt.receipt_id` |
| Experiment product rating | `experiment_product_rating.rating_id` |
| Pipeline accounting event | `pipeline_accounting.event_id` |

The exposure schema encodes its two conditional keys as one pointer list
`(exposure.kind, exposure.event_key, exposure.lookup_id)`: exactly one id is present in each closed
projection, so this is equivalent to the two prose rows above rather than a three-field live key.
Quality correction supersession is grouped separately by `quality_receipt.correction_group_key` so
a correction can and must carry a new native receipt id.

Identical replay is idempotent. Different canonical JSON at one natural key fails unless the newer
record explicitly targets the existing same-producer, same-kind, same-domain, same-natural-key
record. Valid correction lineage is one strictly time-advancing, acyclic chain: no missing target, self-target,
cross-key target, fork, cycle, or multiple effective leaves. Consumers select the unique
unsuperseded leaf, never the newest timestamp. Corrections and regrading append records; they do not
falsify a new task attempt or experiment run. Effective erasure/expiry is the only removal exception.

## Immutable pipeline accounting

Each accounting record is one append-only event with opaque `event_id`, exact owner, `observed_at ≤
recorded_at`, known origin/task/attempt linkage (except aggregate close), request/idempotency linkage
where applicable, optional related record identity, and one of:

- `denominator-decision` for capture, join, direct exposure, or evaluation admission/failure/
  exclusion;
- `request-retry` or `record-delivery-retry`, with ordinal ≥2 and digest of the exact replayed
  immutable identity;
- `record-emission`, including successful identity or delivery/schema/consumer failure plus an
  explicit `delivery_ordinal` (`1` initially, then the matching retry ordinal); or
- `aggregate-close`, an immutable closed-period event count and verifiable event-set digest.

Natural keys are stricter than random event ids: denominator decisions use owner, counter,
occurrence month, and origin/task/attempt; request retries use owner, immutable request linkage, and
ordinal; delivery retries use owner, related record, and ordinal; emissions use owner, related record,
and delivery ordinal; closes use owner, counter, and period. A differing duplicate requires the same
single-chain correction semantics above. A retry for two different records from one task therefore
does not collide, while two outcomes for one record/delivery ordinal do.

Every denominator decision carries `occurrence_at`, and `occurrence_month_utc` is derived from that
instant rather than asserted freely. Capture and join use Hugin `execution.started_at`; direct
exposure uses direct `task.source.accepted_at`; evaluation uses the candidate decision timestamp.
The order is `occurrence_at ≤ observed_at ≤ recorded_at`. Capture and join are Hugin-owned and
Hugin-origin; direct exposure is `gille-inference`-owned and direct-origin. Evaluation accounting is
Hugin-owned but may link a Hugin task or an imported direct-gateway candidate.

An **admitted** evaluation decision additionally carries a full joined evidence bundle, not merely
the candidate record id. It binds the task outcome, governance at the explicit decision clock,
complete task/execution/transport/prompt/config/serving provenance, observed or trusted negative
exposure coverage, independently admissible capability verifier evidence, the optional quality
cohort, and a unique task/attempt lineage. An empty quality cohort is explicitly `unrated`; when
receipts exist they must all be independent and their summary must be non-conflicted. Each plane has a reproducible digest
and every referenced record must be loaded from the trusted dataset no later than the exact decision
clock. The bundle decision equals evaluation denominator occurrence and is no later than the ledger
observation clock. A present quality cohort must have exactly one native binding and rubric; its
normalized task/attempt must join the evaluated outcome. Exact native task/result hashes remain
opaque without their Hugin source artifacts and are not reinterpreted from normalized fields. An `m5-not-admitted` outcome or
unknown serving provenance fails even when the surrounding object has bundle-shaped fields.
Every bundle ref selects the unique effective same-natural-key correction leaf as of the decision
clock. Corrections recorded later do not rewrite the historical decision. Task-outcome lineage is
likewise collapsed as of decision, so a valid predecessor plus correction is one lineage rather than
a permanent duplicate.
Quality evidence is complete per exact native binding/rubric cohort: the first bundled receipt
selects the cohort and the bundle must contain every effective correction leaf available in that
cohort at decision time. Other cohorts remain separate. An empty list truthfully means `unrated`
only when no effective receipt for the task/attempt exists at decision time; it cannot hide an
unfavorable or conflicting receipt.

Closed failure codes include `producer-error`, `consumer-error`, `schema-rejected`, `join-mismatch`,
`late-over-24h`, `policy-unavailable`, `transport-auth-failed`, `gateway-not-admitted`, `transport-error`, and
`record-delivery-failed`. Candidate exclusions are separately closed as governance denied,
erased/expired, exposure incomplete, provenance incomplete, product-quality conflict, verifier
inadmissibility, or duplicate lineage. Evaluation exclusions use only the
seven `candidate-*` codes; capture/direct boundary exclusions use
`synthetic-test|pre-v1-migration`; join boundary exclusions use
`not-m5-routed|pre-v1-migration`. Request retry requires `transport-error`, no related record, and
`request-stamp-jcs-v1`; delivery retry requires a known related record,
`record-delivery-failed`, matching delivery ordinal, and `record-ref-jcs-v1`.
An admitted capture binds a Hugin task-outcome id; admitted join/direct exposure binds a
`gille-inference` exposure id; failed or boundary-excluded capture/join/direct events bind no valid
learning record. Evaluation admission/exclusion binds the candidate record, while a pipeline failure
does not. Thus a failure remains countable when no valid learning record exists. Counter owner and
stage are exact:
Hugin capture, Hugin M5 join, direct-M5 exposure, and Hugin evaluation-candidate.

`synthetic-test` and `pre-v1-migration` are not producer labels. A synthetic exclusion carries a
trusted owner declaration made no later than occurrence/dispatch. A migration exclusion carries a
trusted, predeclared compatibility window and the occurrence must fall inside it. Missing, late, or
out-of-window evidence fails closed. The trusted proof issuer must equal the accounting event's
`owner_component`; repeating that owner inside an attacker-issued payload is insufficient.

Accounting governance permits operational metadata only (`raw_content_present: false`) under the
versioned retention policy; expiry/erasure uses the same reduced tombstone protocol. Mutable
aggregate counters are projections, not fields in events. A period uses a half-open UTC month;
`included_through` reaches at least the next-month boundary and the initial close occurs within the
declared 24-hour grace. `pipeline-event-set-jcs-v1` hashes JCS over schema version, owner, counter,
period, boundary, event count, and the UTF-16-code-unit-sorted denominator natural-key/event-id
pairs. `full-period-partition` additionally requires a separately trusted authoritative ledger
partition/high-water proof whose decision set exactly equals the loaded correction leaves. That set
may be empty: an authenticated high-water proof distinguishes a legitimate zero-event month from
missing data. The proof issuer must equal the counter-owning event `owner_component`. A producer's
`full-period` string, a recomputed body digest, a partial dataset, or an
unproven empty load cannot certify completeness. A close without that proof says `partial-dataset-deferred`; it is
accepted only as explicitly unverified, never silently certified. Each snapshot selects
denominator correction leaves as of `closed_at`, so a later correction does not retroactively
invalidate the old snapshot. Late evidence appends an explicit same-key close correction; that
unique effective leaf is the current snapshot, never implicit newest-wins.

## Compatibility and rollout

An unknown contract major fails closed. Semantic change, field reuse, privacy weakening, or enum
reinterpretation requires `v2` and a parallel migration. This schema and preflight pin
`schema_revision: 1`; revision 999 or any other revision fails closed. A future v1 revision requires
a separately published schema/reader branch and cannot be treated as this schema with extra fields.
Both sides pin the canonical schema, source documents, JCS vectors, and fixtures; two locally
invented mocks do not prove compatibility.
Changing the closed task-taxonomy enum requires a coordinated schema revision and producer/consumer
rollout; changing the taxonomy document alone cannot reinterpret revision 1 records.

The rollout is capability-negotiated and must follow this matrix:

| Phase | Hugin write | Gateway read | Gateway write | Hugin read | Minimum duration and gate | Rollback |
|---|---|---|---|---|---|---|
| 0 baseline | legacy only | legacy | legacy | legacy | Record seven baseline days of request, admission, mismatch, latency, and delivery-retry rates | no change |
| 1 preflight/readers | legacy only; authenticated preflight fetch may run | legacy + v1 fixture/shadow parser; authenticated versioned preflight endpoint | legacy only; no echo for an unsent stamp | legacy + preflight freshness/cache validator + v1 fixtures | ≥7 complete days; preflight identity/freshness ≥99.9%, zero partial advertisements accepted, fixture parse 100%, p95 preflight overhead <10 ms | disable preflight fetch and shadow parser |
| 2 dual write | legacy + v1 stamp when capability advertised | dual read, v1 verify | legacy + v1 echo | dual read/compare | ≥7 complete days and ≥100 real eligible attempts, whichever is later; ≥99.5% exact joins, zero conflict-key mismatch | stop v1 emission, retain dual readers |
| 3 v1 preferred | v1, legacy fallback only for unadvertised peer | dual read | v1 | v1 + legacy fallback | ≥14 complete days; ≥99.9% valid joins, zero auth substitution, <0.1% schema reject, no model-run increase from delivery retry | restore phase 2 writes |
| 4 retire legacy | v1 only | v1 only | v1 only | v1 only | both owner approvals plus 30 complete green days and no legacy traffic for 14 days | redeploy last dual-reader release; do not reinterpret stored v1 |

Capability advertisement is checked before every v1 send or unexpired bounded-cache reuse and includes contract major, pinned schema revision 1, and
`hugin-request-stamp-v1`, `gateway-echo-v1`, `three-stage-prompt-provenance-v1`, and
`reproducible-serving-digests-v1`. Absence before phase 4 selects the declared legacy path; partial
advertisement fails closed and cannot silently strip fields. Dashboards separately report legacy,
shadow, dual, v1, fallback, rejection, and rollback populations.

## Conformance fixtures and required tests

The canonical schema ships with dependency-free positive and adversarial fixtures under
`tests/fixtures/learning-task-contract/`. CI uses the dependency-free semantic validator. A
Draft 2020-12 check is supplied for environments that explicitly provide that dependency. It is
authoritative for structural JSON Schema semantics. The required semantic validator separately
enforces cross-record invariants and exact contract formats, including rejecting impossible calendar
dates such as February 30; passing only the structural check is insufficient. The
dependency-free validator also rejects schema keywords it does not implement, preventing a future
keyword from being silently ignored. It likewise rejects malformed shapes for every supported
keyword (`items`, `properties`, `$defs`, combinators, required/enums, and scalar constraints) rather
than ignoring or crashing on them; Draft 2020-12 remains the authoritative schema semantics.

Producer and consumer suites MUST prove:

1. the same Hugin task/attempt has exact `task`, `execution`, and `transport` projections, including
   attempt/model clocks and authoritative raw fingerprint;
2. authenticated preflight freshness/features/revision, stamp/echo, and principal substitution fail
   closed;
3. direct and joined observed events plus a separate six-lane negative query validate;
4. canonical raw hashes are computed; every prompt/model/config/sampling digest resolves to a typed
   immutable source document and passes RFC 8785 conformance/mutation vectors;
5. policy-unavailable, exact owner/delegation attestations, typed complete policy, numeric expiry,
   erasure, exact idempotent original occurrence-month membership preservation, and backup/store receipts fail closed;
6. native v1 quality artifacts remain exact and fail closed when normalization fabricates
   attempt/rubric/retries; future v2 corrections use a new native id and explicit correction group;
   multiple independent receipts/experiment ratings validate; correction chains select their
   unique leaf; and independent conflicting summaries do not promote;
7. capability admission cannot be driven by self, advisory, uncalibrated, failed, or inadmissible
   evidence; and
8. unknown fields, bad clocks/hashes/commit ids, cross-plane identity mismatch, cross-owner
   repository/correction claims, conflict-key reuse, and active+tombstone coexistence fail; and
9. every denominator/failure/exclusion, request retry, delivery retry, record emission, and period
   close is representable without fabricating a missing learning record; natural-key forks fail;
   and full close count/digest recompute from a trusted as-of ledger partition/high-water proof; and
10. admitted evaluation binds and loads the full governance/provenance/exposure/verifier/quality/
    lineage bundle; an empty quality cohort binds `unrated`, a present cohort must be independent and
    non-conflicted, and record-id-only or non-admitted candidates fail.

## Adoption and measurable meaning of continuous

The contract describes the target seam, not current deployment. Existing task/repository,
experiment, M5 exposure, capability, verifier, and guarded routing mechanisms do not yet emit this
complete projection. Hugin's code-loop client does provide useful partial feasibility evidence:
`tools/list` preflight plus `client_run_id` and `request_fingerprint` response binding. That is not
the authenticated contract preflight/stamp/echo defined here. Likewise native Quality Receipt v1
does not provide the normalized attempt/rubric or same-reviewer correction semantics. Organic
judge/delegate evidence is shadow. Product rating, promotion, deployment, rollback, trusted
validation-context distribution, cross-owner erasure tokens, and authoritative partition proofs
remain implementation work.

Phase 1 adoption is bounded by owning tickets; work outside these tickets requires an explicit
contract/roadmap change rather than implicit scope expansion:

- `gille-inference`: [#2 preflight/stamp validation/echo](https://github.com/Magnus-Gille/gille-inference/issues/2),
  [#3 authoritative accounting and period closes](https://github.com/Magnus-Gille/gille-inference/issues/3), and
  [#4 canonical exposure identity and holdout coverage](https://github.com/Magnus-Gille/gille-inference/issues/4).
- Hugin: [#240 requester-side preflight-bound stamps and attempt evidence](https://github.com/Magnus-Gille/hugin/issues/240),
  [#230 canonical M5 exposure identity](https://github.com/Magnus-Gille/hugin/issues/230),
  [#231 concurrency-safe actionable Quality Receipts](https://github.com/Magnus-Gille/hugin/issues/231), and
  [#232 durable append-only task/outcome registry](https://github.com/Magnus-Gille/hugin/issues/232), and
  [#241 Hugin-owned capture/join/evaluation accounting, cross-owner membership tokens, authoritative partitions, and monthly closes](https://github.com/Magnus-Gille/hugin/issues/241).

“Continuous” uses disjoint complete UTC calendar months with 24-hour close grace:

An **eligible Hugin attempt** is every production Hugin `execution.attempt_id` whose `started_at`
falls in the month. Failed, timed-out, cancelled-after-start, private, no-op, publication-failed,
erased, and unrated attempts remain in the capture denominator. Request transport and record
delivery retries are accounting events, not new attempts; a deliberate new model execution has a
new attempt/request/idempotency identity. The only exclusions are `synthetic-test`, declared before
dispatch, and `pre-v1-migration`, started inside the documented compatibility window. Rejection
before Hugin acceptance/execution is not an attempt.

An **eligible M5-backed join** is an eligible Hugin attempt whose Hugin-owned macro decision selected
M5 before execution. Gateway non-admission, authentication failure, missing echo, and schema failure
remain denominator failures. Whether the gateway produced a convenient record cannot redefine the
denominator. A Hugin attempt whose macro target was not M5 emits a `not-m5-routed` join-boundary
exclusion with request/idempotency marked `not-applicable`; it cannot masquerade as a dispatched
join failure or member.

An **eligible direct-owner request** is every authenticated, non-synthetic direct chat, MCP ask,
delegate, delegate-disagreement, delegate-shadow, or code-loop user turn accepted by
`gille-inference` in the month. Policy lookup failure, denial, model failure, and missing exposure
remain in this capture denominator; only a request rejected before authentication/acceptance and
documented `pre-v1-migration` traffic are excluded. This denominator never inflates Hugin capture or
join coverage.

An **eligible evaluation candidate** is a captured task/outcome with evaluation allowed, active
retention, complete just-in-time exposure evidence, a reproducible independent verifier, and unique
source lineage/raw fingerprint. Admission occurs only when the full immutable joined evidence bundle
described above is loaded and its five digests verify. Candidate exclusions are exactly `candidate-governance-denied`,
`candidate-erased-or-expired`, `candidate-exposure-incomplete`,
`candidate-provenance-incomplete`, `candidate-product-quality-conflicted`,
`candidate-verifier-inadmissible`, and `candidate-duplicate-lineage`.

Every missing, late, or rejected capture/join has one persisted `pipeline-accounting` event.
`not-m5-routed` is the explicit join-boundary exclusion backed by the prior Hugin macro decision;
the seven candidate exclusions
explain only evaluation boundaries. `gateway-not-admitted`, `transport-auth-failed`,
`policy-unavailable`, `producer-error`, `consumer-error`, `schema-rejected`, `join-mismatch`,
`transport-error`, and `late-over-24h` are failures and cannot become exclusions. Unclassified
omissions fail the metric.

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
