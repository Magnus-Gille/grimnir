# Operational-observability contract v1

> **Status:** accepted v1.
> **Contract id:** `grimnir.operational-observability/v1`.
> **Machine schema:** [`operational-observability-v1.schema.json`](operational-observability-v1.schema.json).
> **Tracking issue:** [#183](https://github.com/Magnus-Gille/grimnir/issues/183).
> **Fixtures and tests:** [`tests/fixtures/operational-observability`](../tests/fixtures/operational-observability),
> [`tests/scripts/validate-operational-observability-contract.mjs`](../tests/scripts/validate-operational-observability-contract.mjs).

## Purpose and boundary

This contract defines content-blind operational health and trace records for Grimnir's
service-operability plane. It covers probe truth, expected inventory, trace correlation, privacy,
retention class, and producer/consumer rollout rules without creating a new authority for
topology, task/product quality, capability, or consequential-mutation audit.

The wider separation of telemetry planes remains normative in
[`observability-and-improvement.md`](observability-and-improvement.md): operational telemetry is
separate from Hugin task/product evidence, `gille-inference` capability evidence, and any future
Verdandi receipt. This document fixes the record shape for the operational plane only.

Normative terms **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used as in RFC 2119.

## Record kinds

| `kind` | Producer | Purpose |
|---|---|---|
| `service-observation` | Owning service, systemd-adjacent collector, substrate observer, or synthetic producer | One liveness/readiness/dependency outcome for one declared slot. |
| `observation-aggregate` | Read-only consumer such as Heimdall | A derived, fail-closed health projection bound to explicit expected inventory. |
| `trace-policy` | Owning service or runtime | Declared tracing/export posture, privacy allowlist, retention class, and failure behavior. |
| `trace-span` | Owning service or synthetic journey | One serialized/export-ready W3C-correlated diagnostic span that has already passed the allowlist gate. |

All records are closed (`additionalProperties: false` everywhere in the schema). Safe optional
evolution is limited to informational `extensions`, and v1 `extensions` are marker-only descriptors
with no payload fields. A decision-driving capability requires a new major contract version.

## Closed observation states

The closed health states are `ok`, `degraded`, `failed`, `stale`, `unknown`, and `not_applicable`.

- `ok`: the producer observed the declared slot within its effective freshness window and found no
  degraded or failed condition.
- `degraded`: the slot is operating, but below the declared healthy baseline.
- `failed`: the slot definitively did not satisfy its contract.
- `stale`: the producer has no fresh replacement for an earlier non-negative observation.
- `unknown`: the consumer lacks enough fresh, compatible evidence to classify the slot.
- `not_applicable`: the authoritative expected inventory says the slot is outside scope for this
  service or rollout state.

Missing or expired evidence can never become healthy. An expired `ok` or `degraded` observation
becomes `stale`; an explicit `failed` observation stays `failed`; an existing `unknown` stays
`unknown`.

## Observation shape

Every `service-observation` binds source, service/instance, producer version, attempt ID,
observed/collected timestamps, freshness window, outcome, and a content-blind diagnostic ref.

- `source` identifies the producing surface (`service_internal`, `service_probe`, `systemd`,
  `substrate`, `synthetic`, or `aggregator`) plus the producer id and producer version.
- `service` identifies one service and one instance, using the existing registry/component identity
  space rather than inventing another naming scheme.
- `slot_id` identifies one expected probe slot, so an aggregate can distinguish "never observed"
  from "not applicable".
- `check.surface` is one of `liveness`, `readiness`, and `dependency`.
  `dependency_service_id` is required only for `dependency`.
- `diagnostic_ref` is an opaque `ref:...` pointer. It is never a file path, prompt, stack trace,
  raw URL, or copied payload.

The semantic meaning of the surfaces is fixed even though endpoint spelling is not:

- `liveness` means the producer could still make progress on its own basic loop.
- `readiness` means the producer judged itself safe to serve the declared role.
- `dependency` means a required peer or substrate dependency was checked explicitly and named.

## Expected inventory, ownership, and digests

`observation-aggregate` is a projection, not a source of truth. It carries:

- an `authorities` array that binds every contributing expected-slot authority with
  `authority_kind`, `authority_ref`, and `authority_digest`;
- an `expected_slots` array that says which slots are required vs `not_applicable`;
- explicit slot ownership through `owner_kind` and `owner_service_id`; and
- a consumer-owned `max_freshness` cap on every slot.

The v1 authority kinds are closed:

- `services_json`: Grimnir's authoritative component inventory contributes the baseline
  `service-live` and `service-ready` slots. The slot applicability derives mechanically from the
  component's `desired_runtime_state` (`active` => `required`; `stopped`/`not-applicable` =>
  `not_applicable`).
