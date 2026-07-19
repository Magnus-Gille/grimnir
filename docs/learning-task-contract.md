# LearningTaskContract v1

> **Status:** v1 system contract; component adoption is incremental.
> **Contract id:** `grimnir.learning-task/v1`.
> **Schema owner:** Grimnir. Field values remain owned by the producer named below.
> **Review gate:** changes require review by both the Hugin and `gille-inference` owners.

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

A logical learning record has this shape. JSON field names are normative; a component may store a
native representation if its exported projection is lossless.

```json
{
  "contract_version": "grimnir.learning-task/v1",
  "record_id": "producer-scoped immutable id",
  "record_kind": "task-outcome | inference-exposure | capability-evidence | experiment-observation",
  "producer": { "component": "hugin | gille-inference", "schema_version": "component version" },
  "recorded_at": "RFC 3339 timestamp",
  "task": {},
  "execution": {},
  "artifacts": {},
  "outcomes": {},
  "lineage": {},
  "review": {},
  "governance": {}
}
```

Every record MUST contain `contract_version`, `record_id`, `record_kind`, `producer.component`,
`producer.schema_version`, and `recorded_at`. Fields marked required below are required when that
producer knows the fact. A producer MUST use `null` plus a machine-readable reason where the field
is applicable but genuinely unknown; it MUST NOT manufacture a value to make a record look complete.

| Envelope field | Owner | Meaning |
|---|---|---|
| `contract_version` | Grimnir | Version and compatibility semantics of this seam. |
| `record_id`, `record_kind` | Record producer | Immutable producer-scoped identity and declared projection kind. |
| `producer.component`, `producer.schema_version` | Record producer | Component and native schema that supplied the facts. |
| `recorded_at` | Record producer | Time the projection was created; it never replaces source/execution times. |

### Task identity and type assignment — Hugin owned; taxonomy — `gille-inference` owned

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `task.instance_id` | Hugin | yes for task-derived records | Stable Hugin task instance identifier; retries do not mint a new task. |
| `task.source.system` | Hugin | yes | Originating system or channel, such as Broker, Ratatoskr, or Munin. |
| `task.source.id` | Hugin | when available | Stable source-side request/message identifier. |
| `task.source.created_at` | Hugin | yes | Time the source request was created, not terminal update time. |
| `task.submitted_at` | Hugin | yes | Time Hugin accepted the task. |
| `task.task_type.id` | Hugin | yes | Hugin's assignment from the advertised canonical vocabulary; unknown values use its explicit fallback. |
| `task.task_type.taxonomy_id` | `gille-inference` | yes | Canonical taxonomy name advertised to Hugin. |
| `task.task_type.taxonomy_version` | `gille-inference` | yes | Immutable version/digest of that taxonomy. |
| `task.raw_fingerprint.algorithm` | Hugin | yes | Canonical raw-task algorithm; v1 is `trim-utf8-sha256-v1`. |
| `task.raw_fingerprint.sha256` | Hugin | yes | Digest of the raw task before any context/template rendering. |

Hugin MUST preserve the raw task separately from the rendered model prompt. The raw fingerprint is
the cross-client join and freshness key. It MUST NOT be calculated from `## Context`, `## Task`, a
system prompt, chat template, tool description, or any other harness-added bytes.

### Execution and serving identity — split by fact owner

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `execution.attempt_id` | Hugin | yes for attempts | Stable attempt id; retries/recovery semantics are explicit. |
| `execution.started_at`, `execution.ended_at` | Hugin | yes when reached | Actual attempt interval. |
| `execution.runtime_id` | Hugin | yes | Selected macro runtime/node lane. |
| `execution.provider_id` | `gille-inference` for gateway calls; Hugin otherwise | yes | Effective provider that served the call. |
| `execution.model.id` | `gille-inference` for gateway calls; Hugin otherwise | yes | Canonical served model id, never merely the requested alias. |
| `execution.model.artifact_digest` | `gille-inference` for gateway calls; Hugin otherwise | when available | Immutable weights/quantization artifact identity. |
| `execution.model.config_epoch` | `gille-inference` for gateway calls; Hugin otherwise | yes | Version/digest of effective serving configuration. |
| `execution.rendered_prompt.sha256` | Hugin for its task payload; `gille-inference` for gateway serving render | yes for model calls | Digest after that owner's model-facing rendering; distinct from the raw-task digest. |
| `execution.prompt_version` | Hugin | yes | Agent/system prompt version plus digest. |
| `execution.harness_version` | Hugin | yes | Harness identity and immutable configuration digest. |
| `execution.tool_policy_version` | Hugin | yes | Effective tools/permissions policy version. |
| `execution.sampling_version` | `gille-inference` for gateway calls; Hugin otherwise | yes | Effective temperature/top-p/seed/reasoning/output-limit configuration digest. |
| `execution.routing_policy_version` | `gille-inference` for M5 micro-routing; Hugin for macro-routing | yes | Effective routing decision policy; each owner records only its layer. |

