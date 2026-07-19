# LearningTaskContract v1

> **Status:** proposed v1; it becomes effective only after recorded Hugin and `gille-inference`
> owner reviews.
> **Contract id:** `grimnir.learning-task/v1`.
> **Machine schema:** [`learning-task-contract-v1.schema.json`](learning-task-contract-v1.schema.json).
> **Schema owner:** Grimnir. Field values remain owned by the producer named below.
> **Review gate:** Hugin owner — pending; `gille-inference` owner — pending. Record both review links
> before merging this contract or closing dependent implementation tickets.

## Purpose and boundary

This contract is the join between Hugin's task/product evidence and the M5 gateway's inference
evidence. It makes one task traceable across both systems without creating a second copy of its
prompt, answer, repository contents, or correction.

The contract is **content-governed**, not a license to collect content. Cross-repository records
carry stable identifiers, hashes, classifications, and owner-controlled references. A consumer may
dereference content only when its principal, purpose, sensitivity ceiling, and retention policy
allow it. Hashes are identifiers, not anonymization: sensitive input produces sensitive-derived
metadata and keeps the same access class unless an owner explicitly proves a safer class.

Version 1 is an envelope and ownership contract. It does not replace Hugin's task/result, Quality
Receipt, or experiment schemas, and it does not replace `gille-inference`'s exposure, delegation,
capability-ledger, or routing schemas. Producers project those records into this seam; neither side
may infer a missing verdict owned by the other.

Normative terms **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used as in RFC 2119.

## Record model

The JSON Schema is normative for JSON types, closed enums, object shape, and per-kind required
fields. A component may store a native representation only if its exported projection validates
losslessly. The four discriminated record kinds and their active projections are:

| `record_kind` | Required active section | Required producer | Permitted active task origin |
|---|---|---|---|
| `task-outcome` | `outcomes` | Hugin | Hugin |
| `inference-exposure` | `exposure` | `gille-inference` | Hugin or direct `gille-inference` request |
| `capability-evidence` | `capability` | `gille-inference` | Hugin or direct `gille-inference` request |
| `experiment-observation` | `experiment` | Hugin | Hugin |

An active record has `lifecycle_state: "active"` and contains the common fields required by
`$defs.baseRecord`. A content-removal receipt has
`lifecycle_state: "content-removed-tombstone"` and validates against the deliberately smaller
`$defs.tombstoneBaseRecord`; it is not an active record with fields nulled out. Closed objects reject
unknown top-level or nested fields. Additive active-record data is confined to the current
producer's namespace under `extensions`; tombstones have no extension surface.

Unknown is never an unqualified JSON `null`. A field that permits absence uses this exact shape:

```json
{ "value": null, "unknown_reason": "not-applicable | not-observed | legacy | producer-error | redacted | erased | expired", "detail": "optional non-empty explanation" }
```

The schema says which fields permit that union. A required known value cannot use it. A producer
MUST NOT manufacture a value to make a record look complete.

### Content-removal tombstone

Effective erasure or expiry is the explicit exception to content-record append-only storage. The
producer MUST remove the superseded active projection and any content-keyed exposure rows, then MAY
retain one replacement `content-removed-tombstone`. The active projection and its tombstone MUST
NOT coexist in a conforming dataset.

The tombstone contains only the contract/revision/lifecycle/kind, an opaque new `record_id`, the
producer stamp and `recorded_at`, plus:

| Tombstone field | Owner | Meaning |
|---|---|---|
| `tombstone.removal_reason`, `effective_at` | Record producer, acting on the content owner's policy | Erased/expired decision and its effective time; `recorded_at` cannot precede it. |
| `tombstone.receipt_id` | Record producer | Opaque, non-content-derived erasure audit identity. |
| `tombstone.superseded_record_id` | Original record producer | Opaque, non-content-derived id used only to prove the active record was removed. |
| `tombstone.counter_audit[]` | Counter owner | Optional monthly aggregate-counter disposition; `(counter, period_utc)` is unique. Hugin owns Hugin capture/join/evaluation counters; `gille-inference` owns direct-M5 exposure. |

