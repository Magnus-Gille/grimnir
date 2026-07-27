# ADR-008 — Constitutional, journaled autonomy for Levels 4 and 5

- **Status:** accepted — W0.2 v2 contract; globally disarmed
- **Date:** 2026-07-27
- **Decision owner:** Grimnir system architecture
- **Supersedes:** the manual promotion and mandatory-Verdandi-receipt posture only for the seven
  bounded ADR-008 classes below. It does not supersede owner control of protected lanes, software change,
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

Review of the first W1/W2/W4 adapters found that v1's 3600-second total
deadline and 3600-second watch left no protected-clock time for apply,
readback, verification, or commit scheduling. V1 could pass frozen-clock tests
while no real successful attempt was reachable. V2 is the owner-approved
successor timing epoch; v1 remains immutable historical evidence.

## Decision

Mechanical promotion is permitted only when a future owner implementation validates all of this
ADR's v2 artifacts and every class predicate. **W0.2 is disarmed**: it supplies no executor, policy
service, worker, deployment path, credentials, Heimdall actuator, or Verdandi dependency. A schema
or fixture is not authorization to mutate anything.

### Closed constitution and permanent floors

`autonomy-constitution-v2.schema.json` is closed at every v2 object. Its digest uses the existing
maintenance-policy convention: canonical JSON with lexicographically sorted object keys and the
self-referential digest field omitted (`autonomy-constitution-digest-jcs-v1`; the canonicalization
algorithm is stable across contract epochs). The constitution
contains exactly these mechanically promotable classes:

| Class | Required for | Owner scope | Recovery | Permanent bound |
|---|---|---|---|---|
| `micro-routing` | L4 + L5 | fixed: `gille-inference` | `R-exact` | one target/attempt; 300/3600/300/4200 timing |
| `macro-routing` | L5 | fixed: `hugin` | `R-exact` | one target/attempt; 300/3600/300/4200 timing |
| `prompt` | L5 | owning component | `R-exact` | one target/attempt; 300/3600/300/4200 timing |
| `harness` | L5 | owning component | `R-exact` | one target/attempt; 300/3600/300/4200 timing |
| `tool-policy` | L5 | owning component | `R-exact` | one target/attempt; 300/3600/300/4200 timing |
| `served-model-roster` | L5 | fixed: `gille-inference` | `R-exact` | one target/attempt; 300/3600/300/4200 timing |
| `no-reboot-security-bugfix-maintenance` | L4 | fixed: `brokkr` | `R-forward` | non-pillar, no reboot; 300/3600/300/4200 timing |

The four timing values are, respectively: maximum prepare-through-durable-watch
receipt budget, minimum post-receipt watch, maximum commit grace, and maximum
total attempt duration, all in seconds and measured with protected watchdog
time.

#### Epoch provenance

| Epoch | Constitution ID / digest | Coverage registry / digest | Journal |
|---|---|---|---|
| historical v1 | `grimnir-autonomy-v1` / `sha256:51efdb78c4524780919649f285862543db8b38a6a3a07894f0fad8bdab40fc6c` | `grimnir-autonomy-coverage` / `sha256:379b4d274d93d7c6bd0eda88fd24c35977511565c13967e5467174354286cd90` | `autonomous-mutation-journal-v1`, historical attempts only |
| current W0.2 v2 | `grimnir-autonomy-v2` / `sha256:836aba8abbc48e05294dac301354ec6b1aa21307b992db78202342ce29aa8dc1` | `grimnir-autonomy-coverage-v2` / `sha256:b7303c8f02b03b7330a0fc49cd685428a28ddd2d6306e0c47a7fd24e5c0c3cbd` | `autonomous-mutation-journal-v2`, new attempts after separate arming only |

The synthetic armed-canary v2 fixture has registry digest
`sha256:24c6b51064797b4434b5d1b11b0d7dd22a9dc5eec4dd8ef40ab79d9d5b9f1863`;
it is test provenance, never production authority. The v1 files and validator
are preserved byte-for-byte.

Each class has closed bounds and requires distinct owner, controller, watchdog, kill-switch, and
recovery-worker identities. Concrete identities, writer owner, authority reference plus digest,
and target scope live in the owner-controlled coverage registry rather than becoming fleet-wide
authority merely because a class exists. Prompt, harness, and tool-policy bindings therefore belong to the
component that owns the affected configuration. Hugin may apply a Hugin-owned binding, but for
another component it remains proposal-only and holds no target credentials. Adding or changing a
binding is itself a permanent protected-lane owner decision. The authority reference is accepted
only when its digest matches the target owner's separately reviewed attestation; a component name
in a proposal is not ownership proof. `autonomy-owner-attestation-registry-v1.json` is that
independent root: it binds one class and target-scope digest to one configuration owner, is itself
closed and digest-bound, and can be widened only through the permanent owner-controlled lane.
Coverage admission resolves the attestation ID and digest against that artifact rather than against
fields copied from the proposal. A bound recovery worker may only
monotonically narrow its exact binding from armed to shadow/disarmed; it cannot add a binding,
change scope, widen coverage, or re-arm. That narrow exception is what makes automatic rollback
possible without turning recovery into a policy writer.

