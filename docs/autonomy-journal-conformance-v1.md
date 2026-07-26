# ADR-008 journal conformance v1

W1 (gille-inference) and W2 (Brokkr) export one `autonomous-mutation-journal`
envelope per attempted mutation and validate it with Grimnir's
[`autonomous-mutation-journal-v1.schema.json`](autonomous-mutation-journal-v1.schema.json)
plus `make test-autonomy-contract`. The only v1 phase vocabulary is `prepare`,
`apply`, `verify`, `watch`, `commit`, `unknown`, `revert`, `recover`,
`quarantine`, `disarm`, and `terminally-blocked`.

Before either implementation is admissible it must also call
`verify-autonomy-owner-authorization.mjs` with an independently pinned owner
public key, and verify the signed runtime-narrowing ledger. An owner signature
binds the exact constitution, coverage intent, owner-attestation registry, and
recovery-worker registry digests. A recovery receipt is valid only when its
Ed25519 key is bound by that signed recovery registry and it narrows its exact
target from an armed state to `shadow`; it cannot widen, re-arm, or address a
different target. Production remains disarmed until those artifacts are
provisioned by the owner.

The checked-in W0 fixtures provide both R-exact and R-forward examples for
consumer conformance. They are test vectors, not deployed authorization.

The `admission` values used by the reference predicate are **verifier-derived
proofs, never caller-supplied claims**: owner authorization comes from the
external-pin verifier; effective target state is owner intent minus verified
signed narrowing; and evidence, journal health, rate/window, silence, and
trusted watchdog time come from their authoritative stores and clocks. A
consumer must fail closed if it cannot independently derive any one of them.

The current owner-authorization digest/sequence checkpoint and the recovery
ledger tail checkpoint must live in an owner- or recovery-append-only store,
respectively, outside controller write access. Controllers may read them to
verify admission; they may not replace either checkpoint, registry, or ledger.
For a recovery demotion, append and durably verify the signed narrowing entry
first, then advance the protected tail checkpoint. A crash or disagreement
between those steps is fail-closed: retain shadow/disarmed behavior, repair by
replaying the signed append from the recovery store, and only then advance the
checkpoint. Never reconstruct a tail from controller-visible files.
