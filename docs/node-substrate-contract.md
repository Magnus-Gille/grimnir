# Node/Substrate contract v1

This is the machine-readable companion to [ADR-007](adr-007-node-substrate-contract.md) and
implements Grimnir #102. It defines four public-safe records:

- `node-capability` — Brokkr's observed, expiring evidence about one node;
- `workload-requirement` — a component owner's portable requirements and declared hooks;
- `placement-intent` — Grimnir's desired placement, without copying observed facts; and
- `lifecycle-result` — one attempt's bound decision evidence and recovery state.

The canonical schema is [`node-substrate-contract-v1.schema.json`](node-substrate-contract-v1.schema.json).
Fixtures, normative-schema validation, and semantic validation live under
[`tests/fixtures/node-substrate-contract`](../tests/fixtures/node-substrate-contract) and
[`tests/scripts/validate-node-substrate-contract.mjs`](../tests/scripts/validate-node-substrate-contract.mjs).

## Compatibility and extensions

Consumers support exactly `v1` in this initial release. An unsupported record version, an unknown
decision-driving value, a stale observation, or a hook/result binding mismatch is invalid for a
decision and must fail closed. `unknown` and `not_applicable` are explicit states; neither is a
positive capability.

Records are closed to accidental new fields. Future producers may put only informational,
versioned entries in `extensions`; an extension cannot silently affect an existing placement
decision. A new decision-driving capability requires a later contract version and explicit
consumer support.

## Bound lifecycle evidence

Every lifecycle result binds `attempt_id`, `plan_id` and digest, desired revision, observation,
action, deadline and idempotency key. Every workload-hook result echoes those values. A repeat
with the same key therefore refers to a recorded result rather than authorizing repeated side
effects. Partial drain enters workload compensation followed by component verification of its
baseline; partial substrate realization carries Brokkr's recorded pre-state evidence and requires
a verified substrate rollback before retry. Both conditions are represented as `blocked`.

The schema and fixtures are an interoperability boundary only. They do not define hook commands,
network locations, credentials, host paths, or any mechanism that can execute a mutation.

The neutral fixture-set manifest identifies a shared input that Brokkr, Hugin, and Mimir can
consume. It does **not** claim that those repositories already implement a consumer; their
adoption is downstream owner work.
