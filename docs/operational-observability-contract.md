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

Every v1 timestamp field MUST be a real whole-second UTC instant encoded as
`YYYY-MM-DDTHH:MM:SSZ`. Offsets and fractional seconds are rejected by both the schema and the
runtime validator so every freshness comparison uses one exact wire format.

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
  component's `desired_runtime_state`. When `desired_runtime_state` is absent, consumers MUST treat
  it as `active`, so the slot remains `required`. The full rule is `active` or absent =>
  `required`; `stopped`/`not-applicable` => `not_applicable`.
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

For `producer_contract` and `consumer_contract`, v1 `authority_ref` MUST resolve through a
versioned external authority registry or derivation input that is not authored inside the aggregate
record itself, and that selector MUST name a versioned external contract or observer artifact. The
validator's canonical input is `tests/fixtures/operational-observability/inventory-derivation.json`;
a production consumer needs an equivalent external selector. `authority_digest` is computed over
the externally selected slot projection after removing consumer-owned `max_freshness`, not over an
arbitrary projection embedded only in the aggregate. Unknown refs or mismatched projections fail closed.
Full cross-document byte binding is a future major-version change.

### Canonical `authority_digest`

Each `authority_digest` uses algorithm **`operational-observability-authority-jcs-v1`**:

1. Take one authority binding's `authority_kind` and `authority_ref`.
2. Collect only the `expected_slots` allocated by that authority kind.
3. Remove `max_freshness` from each slot because it is consumer-owned freshness policy, not
   authority-owned slot allocation.
4. Build exactly this canonical object, with no additional fields:

   ```json
   {
     "authority_kind": "services_json | producer_contract | consumer_contract",
     "authority_ref": "ref:...",
     "expected_slots": [
       {
         "slot_id": "...",
         "authority_kind": "...",
         "slot_class": "...",
         "surface": "...",
         "applicability": "...",
         "owner_kind": "...",
         "owner_service_id": "...",
         "dependency_service_id": "..."
       }
     ]
   }
   ```

   `dependency_service_id` appears only for `dependency_health` slots, exactly as in the slot
   projection. `max_freshness` never appears inside the digested object.
5. Canonicalize the resulting JSON value recursively:
   - objects: `{` + comma-joined `JSON.stringify(key) + ":" + canonicalize(value)` pairs, with keys
     sorted by raw UTF-16 code unit order;
   - arrays: `[` + comma-joined canonicalized elements `]`, preserving element order after the
     authority-kind slot ordering rule is applied;
   - strings, booleans, and integers: `JSON.stringify(value)`;
   - no insignificant whitespace anywhere.
6. UTF-8 encode the canonical JSON text and compute SHA-256 over those bytes.
7. Render as `sha256:` followed by 64 lowercase hex characters.

The canonical slot ordering is field-based and locale-free. Compare:

1. slot-class rank: `service_liveness`, `service_readiness`, `dependency_health`,
   `exporter_health`, `collector_health`;
2. `surface`;
3. `applicability`;
4. `owner_kind`;
5. `owner_service_id`;
6. `dependency_service_id`, treating absence as the empty string; and
7. `slot_id`.

Every string comparison in that tuple uses raw UTF-16 code unit order. No concatenated sort key and
no locale-sensitive comparison is allowed.

`tests/fixtures/operational-observability/inventory-derivation.json` is the recomputable fixture
for this rule set: it includes authoritative projections for `services_json`, `producer_contract`,
and `consumer_contract`, including prefix-related dependency ids, and the validator recomputes every
digest from scratch while binding producer/consumer refs through that external fixture input.

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

An aggregate that would otherwise still be `ok` or `degraded` MUST NOT advertise a `fresh_until`
beyond the earliest effective child `fresh_until` after the stricter producer/consumer freshness
cap is applied. Aggregate render-time health cannot outlive any contributing child.

Every `service_overall`, `liveness`, and `readiness` aggregate MUST bind `services_json` authority
and carry the complete mechanically derived registry slot set for that surface:

- `service_overall`: `service-live` plus `service-ready`
- `liveness`: `service-live`
- `readiness`: `service-ready`

No collector-only or exporter-only inventory may validate green for those aggregate surfaces.
`liveness` and `readiness` aggregates may not carry any additional producer or consumer slots
beyond that mechanically derived registry surface set.

Every `service_overall` aggregate MUST include one required consumer-owned `collector_health` slot
and MUST bind exactly one `trace-policy` record for the same service and instance. It MUST also
declare exactly one producer-owned `exporter_health` slot:

- if the bound policy has `export_enabled: true` and `rate_per_mille > 0`, that slot MUST be
  `required`;
- otherwise it MUST be `not_applicable`.

This is the v1 meta-observation floor: a service must not appear healthy while the consumer cannot
collect it, while the producer has declared export on but cannot keep that export path healthy, or
while export omission is being hidden by a missing policy record.

Aggregate clocks are monotonic over their accepted children: `observed_at` and `collected_at` MUST
each be greater than or equal to every referenced child `observed_at` and `collected_at` instant.
An aggregate is not allowed to backdate itself relative to accepted child evidence.

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
consumers cannot admit tokenized URLs. Private IPv4 and IPv6 literals are private locators for this
contract and MUST be rejected even when they fit the safe-token grammar. That rejection explicitly
includes expanded IPv6 loopback spellings such as `0:0:0:0:0:0:0:1`, IPv4-mapped private IPv6
forms, CGNAT `100.64.0.0/10`, and `0.0.0.0`.

`service-observation.trace` and `observation-aggregate.trace` are observation links only. They MUST
resolve to an emitted `trace-span` for the same `service_id` and `instance_id`; they do not let
traces overwrite the observation's owned fact. Cross-service trace structure is allowed only
through `trace-span.parent_span_id`, not through observation trace links.

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

In other words, a disabled or zero-rate `trace-policy` is the explicit v1 model for “no exported
traces right now”. `service_overall` aggregates may rely on that explicit disabled state; they may
not omit the policy record entirely.

Parent/child spans are allowed across services inside the same W3C trace, and the fixtures include
a two-service Hugin → Munin example. Self-parenting is forbidden, and a declared parent span must
exist in the same trace. This is compatible with the stricter observation-link rule above: spans may
cross services, but `service-observation.trace` and `observation-aggregate.trace` may not.

## Retention, sampling, cardinality, and failure behavior

- Retention is aligned with [`data-lifecycle.md`](data-lifecycle.md) through the
  `ref:data-lifecycle-v1` policy ref and the `operational_telemetry` data class. The authoritative
  lifecycle table includes an `Operational telemetry` row with a six-month provisional default.
- Sampling is explicit (`head`, `rate_per_mille`) rather than implicit backend behavior.
- Every emitted v1 `trace-span` is `sampled: true`; disabled or unsampled export is represented by
  policy state plus span absence, not by serializing `sampled: false`.
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
