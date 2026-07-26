# ADR-008 — Constitutional, journaled autonomy for Levels 4 and 5

- **Status:** accepted — W0 contract only; globally disarmed
- **Date:** 2026-07-26
- **Decision owner:** Grimnir system architecture
- **Supersedes:** the manual promotion and mandatory-Verdandi-receipt posture only for the two
  bounded classes below. It does not supersede owner control of protected lanes, software change,
  or the historical evidence records in ADR-006 and the recovery convention.

## Context

The operating loop previously described evidence as `promotion-ready` but still required a human
to apply each routing/prompt/harness/roster change. That leaves the system unable to make a
bounded, reversible improvement when the evidence is already sufficient. Conversely, a generic
"auto-approve" switch would let an executor expand its own scope, weaken evidence gates, or turn
an observer/audit sink into an actuator.

The required replacement is a closed constitutional floor, not a looser review policy: every
future mutation must bind the admitted class, finite blast radius, identities, evidence floor,
postconditions, canary, deadline, recovery, and append-only state transition. It must also remain
safe if an executor dies midway, an observer is compromised, a receipt is replayed, or the current
state cannot be established.

## Decision

Mechanical promotion is permitted only when a future owner implementation validates all of this
ADR's v1 artifacts and every class predicate. **W0 is disarmed**: it supplies no executor, policy
service, worker, deployment path, credentials, Heimdall actuator, or Verdandi dependency. A schema
or fixture is not authorization to mutate anything.

### Closed constitution and permanent floors

`autonomy-constitution-v1.schema.json` is closed at every v1 object. Its digest uses the existing
maintenance-policy convention: canonical JSON with lexicographically sorted object keys and the
self-referential digest field omitted (`autonomy-constitution-digest-jcs-v1`). The constitution
contains exactly these mechanically promotable classes:

| Class | Level | Recovery | Permanent bound |
|---|---:|---|---|
| `routing` | L5 | `R-exact` | one canary target, one attempt, finite deadline/watch |
| `no-reboot-security-bugfix-maintenance` | L4 | `R-forward` | non-pillar canary only, no reboot, one target/attempt, finite deadline/watch |

Each class has closed bounds, distinct executor/recovery identities, required postconditions, and
fault-injection requirements. The constitution also requires fail-closed admission, kill switch,
fresh evidence, unique identity, content-blind journaling, observer non-actuation, unknown-state
disarm, and protected-lane non-promotion. A later class or field requires a new constitution
version and owner decision; `extensions` is deliberately empty in v1.

These permanent protected lanes may be proposed but never mechanically promoted: credentials and
authentication; owner policy; constitution/safety gates; deployments/code; privacy/retention/
erasure; firmware; remote recovery; model-weight training; irreversible external actions; and
package downgrade. The coverage registry contains an exact row for every one, so omission cannot
be mistaken for permission.

### Coverage and admission

`autonomy-coverage-registry-v1.schema.json` is also closed and digest-bound
(`autonomy-coverage-registry-digest-jcs-v1`, same canonical convention). It aligns unique domain
rows with the constitution, class level, owner, recovery class, current coverage, and target state.
The only coverage states are `out-of-scope`, `protected`, `shadow`, `armed-canary`, and
`armed-fleet`; target state is distinct from current state. Current W0 has global state `disarmed`
and both autonomous classes at `shadow`, so it cannot claim a canary or fleet admission.

A future controller may admit exactly one class only when global state is armed, that class has the
matching armed coverage, every evidence/risk/canary predicate is fresh and true, the kill switch is
off, and the authoritative domain journal is healthy. Coverage of routing never completes L4
maintenance, and an observer cannot turn shadow evidence into admission.

### Authoritative content-blind journal

Every future admitted mutation has one closed `autonomous-mutation-journal` envelope for one
domain/mutation/attempt/idempotency key. Entries bind the constitution digest, immutable baseline,
postcondition digest, deadline, one-target canary scope/watch deadline, executor identity,
least-privilege recovery identity, risk scope, opaque reference identifiers, and a receipt hash
chain. It intentionally contains no command, path, prompt, payload, secret, or target content;
references are opaque `ref:<id>` handles. Verdict/audit projections may consume it but cannot
replace it.

The state machine is `prepare → apply → verify → watch → commit → disarm` on success, with any
uncertainty taking the fail-closed branch `… → unknown → recover → [quarantine] → disarm`.
Sequence, time, baseline, postcondition, deadline, canary, risk scope, recovery class, and identity
cannot change inside an envelope. Receipts are canonical-digest chained; replay, gap, tamper,
deadline extension, canary expansion, recovery-worker impersonation, and `unknown → apply` are
rejected. Every recovery worker disarms after acting; terminal outcomes are `disarmed` or
`terminally-blocked`, never implicit retry/re-arm.

- **R-exact** restores the immutable recorded baseline and verifies its exact digest. It is the L5
  routing target.
- **R-forward** makes only a predeclared, bounded compensating move to a named safe state. It is
  the L4 maintenance target, requires active quarantine after a breach, and then disarms.

Heimdall is read-only and outside admission, mutation, recovery, rollback, and re-arm. Verdandi is
an optional asynchronous projection: unavailable/rejected Verdandi must not weaken the authoritative
journal or cause an unrecorded mutation. Its separate recovery/purpose gate remains in force.

## Consequences

- Per-change human approval is removed only for a future, armed, fully covered instance of the two
  classes above; all other changes retain owner control.
- The owner retains the kill switch, protected lanes, software-development/PR review authority,
  and recovery/firmware/credential control.
- A controller that sees incomplete, stale, malformed, unknown, or observer-only evidence must
  fail closed and leave/return the class disarmed; it may create a proposal but not a mutation.
- Implementations belong in their owning repositories. W1 proves routing `R-exact`; W2 adds the
  Brokkr journal/recovery seam; W3 may seek one non-pillar L4 canary only after fault injection.
  W4/W5 each require their own review, CI, coverage, and deployment authorization.

## Alternatives considered

1. **Keep human approval for every change.** Rejected for these bounded classes because a verified,
   reversible operating loop would still stall on availability rather than evidence.
2. **Trust a model/controller policy alone.** Rejected: it provides neither a closed scope nor a
   mechanically verifiable recovery path.
3. **Make Verdandi or Heimdall the gate.** Rejected: both are external observer/projection seams;
   a report sink or dashboard must not become an actuator or single admission dependency.
4. **Permit broad unattended maintenance.** Rejected: firmware, reboots, package downgrades,
   credentials, code/deploys, and remote recovery are explicitly protected.

## Verification

`make test-autonomy-contract` runs closed-schema validation plus positive R-exact/R-forward journal
fixtures and adversarial mutations for protected-lane substitution, content injection, chain/timing
identity drift, unknown-state re-arm, canary expansion, recovery-worker impersonation, and disarmed
coverage claiming armed state. `make test-autonomy-contract-doc` retains the public boundary text.

## Follow-up

This ADR does not arm a controller. Each owning implementation must add its own tests and evidence,
then receive independent review and green CI before a separate admissibility decision. Any need to
alter a protected lane, add a class, or weaken a floor requires an owner-approved successor ADR and
a new versioned constitution.