`counter_audit` may be empty: a producer MUST NOT invent an adjustment for a counter it does not
own. A preserved monthly denominator survives in the aggregate, not by retaining task type, source,
model, prompt, route, artifact, classification, locator, governance detail, review, lineage, or an
extension. Both `record_id` values are schema-constrained opaque UUIDv4 ids; no content-derived or
structured legacy identifier may be copied into the tombstone.

| Envelope field | Owner | Meaning |
|---|---|---|
| `contract_version` | Grimnir | Version and compatibility semantics of this seam. |
| `schema_revision` | Grimnir | Additive v1 schema revision; it never changes v1 semantics. |
| `lifecycle_state`, `record_kind` | Grimnir | Closed lifecycle and projection vocabularies; the producer asserts the applicable values. |
| `record_id` | Record producer | Immutable, opaque producer-scoped UUIDv4 identity prefixed `opaque:`; it embeds no task, source, model, route, or content classification. |
| `producer.component`, `producer.schema_version` | Record producer | Component and native schema that supplied the facts. |
| `recorded_at` | Record producer | Time the projection was created; it never replaces source/execution times. |

### Task identity and type assignment — origin owned; taxonomy — `gille-inference` owned

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `task.origin_component` | Origin component | yes | `hugin` for Hugin tasks or `gille-inference` for direct gateway/MCP/chat work. |
| `task.instance_id` | Origin component | yes | Stable origin-scoped task/request identity; retries do not mint a new task. |
| `task.source.component`, `system`, `id` | Origin component | yes | Source identity; component MUST equal `task.origin_component`. |
| `task.source.created_at`, `accepted_at` | Origin component | yes | Source creation and acceptance clocks, not terminal update time. |
| `task.task_type.id` | Origin component | yes | Origin's assignment from the advertised canonical vocabulary. |
| `task.task_type.taxonomy_id` | `gille-inference` | yes | Canonical taxonomy name advertised to Hugin. |
| `task.task_type.taxonomy_version` | `gille-inference` | yes | Immutable version/digest of that taxonomy. |
| `task.raw_fingerprint` | Origin component | yes when active | `{algorithm, version, digest}` before any context/template rendering; it is absent from content-removal tombstones. |

Hugin MUST preserve its raw task separately from rendered prompts. Direct M5 traffic has a
`gille-inference`-owned raw request identity and does not fabricate a Hugin task id. The raw
fingerprint is the cross-client join/freshness key and MUST NOT contain context, a system prompt,
chat template, tool description, or other harness-added bytes.

### Execution and serving identity — split by fact owner

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `execution.attempt_id`, `started_at`, `ended_at` | Origin component | yes | Stable attempt and its actual interval; recovery semantics are explicit. |
| `execution.prompt_identity.hugin_rendered` | Hugin | required union | Hugin envelope algorithm/version/digest; `not-applicable` for direct gateway traffic. |
| `execution.prompt_identity.gateway_rendered` | `gille-inference` | required union | Final gateway render algorithm/version/digest; `not-applicable` when no gateway ran. |
| `execution.routing.macro` | Hugin | required union | Hugin macro policy id/version/decision id; `not-applicable` for direct gateway traffic. |
| `execution.routing.micro` | `gille-inference` | required union | Gateway micro policy id/version/decision id; `not-applicable` when no gateway ran. |
| `execution.serving.runtime_id`, `provider_id` | Effective serving owner | yes | Effective runtime/provider, not requested aliases. |
| `execution.serving.model.id`, `artifact_digest`, `config_epoch` | `gille-inference` for gateway calls; Hugin otherwise | required unions | Canonical served model and immutable artifact/config identity. |
| `execution.prompt_version` | Hugin for Hugin origin; `gille-inference` for direct origin | required union | Agent/system prompt version; `not-applicable` only when the lane has no such prompt. |
| `execution.harness_version` | Hugin for Hugin origin; `gille-inference` for direct origin | yes | Harness identity and immutable configuration digest. |
| `execution.tool_policy_version` | Hugin for Hugin origin; `gille-inference` for direct origin | yes | Effective tools/permissions policy version. |
| `execution.serving.sampling_version` | `gille-inference` for gateway calls; Hugin otherwise | yes | Effective temperature/top-p/seed/reasoning/output-limit configuration digest. |