Success postconditions are separate from recovery postconditions: a healthy commit verifies the
candidate and completes its canary watch without asserting rollback or disarm. Recovery asserts
either exact baseline restoration or the predeclared safe state, followed by recovery-worker
disarm. The constitution also requires fail-closed admission, kill switch, fresh evidence, unique
identity, content-blind journaling, observer non-actuation, unknown-state disarm, success-state
arming preservation, and protected-lane non-promotion. A later class or field requires a new
constitution version and owner decision; `extensions` is deliberately empty in v2.

These permanent protected lanes may be proposed but never mechanically promoted: credentials and
authentication; owner policy; constitution/safety gates; deployments/code; privacy/retention/
erasure; firmware; remote recovery; model-weight training; irreversible external actions; and
package downgrade. The coverage registry contains an exact row for every one, so omission cannot
be mistaken for permission.

### Coverage and admission

W0.1 adds an authentication floor to this integrity contract. A controller
must verify a detached Ed25519 owner authorization with an **independently
pinned** owner public key (not merely the editable key bundled in a manifest).
That authorization binds exact canonical digests for the production
constitution, owner arming/coverage intent, configuration-owner attestations,
and recovery-worker verification-key registry. The owner's private key remains
outside Git. The checked-in production authorization is deliberately
unconfigured and cannot admit anything. Key rotation or revocation is a new,
owner-signed successor authorization in the permanent owner-policy lane.

Runtime demotion is separate from owner intent: an append-only narrowing ledger
can only record an exact `armed-canary|armed-fleet → shadow` transition. Each
entry is signed by the recovery worker's key that the owner-bound registry
assigns to that precise domain and target scope. A controller identity string,
digest rewrite, or replacement recovery registry is therefore insufficient to
impersonate recovery.

`autonomy-coverage-registry-v2.schema.json` is also closed and digest-bound
(`autonomy-coverage-registry-digest-jcs-v1`, same canonical convention). It aligns unique domain
rows with the constitution, required levels, owner scope, recovery class, current coverage, target
state, and zero or more concrete owner bindings.
The only coverage states are `out-of-scope`, `protected`, `shadow`, `armed-canary`, and
`armed-fleet`; target state is distinct from current state. Current W0.2 has global state `disarmed`
and all seven autonomous classes at `shadow`, so it cannot claim a canary or fleet admission.

A future controller may admit exactly one class only when global state is armed, that class and
the exact concrete owner/target binding both have matching armed coverage, the controller identity
and writer owner match that binding, every evidence/risk/canary predicate is fresh and true, the
kill switch is off, and the authoritative domain journal is healthy. Level 4 requires both the
micro-routing configuration plane and no-reboot maintenance; Level 5 additionally requires the
remaining five R-exact classes. An observer cannot turn shadow evidence into admission.
Individual class admission and aggregate level readiness are separate predicates: arming or
mutating one class cannot claim L4/L5 completion. `required_for_levels` controls the system maturity
label, not whether an independently owner-approved class may run its staged canary; otherwise W1
could not prove micro-routing before W2 proves maintenance. The conformance validator computes the
aggregate reporting gate from every class at or below the claimed level, and separately proves that
a partial class canary does not promote the system maturity label.

### Authoritative content-blind journal

Every future admitted mutation has one closed `autonomous-mutation-journal` envelope for one
domain/mutation/attempt/idempotency key. Its immutable binding carries the candidate, configuration,
evidence, policy, baseline, postcondition, deadline, canary, recovery, admitted coverage digest and
binding state, owner attestation, and all five authority identities. Every entry receipt binds that
immutable binding and opaque reference identifiers. It
intentionally contains no command, path, prompt, payload, secret, or target content; references are
opaque `ref:<id>` handles. Verdict/audit projections may consume it but cannot replace it.

