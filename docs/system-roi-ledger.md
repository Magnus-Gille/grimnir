# System ROI ledger v1

> **Status:** accepted template for grimnir#67; it contains no first-month operational claim.

This is the monthly evidence record for Grimnir as a system. It makes the review required by
[`vision.md`](vision.md#system-roi-and-off-ramp) repeatable without turning rough evidence into
accounting-grade precision.

## Start a review

Copy [`system-roi-ledger-template.json`](system-roi-ledger-template.json) to a dated, tracked
ledger file only after the owner has chosen the review month. The template's `unknown` values are
intentional: do not replace them with zeros, extrapolations, or reconstructed activity. Validate a
filled record with `node scripts/validate-system-roi-ledger.mjs path/to/ledger.json`.

Every value carries both an `evidence_status` and `provenance`:

| Status | Meaning | Value rule |
|---|---|---|
| `unknown` | No supplied or inspectable evidence | `null`; provenance says what is missing |
| `estimate` | A bounded owner estimate | value plus an `estimate_method` reference |
| `measured` | A count, duration, spend, or incident from a named record | value plus a `measurement` or `incident_record` reference |

`provenance.reference` is a durable enough pointer for a reviewer to find the source: a report,
receipt, timestamped export, incident record, or owner statement. It must not contain credentials
or private locators.

## What the monthly review records

The template starts with the five deliberately rough system metrics from the adopted roadmap:
operator maintenance minutes, actual frontier spend, quality-adjusted local-inference value,
human time saved, and incidents detected or prevented. Add a metric only when its unit and source
are intelligible to the next reviewer.

For each service actually reviewed, add a `service_decisions` record with exactly one decision:
`keep`, `fix`, `cut`, or `revisit`. A service decision cannot use `unknown` evidence; defer it
instead. The decision evidence must state its concrete use, pillar-protection role, or the problem
to fix. This preserves the vision's two-consecutive-review cut rule rather than silently treating
an unreviewed service as kept.

Set `system_decision` only after the owner review. Its choices are the same four decisions. The
empty template uses `null` plus `unknown`, so it makes no claim that the system should be kept.
When `review_status` is `reviewed`, the system decision must have a non-unknown evidence status,
a compatible provenance source, and a short `rationale`. When it is `not_reviewed`, no service
or substantive system decision is permitted.

## First real ledger: owner inputs needed

For one chosen calendar month, provide:

1. Operator maintenance time, or an estimate method and bounds.
2. Actual frontier-model spend (or a source proving it is unknown).
3. Any M5/local-routing value with the pricing and quality basis; otherwise leave it unknown.
4. Human time saved, with a short estimate method; otherwise leave it unknown.
5. Incident/detection records to count, including the source record for each.
6. Which services were reviewed, each service's use or pillar-protection evidence, and the owner
   decision (`keep`, `fix`, `cut`, or `revisit`).
7. The resulting system-level decision and its rationale.

Until those are supplied, issue #67 remains open: the artifact is ready, but no actual monthly ROI
review has happened.

## Guardrails

[`system-roi-ledger-v1.schema.json`](system-roi-ledger-v1.schema.json) describes the portable
record shape. The dependency-free validator rejects missing provenance, a numeric value marked
`unknown`, incompatible decision provenance, and a decision without evidence or rationale.
`make test-system-roi-ledger` exercises the blank template and adversarial fixtures; `make test`
includes it.