For a Hugin→gateway attempt, Hugin owns the attempt, Hugin render, and macro route; the gateway owns
its final render, effective provider/model/config/sampling, and micro route. The two prompt and two
routing identities are separate fields even when their bytes or policy version happen to match.
Hugin MUST consume gateway-stamped facts rather than copying its request as observed truth.

### Artifact bindings — producer-bound; repository evidence Hugin owned

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `artifacts.items[]` | Record producer | when applicable | `{kind, owner, ref, content_hash}` for input/output/publication/correction artifacts. |
| `artifacts.repository.base_commit`, `head_commit` | Hugin | for managed-repo attempts | Exact before tree and task head. |
| `artifacts.repository.diff_hash`, `changed_files_ref` | Hugin | when a diff exists | Canonical binary diff fingerprint and governed file-list reference. |

The producer owns the seam binding between its record and these references/hashes; the referenced
artifact's content owner does not change. A consumer validates the hash when dereferencing and records a
contract error on mismatch; it does not silently refresh the hash.

### Outcomes — no cross-owner verdict fabrication

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `outcomes.execution` | Hugin | yes | Lifecycle outcome such as completed, failed, cancelled, timeout, or infrastructure error. |
| `outcomes.repository` | Hugin | for repo tasks | Structured repository result, including no-change and not-finalized states. |
| `outcomes.publication` | Hugin | when applicable | Not attempted, succeeded, failed, or unknown with evidence. |
| `outcomes.product_quality` | Hugin | after review | Quality Receipt rating/disposition; `unrated` is explicit. |
| `capability.outcome`, `routing_effect` | `gille-inference` | for capability evidence | Verifier-backed pass/partial/fail/error/unverified plus admitted/frozen/rejected/shadow effect. |
| `outcomes.execution_failure_mode` | Hugin | on execution/repository/publication failure | Versioned categorical operational or product failure reason. |
| `capability.failure_mode` | `gille-inference` | on capability failure | Versioned categorical verifier/model capability failure reason. |

Execution success does not imply repository success; repository publication does not imply product
quality; product acceptance does not by itself become a model capability verdict. Only
`gille-inference` may apply evidence to the capability ledger, through its defined import/write
contract and evidence policy.

### Verifier, correction, and lineage — Hugin owned except capability grading

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `experiment.verifier` | Hugin | for experiment claims | Stable verifier/rubric identity, versions, and deterministic/human/judge kind. |
| `capability.verifier` | `gille-inference` | for capability claims | Stable verifier/rubric identity, versions, and deterministic/human/judge kind. |
| `review.reviewer_principal_id`, `reviewed_at` | Hugin for product/experiment review; `gille-inference` for capability review | for human review | Authenticated reviewer and receipt time, never free-form identity. |
| `lineage.corrects_record_ids[]` | Record producer | when corrective | Same-plane records this result supersedes/corrects. |
| `lineage.correction_ref` | Hugin | when content was corrected | Reference to an `artifacts.items[]` correction binding that carries the governed hash. |
| `lineage.successor_task_ids[]` | Hugin | when follow-up exists | Tasks created to repair or extend this result. |

A judge-only result remains advisory until its declared calibration gate is met. Regrading MUST
append/supersede under a new rubric or policy version; it MUST NOT destructively rewrite history.

### Governance and exposure — per-source/artifact policy plus strict effective policy

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `governance.policies[]` | Each referenced source/artifact's content owner; recorded by its producer | yes | One policy per source, content-derived fingerprint, artifact ref, and repository file-list ref. |
| `policies[].sensitivity`, `classification_version` | Named content owner | yes | Subject-specific classification and its policy version, copied by the record producer. |
| `policies[].allowed_uses[]` | Content owner | yes | Closed v1 set: operations, evaluation, debug. Empty denies all; training export is invalid in v1. |
| `policies[].retention` | Content owner | yes | Subject-specific policy and expiry or qualified unknown. |
| `policies[].erasure` | Content owner | yes | Active/requested/erased/expired plus effective time and digest disposition. |
| `governance.effective` | Record producer, mechanically derived | yes | Strictest sensitivity/erasure, intersection of allowed uses, earliest known expiry, and every contributing subject ref. |
| `exposure.state`, `coverage`, `first_seen_at`, `last_seen_at` | `gille-inference` | for exposure records | Seen/unseen-covered/incomplete/error/not-checked plus bounded coverage evidence. |