For one gateway-backed attempt, Hugin owns the attempt and requested macro route; the M5 gateway
owns the effective provider/model/config/sampling and micro-route. Hugin MUST consume the stamped
effective identity returned by the gateway rather than copying its request as observed truth.

### Artifact bindings — Hugin owned

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `artifacts.inputs[]` | Hugin | when applicable | `{kind, owner, ref, sha256}` for bounded input sets or manifests. |
| `artifacts.output` | Hugin | when produced | Owner-controlled result reference plus content hash. |
| `artifacts.repository.base_commit` | Hugin | for managed-repo attempts | Exact before tree. |
| `artifacts.repository.head_commit` | Hugin | when a head exists | Exact task-branch head. |
| `artifacts.repository.diff_sha256` | Hugin | when a diff exists | Hash of the canonical binary diff. |
| `artifacts.repository.changed_files_ref` | Hugin | when a diff exists | Governed reference to repository-relative file names. |
| `artifacts.publication_ref` | Hugin | when publication was attempted | PR/commit/publish reference; absence is not success. |

Hugin owns the seam binding between its task and these references/hashes; the referenced artifact's
content owner does not change. A consumer validates the hash when dereferencing and records a
contract error on mismatch; it does not silently refresh the hash.

### Outcomes — no cross-owner verdict fabrication

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `outcomes.execution` | Hugin | yes | Lifecycle outcome such as completed, failed, cancelled, timeout, or infrastructure error. |
| `outcomes.repository` | Hugin | for repo tasks | Structured repository result, including no-change and not-finalized states. |
| `outcomes.publication` | Hugin | when applicable | Not attempted, succeeded, failed, or unknown with evidence. |
| `outcomes.product_quality` | Hugin | after review | Quality Receipt rating/disposition; `unrated` is explicit. |
| `outcomes.capability` | `gille-inference` | for capability evidence | Verifier-backed pass/partial/fail/error/unverified plus capability effect. |
| `outcomes.execution_failure_mode` | Hugin | on execution/repository/publication failure | Versioned categorical operational or product failure reason. |
| `outcomes.capability_failure_mode` | `gille-inference` | on capability failure | Versioned categorical verifier/model capability failure reason. |

Execution success does not imply repository success; repository publication does not imply product
quality; product acceptance does not by itself become a model capability verdict. Only
`gille-inference` may apply evidence to the capability ledger, through its defined import/write
contract and evidence policy.

### Verifier, correction, and lineage — Hugin owned except capability grading

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `review.verifier.id` | Hugin for experiment/product grading; `gille-inference` for capability grading | for verified claims | Stable verifier identity. |
| `review.verifier.version` | Hugin for experiment/product grading; `gille-inference` for capability grading | for verified claims | Immutable code/prompt/model digest. |
| `review.rubric.id`, `review.rubric.version` | Hugin for experiment/product grading; `gille-inference` for capability grading | for rated claims | Versioned interpretation policy. |
| `review.reviewer.principal_id` | Hugin | for human review | Authenticated reviewer identity, not free-form display text. |
| `review.reviewed_at` | Hugin | for human review | Receipt time. |
| `lineage.corrects_record_ids[]` | Hugin | when corrective | Records this result supersedes/corrects. |
| `lineage.correction_ref` | Hugin | when content was corrected | Governed reference plus hash; never copied into the seam by default. |
| `lineage.successor_task_ids[]` | Hugin | when follow-up exists | Tasks created to repair or extend this result. |