- `producer_contract`: the subject service contributes producer-owned dependency and exporter slots,
  such as `dependency_health` and `exporter_health`.
- `consumer_contract`: the read-only consumer contributes consumer-owned meta-observation slots,
  presently `collector_health`.

The owner split is explicit and usable by Heimdall and Brokkr:

- producer-owned slots describe facts the subject service or its adjacent producer-side observer
  owns;
- consumer-owned slots describe the observer's own ability to collect/render the aggregate; and
- `max_freshness` is always consumer-owned, even when the slot's health fact is producer-owned.

`max_freshness` is bounded: it MUST be positive and MUST NOT exceed `P1D`. Effective freshness is
the stricter of the producer's `freshness_window` and the consumer's `max_freshness`.

### Canonical `authority_digest`

Each `authority_digest` uses algorithm **`operational-observability-authority-jcs-v1`**:

1. Take one authority binding's `authority_kind` and `authority_ref`.
2. Collect only the `expected_slots` allocated by that authority kind.
3. Remove `max_freshness` from each slot because it is consumer-owned freshness policy, not
   authority-owned slot allocation.
4. Canonicalize the resulting JSON value recursively:
   - objects: `{` + comma-joined `JSON.stringify(key) + ":" + canonicalize(value)` pairs, with keys
     sorted by UTF-16 code unit order;
   - arrays: `[` + comma-joined canonicalized elements `]`, preserving element order after the
     authority-kind slot ordering rule is applied;
   - strings, booleans, and integers: `JSON.stringify(value)`;
   - no insignificant whitespace anywhere.
5. UTF-8 encode the canonical JSON text and compute SHA-256 over those bytes.
6. Render as `sha256:` followed by 64 lowercase hex characters.

The canonical slot ordering is authority-local:

- `services_json`: `service_liveness`, then `service_readiness`.
- `producer_contract`: `dependency_health` then `exporter_health`, with ties broken by `slot_id`.
- `consumer_contract`: `collector_health`, with ties broken by `slot_id`.

`tests/fixtures/operational-observability/inventory-derivation.json` is the recomputable fixture
for this rule set: it includes authoritative projections for `services_json`, `producer_contract`,
and `consumer_contract`, and the validator recomputes every digest from scratch.

## Aggregation truth table

Absent producers are distinct from `not_applicable`:

- A required slot with no fresh child observation is `unknown`.
- A slot explicitly marked `not_applicable` is excluded from the aggregate.
- An aggregate with only excluded children or an empty expected aggregate is `unknown`.

The v1 truth table is:

1. Start from the authoritative expected slots.
2. Exclude every `not_applicable` slot.
3. For the remaining slots, treat a missing child as `unknown`.
4. Expire an `ok` or `degraded` child to `stale` when the stricter producer/consumer freshness
   window has elapsed. Preserve an explicit `failed` child as `failed`.
5. Reduce with precedence `failed` > `stale` > `unknown` > `degraded` > `ok`.

This makes the fail-closed rule explicit: no `failed`, `stale`, or `unknown` child can be reduced
to `ok`. Stale, missing, and partial evidence never renders healthy.

Every `service_overall` aggregate MUST include one required consumer-owned `collector_health` slot.
If the bound service `trace-policy` has `export_enabled: true`, the aggregate MUST also include one
required producer-owned `exporter_health` slot. This is the v1 meta-observation floor: a service
must not appear healthy while the consumer cannot collect it or while the producer has declared
export on but cannot keep that export path healthy.

Render-time expiry also fails closed: once an aggregate's own `fresh_until` is in the past, a
rendered `ok` or `degraded` aggregate becomes `stale`. A rendered `failed` aggregate stays
`failed`.

## Trace context and privacy

`trace-span` uses W3C trace context: `trace_id` is 32 lowercase hex characters and `span_id` is 16
lowercase hex characters. Trace IDs are diagnostic joins only; they do not move authority away
from Hugin, `gille-inference`, Munin, Verdandi, Brokkr, Grimnir, or any service that already owns
the underlying fact.