Hugin enforces governance for Hugin-origin records. `gille-inference` enforces it for direct gateway,
MCP, chat, and code-loop origins; direct traffic MUST NOT claim Hugin enforcement or invent a Hugin
task. A joined Hugin→M5 record derives effective policy from both planes and uses the strictest
sensitivity, earliest known expiry, most advanced erasure state, and allowed-use intersection.

Raw/prompt fingerprints, output hashes, and diff hashes are content-derived metadata, not anonymous
identifiers. Qualified `redacted`/`not-observed` values may express an active producer's legitimate
lack of a field. Once erasure or expiry becomes effective, the full active projection and exposure
rows keyed by its content MUST be removed and replaced, if an audit receipt is retained, by the
reduced tombstone above. The tombstone cannot carry qualified-null placeholders as a way to retain
task/model/routing shape. It also MUST NOT restore content from another learning copy. A candidate
is excluded when use is denied, erasure/expiry applies, sensitivity exceeds the evaluator ceiling,
or freshness coverage is incomplete.

## Normative field-ownership audit

The schema's `x-grimnir-field-owners` map is normative. The grouped paths below cover every leaf in
an active record or tombstone; a producer may copy another owner's stamp but cannot recompute or
reinterpret it. “Origin” resolves to the one value in `task.origin_component`; “producer” resolves
to `producer.component`, so each record has exactly one owner for each emitted leaf.

| JSON path group | Sole fact owner |
|---|---|
| `contract_version`, `schema_revision`, `lifecycle_state`, `record_kind` | Grimnir owns vocabulary and semantics. |
| `record_id`, `producer.*`, `recorded_at` | Record producer. |
| `tombstone.removal_reason`, `effective_at`, `receipt_id`, `superseded_record_id`, `counter_audit.*` | Tombstone producer; it may name only its owned counters. |
| `task.origin_component`, `instance_id`, `source.*`, `task_type.id`, `raw_fingerprint` | Task origin. |
| `task.task_type.taxonomy_id`, `taxonomy_version` | `gille-inference`. |
| `execution.attempt_id`, `started_at`, `ended_at`, `prompt_version`, `harness_version`, `tool_policy_version` | Task origin. |
| `execution.prompt_identity.hugin_rendered`, `execution.routing.macro` | Hugin. |
| `execution.prompt_identity.gateway_rendered`, `execution.routing.micro` | `gille-inference`. |
| `execution.serving.runtime_id`, `provider_id`, `model.*`, `sampling_version` | `gille-inference` when a gateway ran; otherwise the task origin. |
| `artifacts.items[].kind`, `owner`, `ref`, `content_hash` | Record producer owns the binding; `items[].owner` remains content authority. |
| `artifacts.repository.*` | Hugin. |
| `outcomes.*` | Hugin. |
| `exposure.event_key`, `state`, `fingerprint_version`, `lane`, `first_seen_at`, `last_seen_at`, `coverage.complete`, `coverage.from`, `coverage.through`, `coverage.lanes[]` | `gille-inference`. |
| `capability.evidence_id`, `outcome`, `failure_mode`, `verifier.*`, `policy_epoch`, `routing_effect` | `gille-inference`. |
| `experiment.experiment_id`, `run_id`, `sample_id`, `arm`, `holdout`, `configuration_fingerprint`, `verification_outcome`, `product_outcome`, `verifier.*` | Hugin. |
| `governance.policies[].subject_ref`, `subject_kind` | Record producer owns the binding. |
| `governance.policies[].content_owner`, `sensitivity`, `classification_version`, `allowed_uses`, `retention.*`, `erasure.*` | Named `content_owner`; producer copies its policy. |
| `governance.effective.*` | Record producer, by the specified mechanical derivation. |
| `lineage.corrects_record_ids[]` | Record producer. |
| `lineage.correction_ref`, `successor_task_ids[]` | Task origin. |
| `review.*` | Hugin for task/product/experiment review; `gille-inference` for exposure/capability review. |
| `extensions.<producer.component>.*` | Record producer. Other namespaces fail semantic validation. |