A judge-only result remains advisory until its declared calibration gate is met. Regrading MUST
append/supersede under a new rubric or policy version; it MUST NOT destructively rewrite history.

### Governance and exposure — origin decision plus gille observation

| Field | Owner | Required | Meaning |
|---|---|---:|---|
| `governance.sensitivity` | Hugin | yes | Effective content sensitivity at task acceptance. |
| `governance.classification_version` | Hugin | yes | Policy that produced the sensitivity. |
| `governance.content_owner` | Hugin | yes | Authority permitted to grant dereference/use. |
| `governance.retention.policy_id`, `expires_at` | Content owner through Hugin | yes | Retention/expiry applied to refs and derived metadata. |
| `governance.erasure.request_id`, `state` | Content owner through Hugin | when applicable | Tombstone propagation state; never restore erased content from a learning copy. |
| `governance.allowed_uses[]` | Content owner through Hugin | yes | For example `operations` or `evaluation`; absence denies use. `training-export` is reserved and rejected throughout v1. |
| `governance.exposure.state` | `gille-inference` | yes for M5 freshness decisions | Seen, unseen-covered, incomplete, error, or not-checked. |
| `governance.exposure.coverage` | `gille-inference` | for negative lookup | Coverage window, lanes, fingerprint version, and completeness. |
| `governance.exposure.first_seen_at`, `last_seen_at` | `gille-inference` | when seen | Gateway observation interval. |

Erasure removes content and dereference capability under the owning policy. Minimal tombstones and
aggregate counters may remain only when `docs/data-lifecycle.md` and the originating policy permit
them. A candidate MUST be excluded when use is not allowed, content has been erased, sensitivity
exceeds the evaluator's ceiling, or freshness coverage is incomplete.

## Decision ownership

| Decision | Sole owner | Consumer obligation |
|---|---|---|
| Task identity, source, task-type assignment, macro runtime, lifecycle, repo/publication/product outcome, correction lineage | Hugin | `gille-inference` imports stamped facts or rejects them; it does not recreate them. |
| Canonical task taxonomy vocabulary and version | `gille-inference` | Hugin consumes the advertised taxonomy, records its assignment, and uses the explicit fallback for unknown values. |
| Raw-task canonical bytes supplied to the seam | Hugin | Gateway verifies supplied fingerprint/version and binds it to exposure. |
| Effective gateway provider/model/artifact/config/sampling, exposure, micro-route, capability verdict | `gille-inference` | Hugin records returned stamps or marks them unavailable; it does not infer them. |
| Prompt/harness/tool-policy experiment design and product gates | Hugin | Gateway supplies exact serving evidence for each arm. |
| Capability-evidence admission and routing-table generation | `gille-inference` | Hugin cannot promote by writing a verdict-like task record. |
| Content use, sensitivity, retention, correction, and erasure authority | Originating content owner, enforced by Hugin | Both components fail closed when the authority is missing. |
| Cross-repo schema, compatibility rules, and status vocabulary | Grimnir | Hugin and `gille-inference` both review changes and implement conforming projections. |
| Deployment of a reviewed prompt, harness, route, roster, or config | Owning repository's human operator | `promotion-ready` is evidence, not deployment authority. |

## Producer/consumer conformance

Each component repository MUST keep a frozen, synthetic, non-sensitive v1 fixture. The two fixtures
MUST represent the same logical task and include both raw and rendered prompt digests.

Required contract tests:

1. Hugin serializes its fixture; the `gille-inference` consumer accepts it without transformation.
2. `gille-inference` serializes exposure and served-model evidence; Hugin accepts and joins it to
   the original `task.instance_id` and `execution.attempt_id`.
3. Both sides independently calculate the same raw-task digest, while a rendered prompt containing
   context/template bytes produces a deliberately different digest.
4. Unknown major version, unknown required enum, missing owner-required field, invalid timestamp,
   hash mismatch, duplicate conflicting `record_id`, or incomplete negative exposure coverage fails
   closed.
