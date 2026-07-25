# Maintenance-policy contract v1

> **Status:** accepted v1.
> **Contract id:** `grimnir.maintenance-policy/v1`.
> **Machine schema:** [`maintenance-policy-v1.schema.json`](maintenance-policy-v1.schema.json).
> **Tracking issue:** [#134](https://github.com/Magnus-Gille/grimnir/issues/134); parent program
> [#102](https://github.com/Magnus-Gille/grimnir/issues/102); related Brokkr epic
> [brokkr#26](https://github.com/Magnus-Gille/brokkr/issues/26).
> **Fixtures and tests:** [`tests/fixtures/maintenance-policy`](../tests/fixtures/maintenance-policy),
> [`tests/scripts/validate-maintenance-policy-contract.mjs`](../tests/scripts/validate-maintenance-policy-contract.mjs).

## Purpose and boundary

This contract lets Brokkr schedule unattended OS/firmware maintenance (patching, reboots) for one
or more nodes/workloads without confusing three separate fact classes: **desired policy**
(this document), **observed reality** (Brokkr's own evidence, e.g. package/firmware state, disk
space, whether a service is drained), and **execution evidence** (attempt logs, exit codes, applied
package lists — Brokkr/execution-controller internals, not part of this schema). It operates under
the same authority boundary as [ADR-007](adr-007-node-substrate-contract.md): Grimnir/the operator
declares intent, Brokkr observes and executes, and neither side may substitute one for the other.

**This document expresses intent only.** A `maintenance-policy` record is a declaration of what
*should* happen and under what rules — never a live probe result, an eligibility proof, a
credential, a private locator (hostname, IP, path, Wi-Fi identity), a shell command, or
configuration contents. A `maintenance-decision` record is a *bound, mechanical projection* of a
policy against an explicit, opaque Brokkr evidence reference and an explicit evaluation instant —
it is still not a live observation, still not a mutation authorization, and it embeds no raw
observation content (only an `evidence_id`/`digest` pointer, exactly like `node-substrate`'s
`observation_evidence_id` pattern). **Neither record proves eligibility nor authorizes mutation.**
Any executor MUST additionally hold fresh Brokkr observations and pass the execution controller's
own safety gates (drain/verify hooks, substrate preflight, rollback readiness) before touching a
node — this contract cannot and does not substitute for that.

Normative terms **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used as in RFC 2119.

## Record kinds

| `kind` | Produced by | Contains |
|---|---|---|
| `maintenance-policy` | Operator or Grimnir | Declared scheduling/eligibility/safety rules for one or more targets. Pure intent. |
| `maintenance-decision` | Brokkr or an execution controller | A single evaluation of one policy against an explicit `as_of` instant and a bound Brokkr evidence reference — never raw observation content. |

Both kinds are closed records: `additionalProperties: false` at every object level, everywhere in
the schema. An unrecognized field, unrecognized enum value, malformed duration, or unresolvable
IANA timezone **MUST** fail validation. Future producers may add only informational
`extensions.<id>` entries with `decision_effect: "informational"`; an extension can never drive a
decision. A new decision-driving capability requires a new contract version.

## Field ownership

| Field group | Owner | Notes |
|---|---|---|
| `selector` (`node_ids`/`workload_ids`) | Operator/Grimnir | References `services.json` node/workload identity space; the exact same `id` shape as [`node-substrate-contract-v1.schema.json`](node-substrate-contract-v1.schema.json)'s `node_id`/`workload_id`. This contract never queries or infers a selector; it is always explicit. |
| `timezone`, `dst_policy`, `window` | Operator | Declared local scheduling intent. See DST rules below. |
| `missed_window`, `overdue`, `maximum_deferral` | Operator | Declared fallback behavior when the schedule cannot be kept. |
| `state` (`enabled`, `hold`) | Operator | Kill switch and temporary suspension. Always wins over schedule/deferral rules (see decision-effect precedence below). |
| `updates`, `reboot` | Operator | Bounded, closed-enum safety envelope — see "Update classes and sources are closed for safety" below. |
| `execution_limits`, `concurrency`, `failure_limits` | Operator | Bounds the execution controller must respect; it does not itself execute anything through this schema. |
| `policy_digest` | Mechanically derived | See digest definition below. Any producer or consumer can and must recompute it. |
| `evidence` (decision only) | Brokkr | An opaque, content-addressed pointer to Brokkr's own observation record. This schema never embeds what that evidence actually observed. |
| `window_occurrence`, `missed_occurrences`, `deferral_elapsed`, `effect`, `reason` (decision only) | Mechanically derived from the referenced policy plus the bound evidence and `as_of` | See decision-effect rules below. |

## Intent vs. observation vs. evidence

- **Intent** = everything in a `maintenance-policy` record. It never changes because a node happens
  to be reachable or unreachable right now.
- **Observation** = Brokkr's own versioned facts about a node's actual state (package/firmware
  versions, disk space, service health). This contract does not define that schema; it only
  references it by opaque `evidence_id`/`digest`, exactly as `node-substrate-contract-v1`'s
  `lifecycle-result.observation_evidence_id` references Brokkr's `node-capability.evidence`.
- **Execution evidence** = the record of what one maintenance attempt actually did (started/ended,
  packages applied, reboot performed, exit code). Out of scope for v1; it belongs to a future
  Brokkr-owned execution-result contract, symmetrical to `node-substrate`'s `lifecycle-result`.
- **Decision** = the one record kind in this contract that touches evidence, and only by reference.
  A `maintenance-decision` binds a policy digest, an opaque evidence pointer, and an explicit
  `as_of` instant to a mechanically recomputable `effect`/`reason`. It is a projection for planning
  and observability — not an attempt record and not an authorization.

## Update classes and sources are closed for safety

`updates.allowed_classes` is restricted to `security`, `bugfix`, `kernel`, `firmware`.
`updates.allowed_sources` is restricted to `distro_repository`, `package_manager_lts_channel`,
`vendor_signed_firmware_channel`. Feature/major-version upgrades and arbitrary,
unsigned, or ad hoc sources (a raw URL, an unsigned third-party feed, an inline script) are
deliberately **not** in either enum — there is no way to express them in a v1 policy, so any
attempt to declare one is a closed-schema validation failure, not a runtime decision. Widening
either enum requires a new contract version and explicit review, not a documentation change.

## Deterministic policy digest

`policy_digest` uses algorithm **`maintenance-policy-digest-jcs-v1`**:

1. Take the full `maintenance-policy` record and remove the top-level `policy_digest` key. (The
   digest cannot include itself.)
2. Canonicalize the remaining JSON value:
   - Objects: canonicalize as `{` + comma-joined `JSON.stringify(key) + ":" + canonicalize(value)`
     pairs, with keys sorted by **UTF-16 code unit order** (JavaScript's default string sort — the
     same key-ordering rule used elsewhere in this repo's JCS-flavored digests, e.g.
     `docs/learning-task-contract.md`'s `pipeline-event-set-jcs-v1`), applied **recursively** at
     every nesting level.
   - Arrays: canonicalize as `[` + comma-joined canonicalized elements `]`, **preserving element
     order** — array order is semantic (e.g. `days_of_week`, `allowed_classes`) and is never sorted.
   - Strings, integers, and booleans: `JSON.stringify` of the raw value (this contract has no
     floating-point fields, so ECMAScript number/exponent edge cases documented in
     `docs/learning-task-contract.md` do not arise here; a future field that needs a non-integer
     number would need to state its own normalization).
   - No insignificant whitespace anywhere in the output.
   - The whole record is restricted to the closed I-JSON-safe value space this schema already
     enforces (strings, integers, booleans, arrays, objects — no `NaN`/`Infinity`, no lone Unicode
     surrogates); the schema's closed enums and patterns make this a structural guarantee, not a
     separate canonicalizer concern.
3. UTF-8 encode the canonical JSON text and compute SHA-256 over those bytes.
4. Render as `sha256:` followed by 64 lowercase hex characters.

A conforming implementation recomputes this from any semantically-equal JSON regardless of the
original key order — canonicalization is defined precisely enough that two independent
implementations must produce byte-identical digests. `tests/scripts/validate-maintenance-policy-contract.mjs`
proves this by deep-reordering every fixture policy's keys (including nested objects) and asserting
the digest is unchanged, then independently recomputing every digest from scratch.

## Timezone and DST: fail closed, and state the trap explicitly

`timezone` MUST be a real IANA Time Zone Database identifier, or the literal `UTC`. Structural
schema validation only checks the identifier's *shape*; a shape-valid but nonexistent zone (e.g.
`Mars/Colony`) is caught by semantic validation against the runtime's IANA tz database (Node's
built-in `Intl.supportedValuesOf("timeZone")`, which does not itself list a bare `"UTC"` entry — the
validator special-cases `"UTC"` as always valid). An unresolvable timezone **MUST** fail closed.

A `window.start_local_time` is a wall-clock time in that timezone, recurring weekly on
`window.days_of_week`. On a DST transition day, some wall-clock times do not correspond to exactly
one real instant:

- **Nonexistent (spring-forward gap).** When clocks jump forward, a range of wall-clock times is
  skipped entirely. Example: in `Europe/Stockholm`, clocks jump from `02:00` to `03:00` local time
  on the last Sunday of March; `02:00`–`02:59:59` never happens that day. Verified for 2026:
  `2026-03-29T02:30` local does not exist (confirmed by resolving both the pre-transition offset,
  UTC+1/CET, and the post-transition offset, UTC+2/CEST, against the real instant and finding
  neither reconstructs the requested wall clock).
- **Ambiguous (fall-back repeat).** When clocks fall back, a range of wall-clock times happens
  twice. Example: in `Europe/Stockholm`, clocks fall from `03:00` back to `02:00` on the last Sunday
  of October; `02:00`–`02:59:59` occurs once under CEST (UTC+2) and again under CET (UTC+1).
  Verified for 2026: `2026-10-25T02:30` local resolves validly to both `2026-10-25T00:30:00Z`
  (first pass, CEST) and `2026-10-25T01:30:00Z` (second pass, CET).

`dst_policy` makes the contract's behavior for each case an explicit, closed choice — there is no
implicit default:

| Field | Values | Meaning |
|---|---|---|
| `nonexistent_time` | `shift_forward_to_next_valid` \| `skip_occurrence` \| `fail_closed` | `shift_forward_to_next_valid`: resolve to the real instant exactly one transition-gap-length after the nonexistent wall clock (equivalently, the earliest real instant at or after the gap ends). `skip_occurrence` and `fail_closed` both mean **no `maintenance-decision` may exist for that occurrence** — the former because the operator chose to skip it, the latter because ambiguity resolution itself is refused; a producer must not paper over either with a fabricated decision. |
| `ambiguous_time` | `use_first_instant` \| `use_second_instant` \| `fail_closed` | `use_first_instant`/`use_second_instant` pick the earlier or later of the two real instants that read back as the requested wall clock. `fail_closed` again means no decision may exist for that occurrence. |

A `maintenance-decision.window_occurrence.local_time_kind` MUST equal the real classification
(`normal`/`ambiguous`/`nonexistent`) computed from the referenced policy's `timezone` and
`window.start_local_time` against `window_occurrence.local_date` — a producer cannot declare
`"normal"` for an occurrence that is actually ambiguous or nonexistent. When the real classification
is `nonexistent` or `ambiguous` and the policy's matching `dst_policy` field is `fail_closed` (or,
for `nonexistent_time`, `skip_occurrence`), **no decision for that occurrence is valid** — this is
the concrete fail-closed behavior a validator checks, and `tests/fixtures/maintenance-policy/negative.json`'s
`fail_closed_ambiguous_decision` fixture demonstrates it failing for exactly that reason.
`window.duration` is always absolute elapsed time from the resolved `start` instant — it is
deliberately not re-interpreted in local wall-clock terms at the far end, so a DST transition
crossed mid-window never creates a second layer of ambiguity.

`tests/fixtures/maintenance-policy/dst-transition.json` is the required "fixture must cover a real
DST transition" evidence: one policy plus two decisions, one for the verified 2026-03-29
Stockholm spring-forward gap and one for the verified 2026-10-25 Stockholm fall-back overlap.

## Missed-window, overdue, and maximum-deferral decision rules

A `maintenance-decision` binds one policy to one `as_of` evaluation instant, one bound evidence
reference, one scheduled `window_occurrence`, and Brokkr-derived `missed_occurrences` (how many
prior scheduled occurrences elapsed with no completed maintenance, per Brokkr's own attempt
history — an opaque *count*, not raw observation content) and `deferral_elapsed` (elapsed time
since the earliest occurrence in the current unresolved miss streak). `effect`/`reason` are
mechanically derived with this precedence, evaluated top to bottom — the first matching rule wins:

1. `state.enabled == false` → `held` / `disabled`. A disabled policy never schedules anything,
   regardless of anything else.
2. `state.hold.active == true` → `held` / `hold_active`. An operator hold overrides schedule and
   deferral state; it does not accumulate a missed-window count while active.
3. `missed_occurrences == 0` → `on_schedule` / `on_schedule`. Nothing was missed; `deferral_elapsed`
   MUST be `PT0S`.
4. `deferral_elapsed > maximum_deferral.duration` → `escalate_operator_gate` /
   `maximum_deferral_reached`. An absolute ceiling: no matter what `missed_window`/`overdue` say,
   deferral past this bound always escalates to an operator rather than running or waiting silently
   forever.
5. `missed_occurrences >= overdue.after_missed_windows` → apply `overdue.behavior`:
   `escalate_operator_gate` → `escalate_operator_gate` / `overdue_after_missed_windows`;
   `run_as_soon_as_possible` → `run_deferred` / `overdue_after_missed_windows`;
   `hold` → `held` / `overdue_after_missed_windows`.
6. Otherwise, apply `missed_window.behavior`: `run_at_next_window` → `deferred_to_next_window` /
   `missed_window`; `run_as_soon_as_possible` → `run_deferred` / `missed_window`; `skip_occurrence`
   → `skip_occurrence` / `missed_window`.

This precedence is a deliberate design decision, not an emergent property of the schema: disabled
and held states are absolute; the maximum-deferral ceiling is stricter than (and checked before)
the overdue-count threshold, because a policy author might set a generous `overdue.after_missed_windows`
but still want a hard time-based backstop. `tests/scripts/validate-maintenance-policy-contract.mjs`
recomputes this exact rule tree for every fixture decision and for two deliberately wrong
adversarial decisions (`decision_effect_mismatch`, and the DST fail-closed case above).

An `effect` is a stated outcome for downstream planning/observability — it is never itself a
mutation and never bypasses the execution controller's own fresh-observation and safety-gate
requirements described in "Purpose and boundary" above.

## Selector, ordering, and concurrency

`selector.node_ids`/`selector.workload_ids` reference the exact same `id` identity space as
[`node-substrate-contract-v1`](node-substrate-contract-v1.schema.json)'s `node_id`/`workload_id` —
this contract does not mint a competing identity scheme. At least one of the two arrays MUST be
non-empty. `concurrency.ordering: canary_then_remaining` requires `concurrency.canary_count` to be
present and strictly smaller than the total selector target count; any other ordering requires
`canary_count` to be absent (a v1 closed-schema field cannot express "required only sometimes", so
this is enforced by the semantic validator, the same pattern `node-substrate-contract-v1` uses for
its per-hook-name requirements).

## Compatibility with node-substrate-contract v1

This is a new, independent contract file; it does not modify `node-substrate-contract-v1.schema.json`,
its fixtures, or its validator. Compatibility with existing node-substrate v1 consumers was
confirmed by:

1. Leaving every node-substrate-contract file byte-for-byte untouched.
2. Running `make test-node-substrate-contract` after adding this contract and confirming it still
   passes unmodified (10/10 existing hermetic fixture scenarios).
3. Reusing byte-identical `id` (`^[a-z][a-z0-9-]{2,62}$`), `utc` (`format: date-time`), `digest`
   (`^sha256:[a-f0-9]{64}$`), `evidence`, and `extension` shapes, so a `node_id`/`workload_id`
   referenced from a `maintenance-policy.selector` validates under exactly the same constraints a
   node-substrate producer/consumer already expects, and an `evidence` block in a
   `maintenance-decision` is structurally identical to a node-substrate `evidence` block.

## Out of scope for v1

- **Execution.** This contract never runs a command, opens a connection, or authorizes a mutation.
  See "Purpose and boundary".
- **Occurrence-calendar enumeration.** This schema does not itself compute "how many windows have
  been missed since date X" from a recurring schedule; `missed_occurrences`/`deferral_elapsed` are
  explicit, Brokkr-evidence-bound inputs to a decision. A future execution controller that derives
  those counts from raw attempt history is out of scope here, the same way `node-substrate-contract-v1`
  does not itself compute node health from raw metrics.
- **Calendar year/month durations.** The `duration` type is bounded to day/hour/minute/second
  components; `P1Y`/`P1M` are rejected because a "month" or "year" is not an absolute duration
  (its length depends on which month/year), which would make the digest and deferral math
  ambiguous. A future version that needs true calendar-relative recurrence must define that
  separately.
- **Feature/major-version updates and unsigned/ad hoc sources.** Deliberately excluded from the
  closed `updates` enums; see "Update classes and sources are closed for safety".
- **Execution-result/attempt evidence.** Symmetrical to `node-substrate-contract-v1`'s
  `lifecycle-result`; a future Brokkr-owned contract, not this one.
- **A machine-readable cross-repo consumer-fixture manifest** (the `consumer-fixture-set.json`
  pattern from `node-substrate-contract-v1`). Brokkr is the anticipated first consumer; that
  manifest is deferred until a second real consumer exists, to avoid asserting adoption that has
  not happened yet.