## Decision ownership

| Decision | Sole owner | Consumer obligation |
|---|---|---|
| Hugin-origin identity, source, task-type assignment, macro runtime, lifecycle, repo/publication/product outcome, correction lineage | Hugin | `gille-inference` imports stamped facts or rejects them; it does not recreate them. |
| Direct gateway/MCP/chat/code-loop task identity, source and request lifecycle | `gille-inference` | Hugin may consume a stamped direct-origin record; it does not fabricate a Hugin task id. |
| Canonical task taxonomy vocabulary and version | `gille-inference` | Hugin consumes the advertised taxonomy, records its assignment, and uses the explicit fallback for unknown values. |
| Raw-task canonical bytes supplied to the seam | Task origin (Hugin or `gille-inference`) | Consumer verifies the origin-stamped fingerprint/version and binds it to exposure. |
| Effective gateway provider/model/artifact/config/sampling, exposure, micro-route, capability verdict | `gille-inference` | Hugin records returned stamps or marks them unavailable; it does not infer them. |
| Prompt/harness/tool-policy experiment design and product gates | Hugin | Gateway supplies exact serving evidence for each arm. |
| Capability-evidence admission and routing-table generation | `gille-inference` | Hugin cannot promote by writing a verdict-like task record. |
| Content use, sensitivity, retention, correction, and erasure authority | Referenced subject's content owner; enforced by the record producer | Joined consumers derive the strictest effective policy and fail closed when any policy is missing. |
| Cross-repo schema, compatibility rules, and status vocabulary | Grimnir | Hugin and `gille-inference` both review changes and implement conforming projections. |
| Deployment of a reviewed prompt, harness, route, roster, or config | Owning repository's human operator | `promotion-ready` is evidence, not deployment authority. |

## Producer/consumer conformance

The canonical schema ships with dependency-free positive and adversarial fixtures under
`tests/fixtures/learning-task-contract/`. Each component repository MUST vendor or immutably pin
the canonical fixture revision. The Hugin and `gille-inference` projections MUST include the same
logical joined task plus a direct-gateway-origin case, with raw, Hugin-rendered, and gateway-rendered
identities represented separately.

Required contract tests:

1. Hugin serializes its fixture; the `gille-inference` consumer accepts it without transformation.
2. `gille-inference` serializes exposure and served-model evidence; Hugin accepts and joins it to
   the original `task.instance_id` and `execution.attempt_id`.
3. Both sides independently calculate the same raw-task digest. Hugin and gateway rendering each
   have their own algorithm/version/digest; the synthetic wrapper fixture makes all three values
   deliberately different.
4. Any known raw, Hugin-rendered, gateway-rendered, macro-route, micro-route, or serving identity
   mismatch across the joined task/attempt fails. A schema-qualified unknown may defer only the
   field where the schema explicitly permits it; it cannot overwrite a known owner stamp.
5. Unknown major version, unknown required enum, missing owner-required field, invalid timestamp,
   hash mismatch, duplicate conflicting `record_id`, or incomplete negative exposure coverage fails
   closed.
6. Unknown top-level/nested fields fail. Additive v1 data is accepted only in
   `extensions.<producer.component>` and may not alter v1 decisions.
7. A correction propagates append-only. Erasure/expiry removes the active projection and propagates
   only the reduced tombstone; a dataset retaining both fails.

CI MUST pin the companion fixture revision or fetch an immutable released fixture; it MUST NOT test
only two local mocks of the same assumption. A coordinated contract change is not complete until
both producer and consumer suites pass. The v1 proposal is not effective until owners of both Hugin
and `gille-inference` review it and their review links replace the pending markers at the top.

### Idempotency, uniqueness, and conflict keys

