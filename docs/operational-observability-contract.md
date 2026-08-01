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

All records are closed (`additionalProperties: false` everywhere in the schema). Optional future
information may appear only in informational `extensions`; decision-driving evolution requires a
new major contract version.

## Closed observation states

The closed health states are `ok`, `degraded`, `failed`, `stale`, `unknown`, and `not_applicable`.

- `ok`: the producer observed the declared slot within its freshness window and found no degraded
  or failed condition.
- `degraded`: the slot is operating, but below the declared healthy baseline.
- `failed`: the slot definitively did not satisfy its contract.
- `stale`: the producer has no fresh replacement for an earlier non-negative observation.
- `unknown`: the consumer lacks enough fresh, compatible evidence to classify the slot.
- `not_applicable`: the authoritative expected inventory says the slot is outside scope for this
  service or rollout state.

Missing or expired evidence can never become healthy. A consumer may keep an explicit `failed`,
`degraded`, or `unknown` child as-is, but an expired `ok` can only degrade to `stale`, never stay
green by elapsed time alone.

## Observation shape

Every `service-observation` binds source, service/instance, producer version, attempt ID, observed/collected timestamps, freshness window, outcome, and a content-blind diagnostic ref.

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

## Aggregation truth table

`observation-aggregate` is a projection, not a source of truth. It binds to one explicit expected
inventory with `authority_kind`, `authority_ref`, and `authority_digest`, then references the child
observations it actually consumed. That keeps expected inventory discoverable without making the
aggregate itself a second topology authority.

Absent producers are distinct from `not_applicable`:

- A required slot with no fresh child observation is `unknown`.
- A slot explicitly marked `not_applicable` is excluded from the aggregate.
- An aggregate with only excluded children or an empty expected aggregate is `unknown`.

The v1 truth table is:

1. Start from the authoritative expected slots.
2. Exclude every `not_applicable` slot.
3. For the remaining slots, treat a missing child as `unknown`.
4. Treat an expired `ok` child as `stale`.
5. Reduce with precedence `failed` > `stale` > `unknown` > `degraded` > `ok`.

This makes the fail-closed rule explicit: no `failed`, `stale`, or `unknown` child can be reduced
to `ok`.

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

The safe v1 attribute space is intentionally small: service/instance id echoes, dependency id,
lifecycle outcome, task class, runtime lane, retry ordinal, coarse error class, and check surface.

No prompts, outputs, memory/file contents, Telegram text, accounting data, credentials, private locators, or raw URLs/query strings may enter the serialized/exported envelope.

## Retention, sampling, cardinality, and failure behavior

Tracing/export is incrementally adoptable because `trace-policy` can declare instrumentation and
export both disabled while still fixing the privacy and retention contract.

- Retention is aligned with [`data-lifecycle.md`](data-lifecycle.md) through the
  `ref:data-lifecycle-v1` policy ref and the `operational_telemetry` data class.
- Sampling is explicit (`head`, `rate_per_mille`) rather than implicit backend behavior.
- Cardinality is bounded by the allowlist plus per-policy limits on attribute count and string
  length.
- Export failure is `drop_and_count`; instrumentation failure is `must_not_fail_request`.

These records describe the contract only. They do not create a backend, deletion job, or alert
policy owner.

## Version skew and rollout

Every record carries `contract_version` as `v<major>.<minor>`.

- v1 consumers accept `v1.x` records only when the extra information arrives through
  informational `extensions`.
- Unknown major versions fail visibly.
- Rolling upgrades cannot silently render green: an unsupported major version, a missing required
  slot, or an empty expected aggregate resolves to `unknown`, never `ok`.

This is why v1 is closed to new top-level fields. Safe optional evolution lives in informational
`extensions`; a decision-driving change must bump the major version.

## Fixtures and validation

The canonical schema ships with dependency-free positive, mixed-version, malformed,
privacy-adversarial, stale, missing, and partial fixtures under
`tests/fixtures/operational-observability/`. The validator:

- meta-validates the closed JSON Schema subset it implements;
- recomputes aggregate truth from child observations and expected inventory;
- rejects unsupported major versions and unsafe serialized trace values; and
- proves stale, missing, and partial evidence never renders healthy.

## Out of scope for v1

- Backend deployment, collector rollout, or fleet-wide instrumentation.
- Payload logging, prompt capture, copied stack traces, or generic observability storage.
- Alert-policy ownership, automated remediation, or any claim that traces are learning or audit
  evidence.
- A new topology authority. Expected inventory remains derived from existing authorities and is
  only projected here by ref and digest.