5. Unknown optional fields are preserved or ignored without changing known semantics.
6. A correction and an erasure tombstone propagate without copying deleted content.

CI MUST pin the companion fixture revision or fetch an immutable released fixture; it MUST NOT test
only two local mocks of the same assumption. A coordinated contract change is not complete until
both producer and consumer suites pass. Before the implementation tickets are closed, owners of
both Hugin and `gille-inference` MUST review this v1 contract and record acceptance in their PRs.

## Evolution rules

- `contract_version` uses a stable major identifier. A semantic change, field reuse, weakened
  privacy rule, or enum reinterpretation requires `v2` and a parallel migration period.
- Backward-compatible optional fields may be added within v1. They MUST have one owner, an explicit
  null/absence meaning, and fixtures before production use.
- Required fields and enum meanings never change in place. Enum additions are tolerated only where
  the field explicitly defines an unknown/fallback behavior; decision-driving consumers otherwise
  fail closed.
- Records are append-only. Corrections, judge-policy changes, regrading, and erasure use lineage or
  tombstones rather than destructive evidence edits.
- A producer advertises the versions it emits; a consumer advertises the versions it accepts.
  Deployment order is expand consumer → switch producer → retire old reader after the documented
  compatibility window.
- Raw and rendered prompt fingerprint algorithms have separate version fields. Neither may silently
  fall back to the other.

## Adoption state and roadmap

These labels describe mechanisms, not live deployment health:

| Stage | Meaning | Current v1 position |
|---|---|---|
| **Implemented** | Code emits/enforces the evidence in production paths. | Hugin task/result/repository evidence, Quality Receipt mechanism, controlled experiment ledger and daily candidate factory; M5 exposure registry, capability ledger, deterministic verifiers and guarded routing-table generation. Existing schemas are not yet full v1 projections. |
| **Shadow** | Runs and records evidence but cannot change normal routing. | M5 organic harvest/judge and delegate-policy evidence. It remains non-authoritative until representative human calibration passes. |
| **Manual** | A human performs the decision/action. | Product rating, candidate approval, independent-verifier acceptance, challenger deployment, champion pointer advancement, and rollback. |
| **Future** | Specified but not yet an operational path. | Durable all-outcome learning registry, candidate-to-experiment packager, Hugin→M5 verified-evidence import, automated guarded routing reload, and read-only experiment proposals. Model-weight training is outside v1. |

Implementation order is deliberately integrity-first:

1. Land compatible v1 identity/taxonomy projections and the cross-repo fixture tests.
2. Make receipts concurrency-safe and capture corrections/successors.
3. Store all eligible outcomes durably, including failures, no-ops, and publication failures.
4. Package reviewed candidates with just-in-time exposure checks into one-axis experiments.
5. Import verified experiment evidence into the capability ledger and regenerate routing through a
   reviewed deployment/rollback path.
6. Only then add read-only experiment proposals; no automatic mutation is implied.

## Measurable meaning of “continuous”

Grimnir MUST qualify the claim. A timer or growing ledger alone is not a continuous improvement
loop.

| Claim | Rolling evidence required |
|---|---|
| **Continuous capture** | For 30 consecutive days, at least 95% of eligible Hugin attempts produce joinable Hugin and served-model/exposure records within 24 hours; all omissions have explicit reasons and no unresolved contract mismatch is older than 24 hours. |
| **Continuous evaluation** | In every 30-day window containing at least ten eligible tasks, at least one production-derived frozen batch completes independent verification and a one-axis experiment reaches a reviewed disposition. When volume is below ten, report `insufficient-volume`, not success. |
| **Continuous learning** | For three consecutive 30-day windows, the capture and evaluation gates pass and each experiment's result changes durable knowledge: rejected evidence retains the champion plus a next hypothesis, or accepted evidence advances a reviewed prompt/harness/route/roster reference. |
| **Continuously improving baseline** | In addition to continuous learning, at least one accepted change in the last 90 days is deployed, observed for its declared window, clears non-regression/product gates, and has a tested rollback. If every challenger loses, the system is learning but must not claim the baseline improved. |

These are initial service-level objectives, not promises of automatic promotion. The human review
boundary remains in force throughout v1.