The success state machine is `prepare → apply → verify → watch → commit`. `commit` terminates that
one attempt while leaving the separately controlled class/coverage arming unchanged, so later
qualifying evidence can start another bounded attempt. Any uncertainty takes a fail-closed recovery
branch: **R-exact** is `… → unknown → revert/reverted → disarm`; **R-forward** is
`… → unknown → recover/recovered → quarantine → disarm`. If recovery cannot establish its required
postconditions, the recovery worker records a reason-bound `terminally-blocked` state. Both
`disarm` and `terminally-blocked` mean the class cannot re-arm mechanically. Candidate/config/evidence/
policy identity, baseline, postconditions, deadline, canary, recovery class, and authority identity
cannot change inside an envelope. V2 does not prebind a `watch_deadline`.
Prepare, apply, candidate readback, verification, and an authenticated durable
watch receipt must complete within 300 seconds. Only after the append boundary
authenticates the bound controller, persists and reads back the chained receipt,
and verifies protected watchdog time does the 3600-second post-mutation watch
begin. The earliest valid commit is derived from that receipt timestamp; commit
has at most 300 seconds of grace. Every success-path mutation phase and the
immutable deadline stay within 4200 seconds of prepare. No mutation phase may be recorded after its deadline; detection,
revert/recovery, quarantine, recovery-worker disarm, and terminal blocking may occur after it. The
commit cannot precede the complete watch window. Receipts are canonical-digest
chained; replay, gap, tamper, deadline extension, canary expansion, recovery-worker impersonation,
and `unknown → apply` are rejected. Recovery never retries or re-arms.

Every `disarm` or `terminally-blocked` receipt also binds the prior armed state, the exact target
scope, the recovery-worker identity, and the only permitted destination (`shadow`). Non-terminal
entries must carry no coverage transition. The journal therefore proves the narrow recovery
exception mechanically instead of trusting a policy label: a recovery worker cannot widen,
re-arm, demote another target, or forge an owner's coverage change.

The positive journal fixtures bind a checked-in synthetic armed-canary coverage snapshot and are
validated against its exact canonical digest and binding state. That file is test data, not a
deployment or authority surface. The production registry in `docs/` remains globally disarmed and
all of its bindings remain `shadow`.

- **R-exact** restores the immutable recorded baseline and verifies its exact digest. It applies to
  all six routing/configuration classes above; micro-routing contributes to both L4 and L5.
- **R-forward** makes only a predeclared, bounded compensating move to a named safe state. It is
  the L4 maintenance target, requires active quarantine after a breach, and then disarms.

For these ADR-008 classes only, the domain journal is authoritative and Verdandi is an optional
asynchronous projection: unavailable/rejected Verdandi must not weaken the journal or cause an
unrecorded mutation. Heimdall is read-only and outside admission, mutation, recovery, rollback, and
re-arm. Legacy actors retain mandatory Verdandi receipts and no automatic rollback; Verdandi's
separate recovery/purpose gate remains in force for them.

## Consequences

- Per-change human approval is removed only for a future, armed, fully covered instance of the seven
  classes above; all other changes retain owner control.
- The owner retains the kill switch, protected lanes, software-development/PR review authority,
  and recovery/firmware/credential control.
- A controller that sees incomplete, stale, malformed, unknown, or observer-only evidence must
  fail closed and leave/return the class disarmed; it may create a proposal but not a mutation.
- V1 schemas, fixtures, and validator remain byte-stable for historical attempts.
  A v1 attempt finishes or recovers under its original digest; it is never
  rewritten as v2. New consumers pin the entire v2 constitution/coverage/journal
  bundle, and any cross-epoch mixture fails closed.
- The v2 production coverage registry is globally disarmed and the production
  owner authorization remains unconfigured. Contract publication changes no
  runtime authority. Reversal before downstream migration is a normal Git
  revert; after migration, consumers must repin v1 only for historical recovery,
  never to resume new v1 promotion.
- Implementations belong in their owning repositories. W1 proves the L4 configuration plane and
  the micro-routing axis of L5; W2 adds the Brokkr journal/recovery seam; W3 may seek one non-pillar
  L4 maintenance canary only after fault injection.
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

`make test-autonomy-contract` retains the immutable v1 regression lane.
`make test-autonomy-contract-v2` runs closed-schema validation plus byte-valid happy commit, R-exact
revert/disarm, R-forward recover/quarantine/disarm, and terminally-blocked fixtures. Its adversarial
mutations cover protected-lane substitution, commands/private locators, binding identity drift,
unknown-state re-arm, canary expansion, recovery-worker impersonation, observer actuation,
real clock advancement, exact and one-millisecond timing boundaries, excessive
apply duration, short watch, excess commit grace, total-deadline overflow,
invalid calendar instants, cross-owner actuation, forged or
widening recovery transitions, duplicate coverage, owner misalignment, aggregate L4/L5 readiness,
and disarmed coverage claiming armed state.
`make test-autonomy-contract-doc` retains the public boundary text.

## Follow-up

This ADR does not arm a controller. Each owning implementation must add its own tests and evidence,
then receive independent review and green CI before a separate admissibility decision. Any need to
alter a protected lane, add a class, or weaken a floor requires an owner-approved successor ADR and
a new versioned constitution.