The schema's `x-grimnir-conflict-keys` extension is normative. The kind-specific keys apply only to
active records; a tombstone has only its producer/record conflict key and its opaque
`superseded_record_id` non-coexistence rule:

| Scope | Immutable conflict key |
|---|---|
| Every record | `(producer.component, record_id)` |
| Task outcome | `(task.origin_component, task.instance_id, execution.attempt_id)` |
| Inference exposure | `exposure.event_key` |
| Capability evidence | `capability.evidence_id` |
| Experiment observation | `(experiment.experiment_id, experiment.run_id)` |

An identical replay at a key is idempotent. Different canonical JSON at the same key is a conflict
and MUST fail without last-write-wins. Experiment sampling also deduplicates source lineage and raw
fingerprint; retries and duplicate prompts do not become independent samples.

## Evolution rules

- `contract_version` is the exact major identifier. An unknown major fails closed. A semantic
  change, field reuse, weakened privacy rule, or enum reinterpretation requires `v2` and a parallel
  migration period.
- `schema_revision` may increase within v1 for optional data under `extensions` or a new explicit
  `task_type.taxonomy_version` branch, with one owner, unchanged existing-v1 decisions, and fixtures
  before use. Required fields and every existing versioned enum branch remain unchanged.
- Required fields and enum meanings never change in place. The task taxonomy is closed per version;
  a new vocabulary adds a new `gille-inference`-owned version branch and never reinterprets an old
  id/version. Other enum changes require v2; decision-driving consumers fail closed.
- Corrections, judge-policy changes, and regrading are append-only and use lineage rather than
  destructive edits. Effective erasure/expiry is the explicit exception: delete the superseded
  content-bearing projection and keyed exposure rows, then retain at most the reduced replacement
  tombstone and aggregate counter audit. Retaining both is invalid.
- A producer advertises major/revision it emits; a consumer advertises the major/revisions it accepts.
  Deployment order is expand consumer → switch producer → retire old reader after the documented
  compatibility window.
- Raw, Hugin-rendered, and gateway-rendered prompt fingerprints have separate algorithm/version
  fields. Macro and micro routing have separate policy/version/decision fields. No field may
  silently fall back to, copy, or stand in for another.

## Adoption state and roadmap

These labels are the v1 migration target, not a claim that every component document/dashboard
already uses them. Grimnir uses them here; Hugin and `gille-inference` adopt them through their
implementation tickets. Until then, component-local labels MUST be mapped explicitly before a
cross-system status claim. The labels describe mechanisms, not live deployment health:

| Stage | Meaning | Current v1 position |
|---|---|---|
| **Implemented** | Code emits/enforces the evidence in production paths. | Hugin task/result/repository evidence, Quality Receipt mechanism, controlled experiment ledger and daily candidate factory; M5 exposure registry, capability ledger, deterministic verifiers and guarded routing-table generation. Existing schemas are not yet full v1 projections. Quality Receipt first-create concurrency remains partial as described in [observability-and-improvement.md](observability-and-improvement.md). |
| **Shadow** | Runs and records evidence but cannot change normal routing. | M5 organic harvest/judge and delegate-policy evidence. It remains non-authoritative until representative human calibration passes. |
| **Manual** | A human performs the decision/action. | Product rating, candidate approval, independent-verifier acceptance, challenger deployment, champion pointer advancement, and rollback. |
| **Future** | Specified but not yet an operational path. | Durable all-outcome learning registry, candidate-to-experiment packager, Hugin→M5 verified-evidence import, automated guarded routing reload, and read-only experiment proposals. Model-weight training is outside v1. |

Implementation order is deliberately integrity-first:

1. Land compatible v1 identity/taxonomy projections and the cross-repo fixture tests.
2. Close the Quality Receipt concurrent-first-create gap, then capture corrections/successors.
3. Store all eligible outcomes durably, including failures, no-ops, and publication failures.
4. Package reviewed candidates with just-in-time exposure checks into one-axis experiments.
5. Import verified experiment evidence into the capability ledger and regenerate routing through a
   reviewed deployment/rollback path.
6. Only then add read-only experiment proposals; no automatic mutation is implied.

## Measurable meaning of “continuous”