The serialized/exported trace envelope is deny-by-default:

- only allowlisted attributes may appear;
- every record stays content-blind and low-cardinality;
- informational `extensions` cannot drive a health or routing verdict; and
- automatic instrumentation is disabled by default until its exported envelope passes the same
  privacy-adversarial fixture set as manual spans.

The safe v1 attribute space is intentionally small: service/instance echoes, dependency id, task
class, runtime lane, retry ordinal, coarse error class, and check surface. Spans MUST NOT carry a
`lifecycle_outcome` or any equivalent field that would let traces become an alternate health-truth
path; observations and aggregates remain the only health-verdict records.

No prompts, outputs, memory/file contents, Telegram text, accounting data, credentials, private
locators, or raw URLs/query strings may enter the serialized/exported envelope. Free-form token
fields such as `producer_version` and `error_class` are schema-bounded safe tokens so schema-only
consumers cannot admit tokenized URLs.

`service-observation.trace` and `observation-aggregate.trace` are observation links only. They MUST
resolve to an emitted `trace-span`; they do not let traces overwrite the observation's owned fact.

## Trace policy, sampling, and parentage

`trace-policy` is bound to one service identity: `source.producer` MUST equal
`trace-policy.service.service_id`, and any `trace-span` that cites the policy MUST bind the same
service and instance as that policy.

Tracing/export is incrementally adoptable because `trace-policy` can declare instrumentation and
export both disabled while still fixing the privacy and retention contract. The behavior is strict:

- if `instrumentation_enabled` is `false`, `export_enabled` MUST be `false`,
  `automatic_instrumentation` MUST be `disabled`, and `rate_per_mille` MUST be `0`;
- if `export_enabled` is `false`, `rate_per_mille` MUST be `0`; and
- when instrumentation/export is disabled or `rate_per_mille` is `0`, no `trace-span` record may
  cite that policy.

Parent/child spans are allowed across services inside the same W3C trace, and the fixtures include
a two-service Hugin → Munin example. Self-parenting is forbidden, and a declared parent span must
exist in the same trace.

## Retention, sampling, cardinality, and failure behavior

- Retention is aligned with [`data-lifecycle.md`](data-lifecycle.md) through the
  `ref:data-lifecycle-v1` policy ref and the `operational_telemetry` data class.
- Sampling is explicit (`head`, `rate_per_mille`) rather than implicit backend behavior.
- Cardinality is bounded by the allowlist plus per-policy limits on attribute count and string
  length.
- Export failure is `drop_and_count`; instrumentation failure is `must_not_fail_request`.

These records describe the contract only. They do not create a backend, deletion job, or alert
policy owner.

## Version skew and rollout

Every v1 record carries `contract_version` as `v1.<minor>`, and the published schema enforces that
constraint directly.

- v1 consumers accept `v1.x` records only when the extra information arrives through
  informational `extensions`.
- Unknown major versions fail visibly at ingestion.
- A required slot whose unsupported-major child was rejected resolves `unknown` in the aggregate,
  rather than aborting the aggregate or rendering green.
- Rolling upgrades cannot silently render green: an unsupported major version, a missing required
  slot, or an empty expected aggregate resolves to `unknown`, never `ok`.

This is why v1 is closed to new top-level fields. Safe optional evolution lives in informational
`extensions`; a decision-driving change must bump the major version.

## Fixtures and validation

The canonical schema ships with dependency-free positive, mixed-version, malformed,
privacy-adversarial, stale, missing, partial, unsupported-major, and parent-child trace fixtures
under `tests/fixtures/operational-observability/`. The validator:

- meta-validates the closed JSON Schema subset it implements;
- recomputes `authority_digest` and proves the expected-inventory derivation rules;
- recomputes aggregate truth from child observations and expected inventory;
- rejects unsupported major versions and unsafe serialized trace values; and
- proves stale, missing, and partial evidence never renders healthy.

## Out of scope for v1

- Backend deployment, collector rollout, or fleet-wide instrumentation.
- Payload logging, prompt capture, copied stack traces, or generic observability storage.
- Alert-policy ownership, automated remediation, or any claim that traces are learning or audit
  evidence.
- A new topology authority. Expected inventory remains derived from existing authorities and is
  only projected here through closed, digest-bound slot allocations.
