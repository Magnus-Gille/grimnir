# ADR-008 — Constitutional, journaled autonomy for Levels 4 and 5

**Status:** accepted — W0 contract only, 2026-07-26. It supersedes manual promotion for the bounded operating-loop classes below, never protected-lane owner control.

Future execution is permitted only after validating a digest-bearing v1 constitution, an explicitly armed coverage record, fresh evidence, and the authoritative domain journal. **W0 is disarmed**: it provides no executor, policy service, worker, deployment path, Heimdall actuator, or Verdandi dependency.

The constitution owns classes, bounds, floors, identities, postconditions, and fault-injection requirements, not routine tunables. Its canonical digest omits `constitution_digest`; coverage is likewise digest-bound.

- **R-exact** restores the immutable recorded baseline and verifies its exact digest. Routing is the Level 5 target.
- **R-forward** makes a bounded, predeclared recovery to a defined safe state when exact restoration is unavailable. It uses a separate least-privilege recovery worker that always disarms after acting. No-reboot `security`/`bugfix` maintenance on a non-pillar canary is the Level 4 target.

Unknown/partial state is never retry or re-arm: journal `unknown`, recover, then end `disarmed` or `terminally-blocked`. Receipts are content-blind, chained, and bind constitution, baseline, postconditions, deadline, recovery, and worker identity. Verdandi is an optional asynchronous projection. Heimdall observes only and is outside admission, mutation, rollback, and recovery.

Permanent protected lanes: credentials/authentication, owner policy, constitution/safety gates, code/deployments, privacy/retention/erasure, firmware, remote recovery, model-weight training, irreversible external actions, and package downgrade. They may be proposed but never mechanically promoted.

Coverage states are `out-of-scope`, `protected`, `shadow`, `armed-canary`, and `armed-fleet`. Current W0 is globally disarmed; route-only machinery is not system-wide completion. W1 proves exact routing rollback; W2 adds Brokkr's supervised journal/recovery seam; W3 can arm one non-pillar canary after fault injection; W4/W5 require their own verification, review, CI, and coverage gates.