Grimnir MUST qualify the claim. A timer or growing ledger alone is not a continuous improvement
loop. Measurements use **disjoint complete UTC calendar months**, with a 24-hour close grace after
month end. A late record remains `late-over-24h`; it cannot retroactively turn a published red month
green.

### Denominators and exclusions

An **eligible Hugin attempt** is every production Hugin `execution.attempt_id` whose `started_at`
falls inside the month. Retries are separate attempts. Failed, timed-out, cancelled after start,
private, no-op, publication-failed, erased, and product-unrated attempts remain in the capture
denominator; erased data contributes a minimal tombstone. The only capture exclusions are:

- `synthetic-test` — declared test/smoke traffic before dispatch; and
- `pre-v1-migration` — started under the documented compatibility window before v1 emission.

A request rejected before Hugin acceptance/execution is not an attempt. No other exclusion may be
added without a contract revision and both component-owner reviews.

An **eligible M5-backed join** is an eligible Hugin attempt whose recorded macro route selected M5
before execution. Eligibility is fixed by that Hugin-owned decision, not by whether the gateway
later admitted the request or emitted evidence. Connection or admission failure is therefore a
`gateway-not-admitted` join failure, not a denominator exclusion. Direct M5 traffic is measured by
`gille-inference` exposure coverage separately; it never inflates Hugin join coverage.

An **eligible evaluation candidate** is a captured task/outcome with evaluation allowed by effective
governance, active retention, complete just-in-time exposure evidence, a reproducible independent
verifier, and unique source lineage/raw fingerprint. Candidate exclusions use exactly:
`governance-denied`, `erased-or-expired`, `exposure-incomplete`, `unreproducible`, or
`duplicate-lineage`. Retries and repeated prompts may supply operational evidence but count once as
an independent evaluation sample.

Every missing/late/rejected join has one persisted omission code. `not-m5-routed` and the candidate
exclusions above explain denominator boundaries; `gateway-not-admitted`, `producer-error`,
`consumer-error`, `schema-rejected`, `join-mismatch`, and `late-over-24h` are failures and MUST NOT
be converted into exclusions. Unclassified omissions fail the metric.

### Owners, sources, clocks, and gates

| Claim | Measurement owner | Authoritative source and clock | Gate per disjoint month |
|---|---|---|---|
| **Continuous Hugin capture** | Hugin | Hugin accepted task/attempt registry; denominator by `execution.started_at`, completion by terminal checkpoint, delivery by contract `recorded_at` | At least 95% of eligible attempts emit a schema-valid task-outcome within 24 hours of terminal state; every remainder has a failure code. |
| **Continuous M5 cross-plane join** | Grimnir cross-repo validator | Hugin task-outcome plus `gille-inference` exposure/serving records; join by origin task, attempt, and raw fingerprint; month from Hugin `started_at` | At least 95% of eligible M5-backed joins resolve within 24 hours; zero unresolved conflict-key or identity mismatch. Report direct-M5 exposure coverage separately. |
| **Continuous evaluation** | Hugin | Durable candidate registry and experiment ledger; candidate month from source `created_at`, disposition month from authenticated `reviewed_at` | When at least ten unique eligible candidates exist, one production-derived frozen batch completes independent verification and one distinct one-axis `experiment_id` reaches reviewed disposition. Below ten is `insufficient-volume`, never pass. |
| **Continuous learning** | Grimnir monthly system review | Three consecutive complete monthly reports plus immutable Hugin experiment and M5 capability references | Capture, join, and evaluation gates pass in all three months; each month uses a different `experiment_id`, and each disposition changes durable knowledge via a rejected next hypothesis or accepted reviewed reference. |
| **Continuously improving baseline** | Owning repository operator, attested by Grimnir review | Exact applied repo/config reference, champion lineage, observation window, product/non-regression result, and tested rollback | Across the same latest three complete months, at least one accepted change is deployed and clears its predeclared observation gates. If every challenger loses, the system learned but the baseline did not improve. |

The same experiment, run, task lineage, or duplicate raw fingerprint cannot satisfy more than one
monthly gate. These are initial service-level objectives, not automatic-promotion promises; human
review remains mandatory throughout v1.
